import SwiftUI

@main
struct LiveTrainingWatchApp: App {
    @StateObject private var recorder = WatchRecorder()
    @StateObject private var transfer = PhoneTransfer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .environmentObject(transfer)
                .onAppear {
                    let sender = transfer
                    recorder.onFinished = { sender.sendAll() }
                    transfer.activate()
                    recorder.requestAuthorization()
                }
        }
    }
}
