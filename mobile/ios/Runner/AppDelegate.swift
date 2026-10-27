import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WatchSessionReceiver.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Receives sessions recorded by the Apple Watch app (mobile/ios/LiveTrainingWatch) and saves them
/// to Documents/sessions, the same folder the Flutter app records into. The Sessions tab then lists
/// and uploads them like phone sessions. No Flutter plugin needed.
final class WatchSessionReceiver: NSObject, WCSessionDelegate {
  static let shared = WatchSessionReceiver()

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  private var sessionsDirectory: URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("sessions", isDirectory: true)
  }

  // Called on a background queue. The file must be moved before this returns.
  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    guard let name = file.metadata?["name"] as? String,
          !name.contains("/"), name.hasSuffix(".csv") || name.hasSuffix(".json") else { return }
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
      let destination = sessionsDirectory.appendingPathComponent(name)
      if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
      if name.hasSuffix(".json") {
        try Self.copyAddingAthleteId(from: file.fileURL, to: destination)
      } else {
        try fm.moveItem(at: file.fileURL, to: destination)
      }
    } catch {
      NSLog("LiveTraining: could not save watch file \(name): \(error)")
    }
  }

  /// The watch doesn't know the athlete ID, so take it from the phone app's settings.
  /// shared_preferences stores it in UserDefaults as "flutter.athlete_id".
  private static func copyAddingAthleteId(from source: URL, to destination: URL) throws {
    let data = try Data(contentsOf: source)
    guard var meta = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      try data.write(to: destination, options: .atomic)
      return
    }
    if meta["athlete_id"] == nil || meta["athlete_id"] is NSNull,
       let id = UserDefaults.standard.object(forKey: "flutter.athlete_id") as? NSNumber {
      meta["athlete_id"] = id.intValue
    }
    let out = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
    try out.write(to: destination, options: .atomic)
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
               error: Error?) {}
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
