import SwiftUI

private let accent = Color(red: 0.30, green: 0.79, blue: 0.94)
private let heart = Color(red: 1.0, green: 0.30, blue: 0.43)

private func pretty(_ slug: String) -> String {
    let s = slug.replacingOccurrences(of: "_", with: " ")
    return s.prefix(1).uppercased() + s.dropFirst()
}

struct ContentView: View {
    @EnvironmentObject var recorder: WatchRecorder

    var body: some View {
        if recorder.isRecording {
            RecordingView()
        } else {
            SetupView()
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var recorder: WatchRecorder
    @EnvironmentObject var transfer: PhoneTransfer

    var body: some View {
        List {
            Picker("Sport", selection: $recorder.sport) {
                ForEach(WatchRecorder.sportOptions, id: \.self) { Text(pretty($0)).tag($0) }
            }
            Picker("Worn on", selection: $recorder.placement) {
                ForEach(WatchRecorder.placementOptions, id: \.self) { Text(pretty($0)).tag($0) }
            }
            Picker("Rate", selection: $recorder.rate) {
                ForEach(WatchRecorder.Rate.allCases) { Text($0.rawValue).tag($0) }
            }

            Button {
                recorder.start()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(accent)
            .listRowBackground(accent.opacity(0.25).clipShape(RoundedRectangle(cornerRadius: 12)))

            Section {
                Text(recorder.status).font(.footnote).foregroundStyle(.secondary)
                if transfer.pending > 0 {
                    Text("\(transfer.pending) file(s) waiting for iPhone").font(.footnote)
                }
                if let message = transfer.lastMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Send to iPhone again") { transfer.sendAll() }.font(.footnote)
            }
        }
        .navigationTitle("Live Training")
    }
}

struct RecordingView: View {
    @EnvironmentObject var recorder: WatchRecorder
    @State private var confirmStop = false

    private var clock: String {
        let s = Int(recorder.elapsed)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("REC · \(pretty(recorder.placement))").font(.caption2).foregroundStyle(.secondary)
                }
                Text(clock)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(heart)
                    Text(recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.title3.bold()).monospacedDigit()
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(recorder.accCount)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    Button("Sync") { recorder.mark("sync_jumps") }
                    Button("Mark") { recorder.mark("mark") }
                }
                Button(role: .destructive) {
                    confirmStop = true
                } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(.red)
            }
        }
        .confirmationDialog("End session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop and save", role: .destructive) { recorder.stop() }
            Button("Keep recording", role: .cancel) {}
        }
    }
}
