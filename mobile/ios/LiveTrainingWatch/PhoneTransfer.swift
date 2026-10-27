import Foundation
import WatchConnectivity

/// Sends finished sessions to the iPhone app with WatchConnectivity file transfers. These queue in
/// the background and retry until delivered, also when the iPhone app isn't open. A file is deleted
/// from the watch once the iPhone has it.
final class PhoneTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var pending = 0
    @Published private(set) var lastMessage: String?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Queues every complete session file that isn't already on its way. CSV first, JSON last.
    func sendAll() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            DispatchQueue.main.async { self.lastMessage = "Waiting for iPhone…" }
            return
        }
        let inFlight = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        guard let dir = try? WatchRecorder.sessionsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for json in files where json.pathExtension == "json" && Self.isComplete(json) {
            let csv = json.deletingPathExtension().appendingPathExtension("csv")
            for file in [csv, json]
            where FileManager.default.fileExists(atPath: file.path) && !inFlight.contains(file.lastPathComponent) {
                session.transferFile(file, metadata: ["name": file.lastPathComponent])
            }
        }
        updatePending()
    }

    private static func isComplete(_ json: URL) -> Bool {
        guard let data = try? Data(contentsOf: json),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return meta["complete"] as? Bool ?? false
    }

    private func updatePending() {
        let n = WCSession.default.outstandingFileTransfers.count
        DispatchQueue.main.async { self.pending = n }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if activationState == .activated { sendAll() }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        if let error {
            DispatchQueue.main.async { self.lastMessage = "Send failed (\(name)): \(error.localizedDescription)" }
        } else {
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            DispatchQueue.main.async { self.lastMessage = "Sent to iPhone ✓" }
        }
        updatePending()
    }
}
