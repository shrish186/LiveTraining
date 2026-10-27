import CoreMotion
import Foundation
import HealthKit

/// Records one session on the watch: accelerometer + gyroscope (worn on the leg or wrist) and
/// heart rate. A HealthKit workout session keeps the app running with the screen off.
///
/// Output: <Documents>/sessions/<session_id>.csv + .json in the session format, source `apple_watch`.
/// Times: motion uses the sensor clock (seconds since boot, monotonic), heart rate uses its
/// sample date; both are relative to the same session start.
final class WatchRecorder: NSObject, ObservableObject {
    enum Rate: String, CaseIterable, Identifiable {
        case standard = "100 Hz"
        case high = "800 Hz"
        var id: String { rawValue }
    }

    static let source = "apple_watch"
    static let sportOptions = ["general", "soccer", "running", "basketball", "tennis", "cycling", "gym"]
    static let placementOptions = ["ankle", "shin", "thigh", "wrist", "upper_arm", "waist"]
    private static let gravity = 9.80665

    // Choices (persisted)
    @Published var sport = UserDefaults.standard.string(forKey: "sport") ?? "soccer" {
        didSet { UserDefaults.standard.set(sport, forKey: "sport") }
    }
    @Published var placement = UserDefaults.standard.string(forKey: "placement") ?? "ankle" {
        didSet { UserDefaults.standard.set(placement, forKey: "placement") }
    }
    @Published var rate = Rate(rawValue: UserDefaults.standard.string(forKey: "rate") ?? "") ?? .standard {
        didSet { UserDefaults.standard.set(rate.rawValue, forKey: "rate") }
    }

    // Live state for the UI
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var accCount = 0
    /// Accelerometer samples per second actually arriving, over the last few seconds.
    @Published private(set) var accRateHz: Int?
    private var countHistory: [(TimeInterval, Int)] = []
    @Published private(set) var heartRate: Double?
    @Published private(set) var status = "Ready"

    /// Called after a session's files are complete (the app sends them to the iPhone).
    var onFinished: (() -> Void)?

