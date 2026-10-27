# Apple Watch as the motion sensor

The watch app records **accelerometer + gyroscope** (and watch heart rate) during a workout and
sends the session to the iPhone app when you stop. Strap the watch to your **lower leg** for sport
movement. WHOOP stays on your wrist for heart rate, and the phone records it.

```
watch on the lower leg (motion) ──WatchConnectivity──► iPhone app ──upload──► backend
WHOOP on the wrist (heart rate) ──BLE──► iPhone app ─┘
                                       analysis: merge_sessions.py lines the two up via sync jumps
```

Source code is in `mobile/ios/LiveTrainingWatch Watch App/`. The watch target is already in the Xcode project. The iPhone side is `WatchSessionReceiver` in
`mobile/ios/Runner/AppDelegate.swift`. It saves received files into the Sessions list.

## One-time setup in Xcode (already done; kept for reference)

Flutter can't create watch targets, so this was done once in Xcode and committed. On a fresh clone
you only need step 6 (Developer Mode) and step 7 (install). The steps below are how the target was created.

1. Open the project:
   ```bash
   cd ~/LiveTraining/mobile && flutter pub get && open ios/Runner.xcworkspace
   ```
2. **File › New › Target… › watchOS › App** › Next.
   - Product Name: **`LiveTrainingWatch`**
   - Team: your Personal Team
   - Choose **Watch App for Existing iOS App**, companion app **Runner**
   - Interface SwiftUI, Language Swift, untick tests and notifications
   - Finish. If asked to activate the scheme, click Activate.
3. Xcode creates a folder `ios/LiveTrainingWatch Watch App/` with two template files. Replace them
   with ours in Terminal:
   ```bash
   cd ~/LiveTraining/mobile
   cp ios/LiveTrainingWatch/*.swift "ios/LiveTrainingWatch Watch App/"
   ```
   Back in Xcode, the folder now shows 5 Swift files: `LiveTrainingWatchApp`, `ContentView`,
   `WatchRecorder`, `PhoneTransfer` and `SessionWriter`. If a file is missing from the list,
   right-click the folder, choose **Add Files…** and tick only the watch target.
4. Select the **LiveTrainingWatch Watch App** target:
   - **General › Minimum Deployments:** watchOS **10.0**
   - **Signing & Capabilities:**
     - Team: your Personal Team
     - **+ Capability › HealthKit**
     - **+ Capability › Background Modes**, then tick **Workout processing**
   - **Info** tab: add three rows, with any sensible text as the value:
     - `Privacy - Health Share Usage Description`
     - `Privacy - Health Update Usage Description`
     - `Privacy - Motion Usage Description`
   - **Build Settings › Swift Language Version:** **Swift 5** (if it says Swift 6)
   - **Build Settings › All › Supported Platforms:** set **Debug, Release and Profile** to
     **watchOS**. Flutter's project template sets `SUPPORTED_PLATFORMS = iphoneos` at the project
     level for Release and Profile, and the watch target inherits it. Without this override,
     `flutter run --release` compiles the watch code for iOS and fails with "… is unavailable in iOS".
   - If the Info tab drops new rows, add the privacy texts under **Build Settings › All**, searching
     for "Usage Description".
5. Select the **Runner** target › **Build Phases**: drag **Embed Watch Content** above
   **Thin Binary**. Without this, builds fail with "Cycle inside Runner".
6. On the watch: **Settings › Privacy & Security › Developer Mode** › on. It appears after the
   watch has been seen by Xcode once: keep it unlocked, on the charger, near the paired iPhone.
7. Install (quit Xcode first with ⌘Q):
   - `flutter run --release` builds the iPhone app with the watch app embedded. You should see
     "Watch companion app found".
   - **Watch:** on the iPhone, open the **Watch** app › scroll to **Available Apps** › **Live
     Training** › **Install**. Alternatively, run the **LiveTrainingWatch Watch App** scheme from
     Xcode with the watch as destination. That needs the watch visible in Window › Devices and
     Simulators and Developer Mode on.
   - If Xcode reports "Missing package product 'FlutterGeneratedPluginSwiftPackage'", run
     `flutter build ios --config-only --release` and reopen Xcode. Building with `flutter run`
     avoids it.
8. Commit what Xcode created, so it's not lost:
   ```bash
   git pull
   git add ios/Runner.xcodeproj "ios/LiveTrainingWatch Watch App" && git commit -m "Add watch target" && git push
   ```
   From then on, edit the watch code in `ios/LiveTrainingWatch Watch App/`.

## Recording a session

1. **Watch settings for leg wear:** in the Watch app on the iPhone › Passcode › turn **Wrist
   Detection** off. Otherwise the watch locks when it's not on a wrist. Turn it back on afterwards.
2. Strap the watch tightly to the outside of the lower leg, a few cm above the ankle bone, on the
   **non-kicking leg**. Not for contact play or matches.
3. **Watch:**
   - Pick the sport, **Worn on: Ankle** and the rate (100 Hz, or 800 Hz for kicks and impacts).
   - Tap **Start**. Allow Health and Motion access the first time.
4. **Phone:** on the Live tab, connect WHOOP HR, set *Sensor on* to `ankle`, and tap **Start session**.
5. **Do 3 vertical jumps, then tap *Sync jumps* on the phone.** Both devices feel the jumps, which
   is how the recordings are lined up to the millisecond.
6. Train. Then stop the watch (**Stop › Stop and save**) and the phone (**Hold to stop**).
7. Keep the phone nearby with the app open. The watch sends its files in the background, and the
   session appears in the **Sessions** tab tagged **Apple Watch**. Upload both sessions.

## Analysis

```bash
cd ~/LiveTraining/analysis && . .venv/bin/activate
ls -t ../backend/data/sessions/*.csv | head -2        # the phone and the watch session
python merge_sessions.py ../backend/data/sessions/<phone_id>.csv ../backend/data/sessions/<watch_id>.csv
python analyze_session.py output/merged_<phone_id>.csv
```

`merge_sessions.py` prints how it aligned the two: by **sync jumps** (good), or by **clock only**
(no clear jump match, usually within a few tens of ms). The merged analysis uses the watch for
motion and WHOOP for heart rate, with the `ankle` thresholds from `profiles/sport_profiles.yaml`.
Those thresholds are starting guesses, so expect to tune them after a few sessions.

## Troubleshooting

- **"Personal development teams do not support HealthKit"** (or a similar signing error): the
  watch app needs HealthKit for its workout session, which keeps it running with the screen off.
  If your free Apple ID can't sign it, a paid Apple Developer account is needed.
- **Compile errors in the watch files:** this code was written without a Mac, so a fix or two may
  be needed. Paste the first error and I'll fix it. The parts I'm least sure of are the 800 Hz
  batched-sensor API (`CMBatchedSensorManager`) and Swift 6 concurrency checks (step 4 sets Swift 5).
- **"Cycle inside Runner"** when building: see step 5.
- **The watch session never shows up on the phone:**
  - Open the phone app and keep it in the foreground for a minute.
  - Check the watch's start screen, which shows how many files are waiting. Tap
    **Send to iPhone again**.
  - Both apps must come from the same project (the watch app is Runner's companion).
- **No motion on the watch** (the sample counter stays at 0): check Settings › Privacy & Security
  › Motion & Fitness on the iPhone.
- **800 Hz option says "not supported":** the watch falls back to 100 Hz and records anyway.
