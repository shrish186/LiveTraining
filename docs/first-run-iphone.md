# First run on an iPhone (macOS)

From an empty `backend/.env` to "uploaded my first session and ran the analysis".
Allow about 45 minutes the first time, mostly installing Xcode.

**You need:** a Mac, an iPhone with its cable, your WHOOP strap, and one Wi-Fi network that both the
Mac and the iPhone are on.

## A. Tools on the Mac (once)

1. **Xcode:** install it from the App Store, open it once, accept the license, and let it install
   the iOS platform. Then in Terminal:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```
2. **Homebrew** (if you don't have it): see <https://brew.sh>. Then:
   ```bash
   brew install --cask flutter       # or follow https://docs.flutter.dev/get-started/install/macos
   brew install cocoapods
   brew install python@3.12          # macOS's own python3 is 3.9, too old for the backend
   ```
   Flutter now uses Swift Package Manager for these plugins, so CocoaPods may never be used, but
   `flutter doctor` expects it.
3. Run **`flutter doctor`**. You need ✓ next to **Flutter** and **Xcode**. ✗ for Android toolchain,
   Chrome or Android Studio is fine.
4. Get the code:
   ```bash
   git clone https://github.com/shrish186/LiveTraining.git
   cd LiveTraining
   ```

## B. Backend and WHOOP (on the Mac)

5. **Register a WHOOP app** at <https://developer-dashboard.whoop.com>:
   - Redirect URL, exactly: `http://localhost:8000/auth/whoop/callback`
   - Scopes: `read:recovery`, `read:cycles`, `read:sleep`, `read:workout`, `read:profile`,
     `read:body_measurement`
   - Copy the Client ID and Client Secret.
6. **Fill in `backend/.env`**:
   ```bash
   cd backend
   cp .env.example .env
   open -e .env                       # paste WHOOP_CLIENT_ID and WHOOP_CLIENT_SECRET, save
   ```
   `.env` is gitignored, so never commit it.
7. **Start the backend:** run `./run_dev.sh`.
   - It sets everything up and prints:
     ```
     Backend URL for the app:  http://192.168.x.x:8000
     ```
     Write that URL down.
   - If macOS asks to allow incoming connections for Python, click **Allow**.
   - Leave this Terminal window running.
8. **Connect WHOOP, in the Mac's browser** (not on the phone):
   - Open <http://localhost:8000> and click **Connect WHOOP**.
   - Log in and approve.
   - You'll see **"Connected as <name>. Athlete ID: 1"**. The ID is also listed on
     <http://localhost:8000>.

## C. App on the iPhone

9. **Developer Mode:**
   - Plug the iPhone into the Mac, unlock it, and tap **Trust This Computer**.
   - On the iPhone, go to Settings › Privacy & Security › **Developer Mode** and turn it on. The
     phone restarts; confirm.
   - If Developer Mode isn't listed, open Xcode › Window › Devices and Simulators once with the
     phone plugged in.
10. **Signing with your free Apple ID:**
    ```bash
    cd mobile
    flutter pub get
    open ios/Runner.xcworkspace
    ```
    - In Xcode: click **Runner** (blue icon, top left) › target **Runner** › **Signing &
      Capabilities**.
    - Tick **Automatically manage signing**.
    - **Team** › **Add an Account…** › sign in with your Apple ID, then pick **"<Your Name> (Personal
      Team)"**.
    - The bundle identifier is `com.shrish186.livetraining`. If Xcode says it's unavailable, change
      it in **`mobile/ios/Flutter/AppIdentity.xcconfig`** (one line), e.g.
      `com.yourname.livetraining`.
    - You can close Xcode afterwards.
11. **Install and run:**
    ```bash
    flutter devices            # your iPhone should be listed
    flutter run --release      # first build takes a few minutes
    ```
    Use `--release`: on iOS a debug build can't be opened from the home screen once you unplug
    the phone.
12. **"Untrusted Developer"** on first launch:
    - On the iPhone: Settings › General › **VPN & Device Management** › your Apple ID › **Trust**.
    - Then open the app (or rerun `flutter run --release`).
13. **Permission prompts:** allow them.
    - **Local Network**: appears the first time the app talks to the backend.
    - **Bluetooth**: appears when you tap *Connect WHOOP HR*.
    - **Motion & Fitness** may not appear at all. That's normal, because iOS gives raw accelerometer
      data without it.

## D. First session

14. **In the app, Settings tab:**
    - Backend URL: the one from step 7.
    - Tap **Test connection** and wait for "✓ Connected".
    - Athlete ID: the number from step 8. Tap **Save**.
    - Pick your default sport and sensor placement.