    private let healthStore = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "livetraining.motion"
        return q
    }()
    private var batchedManager: AnyObject?  // CMBatchedSensorManager (watchOS 10+)
    private var batchTasks: [Task<Void, Never>] = []

    /// Serial queue that owns `writer`. Every write goes through it.
    private let io = DispatchQueue(label: "livetraining.writer")
    private var writer: SessionWriter?
    private var finalCounts: [String: Int] = [:]

    private var uiTimer: Timer?
    private var sessionId = UUID().uuidString.lowercased()
    private var startDate = Date()
    private var startUptime: TimeInterval = 0
    private var durationMs = 0
    private var actualRateHz = 100

    static func sessionsDirectory() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Permissions

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [heartRateType]
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] ok, error in
            if !ok {
                DispatchQueue.main.async {
                    self?.status = "Health access needed: \(error?.localizedDescription ?? "denied")"
                }
            }
        }
    }

    // MARK: - Start / stop

    func start() {
        guard !isRecording else { return }
        sessionId = UUID().uuidString.lowercased()
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: sport)
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            workout = session
            self.builder = builder

            let csv = try Self.sessionsDirectory().appendingPathComponent("\(sessionId).csv")
            let newWriter = try SessionWriter(csvURL: csv)
            startDate = Date()
            startUptime = ProcessInfo.processInfo.systemUptime
            durationMs = 0
            io.sync {
                writer = newWriter
                newWriter.event(0, Self.source, "session_start")
            }

            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }
            startMotion()
            isRecording = true
            countHistory = []
            accRateHz = nil
            status = "Recording"
            heartRate = nil
            try writeMetadata(complete: false)
            uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        } catch {
            status = "Could not start: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        uiTimer?.invalidate()
        uiTimer = nil
        stopMotion()

        let endMs = tMs(uptime: ProcessInfo.processInfo.systemUptime)
        durationMs = endMs
        io.sync {
            writer?.event(endMs, Self.source, "session_end")
            finalCounts = writer?.counts ?? [:]
            writer?.close()
            writer = nil  // late motion callbacks become no-ops
        }

        workout?.end()
        let builder = self.builder
        builder?.endCollection(withEnd: Date()) { _, _ in
            builder?.finishWorkout { _, _ in }  // saves the workout to Health
        }

        do {
            try writeMetadata(complete: true)
            status = "Saved, sending to iPhone…"
            onFinished?()
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Adds an event row (e.g. "sync_jumps") at the current time.
    func mark(_ label: String) {
        guard isRecording else { return }
        let t = tMs(uptime: ProcessInfo.processInfo.systemUptime)
        io.async { self.writer?.event(t, Self.source, label) }
    }

    // MARK: - Motion

    private func tMs(uptime: TimeInterval) -> Int {
        max(0, Int(((uptime - startUptime) * 1000).rounded()))
    }

    private func startMotion() {
        if rate == .high {
            if #available(watchOS 10.0, *) {
                if CMBatchedSensorManager.isAccelerometerSupported {
                    startBatched()
                    return
                }
            }
            DispatchQueue.main.async { self.status = "800 Hz not supported here, using 100 Hz" }
        }
        actualRateHz = 100
        motion.accelerometerUpdateInterval = 1.0 / 100
        motion.deviceMotionUpdateInterval = 1.0 / 100
        motion.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            let t = self.tMs(uptime: data.timestamp)
            self.io.async {
                self.writer?.vector(t, Self.source, "acc", a.x * Self.gravity, a.y * Self.gravity, a.z * Self.gravity)
            }
        }
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] dm, _ in
                guard let self, let dm else { return }
                let r = dm.rotationRate
                let t = self.tMs(uptime: dm.timestamp)
                self.io.async { self.writer?.vector(t, Self.source, "gyro", r.x, r.y, r.z) }
            }
        }
    }

    /// High-rate batches (accelerometer ~800 Hz, device motion ~200 Hz). Needs an active workout.
    @available(watchOS 10.0, *)
    private func startBatched() {
        actualRateHz = 800
        let manager = CMBatchedSensorManager()
        batchedManager = manager
        batchTasks.append(Task.detached { [weak self] in
            do {
                for try await batch in manager.accelerometerUpdates() {
                    guard let self else { return }
                    let rows = batch.map { (self.tMs(uptime: $0.timestamp), $0.acceleration) }
                    self.io.async {
                        for (t, a) in rows {
                            self.writer?.vector(t, Self.source, "acc", a.x * Self.gravity, a.y * Self.gravity, a.z * Self.gravity)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { self?.status = "Accelerometer stopped: \(error.localizedDescription)" }
            }
        })
        if CMBatchedSensorManager.isDeviceMotionSupported {
            batchTasks.append(Task.detached { [weak self] in
                do {
                    for try await batch in manager.deviceMotionUpdates() {
                        guard let self else { return }
                        let rows = batch.map { (self.tMs(uptime: $0.timestamp), $0.rotationRate) }
                        self.io.async {
                            for (t, r) in rows { self.writer?.vector(t, Self.source, "gyro", r.x, r.y, r.z) }
                        }
                    }
                } catch {
                    DispatchQueue.main.async { self?.status = "Gyroscope stopped: \(error.localizedDescription)" }
                }
            })
        }
    }

    private func stopMotion() {
        motion.stopAccelerometerUpdates()
        motion.stopDeviceMotionUpdates()
        // Cancelling the tasks ends the batched update streams, which stops the sensors.
        batchTasks.forEach { $0.cancel() }
        batchTasks.removeAll()
        batchedManager = nil
    }

    private func tick() {
        elapsed = Date().timeIntervalSince(startDate)
        io.async {
            let n = self.writer?.counts["\(Self.source)/acc"] ?? 0
            DispatchQueue.main.async {
                self.accCount = n
                let now = self.elapsed
                self.countHistory.append((now, n))
                if self.countHistory.count > 7 { self.countHistory.removeFirst() }  // ~3 s at 2 ticks/s
                if let first = self.countHistory.first, now - first.0 >= 2 {
                    self.accRateHz = Int((Double(n - first.1) / (now - first.0)).rounded())
                }
            }
        }
    }

    // MARK: - Metadata

    private func writeMetadata(complete: Bool) throws {
        var counts: [String: Int] = [:]
        io.sync { counts = complete ? finalCounts : (writer?.counts ?? [:]) }
        var kinds: [String] = []
        var busiest = 0
        for (key, n) in counts {
            let parts = key.split(separator: "/")
            guard parts.count == 2, parts[1] != "event" else { continue }
            kinds.append(String(parts[1]))
            busiest = max(busiest, n)
        }
        let seconds = Double(durationMs) / 1000
        var source: [String: Any] = ["id": Self.source, "kinds": kinds.sorted()]
        source["sample_rate_hz"] = seconds > 0 ? (Double(busiest) / seconds * 10).rounded() / 10 : NSNull()

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let meta: [String: Any] = [
            "format_version": 1,
            "session_id": sessionId,
            "athlete_id": NSNull(),  // filled in by the iPhone app on receipt
            "sport": sport,
            "session_type": "training",
            "started_at": iso.string(from: startDate),
            "app_version": "0.1.0-watch",
            "device_model": "Apple Watch, watchOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "sources": [source],
            "placement": placement,
            "notes": "",
            "duration_ms": durationMs,
            "complete": complete,
            "requested_rate_hz": actualRateHz,
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: try Self.sessionsDirectory().appendingPathComponent("\(sessionId).json"), options: .atomic)
    }

    /// Only tells the watch which workout type to log in Health. Unknown sports log as "other".
    private static func activityType(for sport: String) -> HKWorkoutActivityType {
        switch sport {
        case "soccer": return .soccer
        case "running": return .running
        case "basketball": return .basketball
        case "tennis": return .tennis
        case "cycling": return .cycling
        case "gym": return .traditionalStrengthTraining
        default: return .other
        }
    }
}

// MARK: - HealthKit delegates

extension WatchRecorder: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.status = "Workout error: \(error.localizedDescription)" }
    }
}

extension WatchRecorder: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let stats = workoutBuilder.statistics(for: heartRateType),
              let quantity = stats.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let date = stats.mostRecentQuantityDateInterval()?.end ?? Date()
        let t = max(0, Int((date.timeIntervalSince(startDate) * 1000).rounded()))
        io.async { self.writer?.scalar(t, Self.source, "hr", bpm) }
        DispatchQueue.main.async { self.heartRate = bpm }
    }
}