15. **In the WHOOP app:** turn on **Heart Rate Broadcast** in the strap's device settings, and
    wear the strap.
16. **Live tab:**
    - Tap **Connect WHOOP HR**. The big BPM number should start moving.
    - The recovery card shows today's recovery.
    - Motion moves when you shake the phone.
17. **Record:**
    - Tap **Start session**.
    - Do 3 jumps and tap **Mark sync jumps**.
    - Train. Use **Mark event** for markers.
    - **Hold to stop** (a short tap won't stop it).
    - Keep the app open on screen while recording.
18. **Upload:**
    - Sessions tab › cloud icon › **Uploaded** ✓.
    - <http://localhost:8000> now shows "Sessions uploaded: 1".
19. **Analyse, on the Mac:**
    ```bash
    cd analysis
    python3.12 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
    ls ../backend/data/sessions/
    python analyze_session.py ../backend/data/sessions/<session_id>.csv
    open ../backend/data/sessions/<session_id>.png
    ```

## Free signing expires after 7 days

With a free Apple ID, the app stops opening after 7 days. To renew it:
1. Plug the phone in.
2. Run `cd mobile && flutter run --release` again.

Installing over the existing app keeps your recorded sessions. Deleting the app deletes them, so
upload first. Free accounts also allow at most 3 sideloaded apps per device.

## Troubleshooting

**CocoaPods errors** ("CocoaPods not installed", "pod install failed", ffi or Ruby errors)
- `brew install cocoapods` (use Homebrew's version, not `sudo gem install`).
- Then:
  ```bash
  cd mobile && flutter clean && rm -rf ios/Pods ios/Podfile.lock && flutter pub get
  cd ios && pod repo update && cd .. && flutter run --release
  ```
- Swift Package errors: in Xcode, File › Packages › **Reset Package Caches**, and also
  `rm -rf ~/Library/Developer/Xcode/DerivedData`.

**Signing or provisioning errors**
- *"Signing for Runner requires a development team"*: pick your Personal Team (step 10).
- *"Failed to register bundle identifier" / "not available"*: change `APP_BUNDLE_ID` in
  `mobile/ios/Flutter/AppIdentity.xcconfig`, then rerun.
- *"Maximum App ID limit reached"*: free accounts get 10 new IDs per 7 days. Reuse an earlier ID.
- *"Device is not registered" / "Could not launch"*: unlock the phone, keep it plugged in, open Xcode ›
  Window › Devices and Simulators and wait until the phone is ready ("Preparing device…" can take
  minutes the first time).
- *"iPhone is not available… Developer Mode disabled"*: see step 9.

**"Untrusted Developer"**
- Settings › General › VPN & Device Management › your Apple ID › Trust (step 12).

**Local network blocked / backend unreachable** (Test connection shows the exact error)
- *Connection refused*: the Mac was reached, but `run_dev.sh` isn't running or is on another port.
- *No route to host* or *timed out*:
  - Allow it in Settings › Privacy & Security › **Local Network** › Live Training.
  - Check that both devices are on the **same** Wi-Fi.
  - Check the macOS firewall: System Settings › Network › Firewall, allow Python.
- **Campus, office or guest Wi-Fi often blocks device-to-device traffic.** Use the iPhone's
  **Personal Hotspot** instead:
  1. Join it from the Mac.
  2. Rerun `./run_dev.sh` to get the new IP (usually `172.20.10.x`).
  3. Put that URL in the app.
- The Mac's IP can change after a reconnect. Rerun `run_dev.sh` and update the URL in the app.
- To check from the Mac itself: `curl http://<that-ip>:8000/health` should print `{"status":"ok"}`.

**WHOOP HR not showing**
- Heart Rate Broadcast must be **on** in the WHOOP app, and the strap must be worn.
- The broadcast connects to one device at a time. Disconnect other apps or gym equipment using it.
- Bluetooth must be on, and allowed for Live Training (Settings › Privacy & Security › Bluetooth).
- Tap Disconnect, then Connect again. If needed, toggle Bluetooth off and on.

**WHOOP connect errors**
- *Redirect URI mismatch*: the WHOOP dashboard redirect URL must be exactly
  `http://localhost:8000/auth/whoop/callback`.
- *"Link expired or invalid"*: the login link is valid for 10 minutes. Click Connect WHOOP again.
- The recovery card says WHOOP isn't connected: reconnect at <http://localhost:8000> on the Mac.

**Backend won't start**
- *"WHOOP_CLIENT_SECRET empty in backend/.env"*: fill it in (step 6).
- *"Python 3.11 or newer is required"*: `brew install python@3.12`.
