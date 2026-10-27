# Live Training Intelligence

Live training calls for athletes in any sport ("warmed up, go", "fatigue building, cut the last
set"), from a body-worn motion sensor plus WHOOP heart rate and recovery.

**v1 is the data pipeline.** The phone records its own motion sensors (stand-in for a body-worn
sensor) and WHOOP heart rate. Sessions upload to a local backend, which also pulls WHOOP recovery
through the official API. Python scripts analyse sessions offline: efforts, HR recovery and
fatigue.

```
 WHOOP strap ──(Heart Rate Broadcast, BLE 0x180D)──┐
 Phone accelerometer + gyroscope ──────────────────┤
                                                   ▼
                                     mobile/ (Flutter) ── CSV + JSON ──► backend/ (FastAPI) ◄── WHOOP API (OAuth)
                                                                               │
                                                                               ▼
                                                                analysis/ (pandas, plots) ◄── profiles/
```

| Folder | What |
|---|---|
| `backend/` | FastAPI and SQLAlchemy: WHOOP OAuth, recovery and sleep, session upload and storage |
| `mobile/` | Flutter app (iOS and Android) |
| `analysis/` | synthetic sessions, session analysis and plots |
| `profiles/sport_profiles.yaml` | sport profiles: all sport-specific thresholds and placements |
| `docs/session-format.md` | the session file format used by all three parts |
| `docs/sample/` | example analysis output (plot and summary) from the synthetic session |

Data sources are only WHOOP's **official developer API** and WHOOP's built-in **Heart Rate
Broadcast** (the standard Bluetooth heart-rate service). Nothing reverse-engineers the strap.

---

## Quick start: see it work without any hardware (2 minutes)

```bash
cd analysis
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python make_synthetic_session.py --out output/
python analyze_session.py output/synthetic.csv     # picks up output/synthetic.json automatically
open output/synthetic.png                          # macOS; or just open the file
```

You'll see 6 detected efforts, with the last two flagged "fatigue building":

![synthetic analysis](docs/sample/synthetic_analysis.png)

---

## The app

| Today | Recording | Settings |
|---|---|---|
| ![Live tab](docs/screenshots/home_connected.png) | ![Recording](docs/screenshots/home_recording.png) | ![Settings](docs/screenshots/settings.png) |

These screenshots are rendered by `mobile/test/ui_screens_test.dart` with sample data. To
regenerate them:
`PREVIEW_DIR=../docs/screenshots PREVIEW_FONT_DIR=<folder with Inter-*.otf> flutter test test/ui_screens_test.dart`.

## 1. Register a WHOOP developer app (once)

1. Go to the WHOOP Developer Dashboard at <https://developer-dashboard.whoop.com> and sign in with your
   WHOOP account. Create a team if asked.
2. **Create app** and fill in the required fields (name, contact, privacy policy URL; any
   placeholder URL is fine for personal development).
3. **Redirect URL:** `http://localhost:8000/auth/whoop/callback`
4. **Scopes:** tick all of `read:recovery`, `read:cycles`, `read:sleep`, `read:workout`,
   `read:profile`, `read:body_measurement`. The backend also requests `offline`, which is what
   makes WHOOP issue refresh tokens.
5. Copy the **Client ID** and **Client Secret**.

Development access allows up to 10 WHOOP members per app.

## 2. Run the backend on your laptop

Needs Python 3.11 or newer. macOS's built-in `python3` is 3.9; install a newer one with
`brew install python@3.12`.

```bash
cd backend
cp .env.example .env            # then edit .env: WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET
./run_dev.sh                    # creates .venv, installs deps, prints the URL for the app, starts the server
```

- `run_dev.sh` listens on `0.0.0.0:8000` so your phone can reach the Mac over Wi-Fi, and prints the
  exact backend URL to type into the app (e.g. `http://192.168.1.23:8000`). If macOS asks whether
  to allow incoming connections for Python, click **Allow**.
- The server refuses to start if `WHOOP_CLIENT_ID` or `WHOOP_CLIENT_SECRET` is missing.
- <http://localhost:8000> shows a status page: server running, credentials configured yes/no, a
  Connect WHOOP button, and connected athletes with their IDs. API docs are at
  <http://localhost:8000/docs>.
- Tests: `.venv/bin/pytest` (63 tests, no network needed). To start manually:
  `.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`.
- Data is stored in `backend/data/` (SQLite DB and uploaded sessions; gitignored). For Postgres, set
  `DATABASE_URL=postgresql+psycopg://user:pass@host/db` and `pip install "psycopg[binary]"`.
- Run a single worker (the default). See Decisions #17.

## 3. Connect your WHOOP account

Do this in a browser **on the laptop** (the redirect URL points at `localhost`):

1. Open <http://localhost:8000/auth/whoop/login>.
2. Log in to WHOOP and approve.
3. You'll land on **"Connected as <your name>. Athlete ID: 1"**. Note the ID.

Check that it works: <http://localhost:8000/athletes/1/whoop/recovery/latest> should return today's
recovery.

## 4. Run the app on your phone

**iPhone and Mac, first time:** follow the checklist in
[docs/first-run-iphone.md](docs/first-run-iphone.md). It covers Xcode, signing, Developer Mode,
permissions and troubleshooting.

Needs the Flutter SDK (<https://docs.flutter.dev/get-started/install>). The platform folders
(`mobile/android`, `mobile/ios`) are already generated and include the permissions.

```bash
cd mobile
flutter pub get
flutter test            # 46 tests
flutter devices         # your phone should be listed
flutter run --release   # or plain `flutter run` for hot reload
```

**iPhone:**
- Needs a Mac with Xcode.
- First time: open `mobile/ios/Runner.xcworkspace` in Xcode. Under Runner → Signing &
  Capabilities, pick your Team (a free Apple ID works) and change the bundle identifier if Xcode
  says it's taken.
- On the phone, enable Settings → Privacy & Security → **Developer Mode**. After the first install,
  trust your certificate under Settings → General → VPN & Device Management.
- iOS will ask for Bluetooth and Local Network access. Allow both.

**Android:**
- Enable Developer options and **USB debugging**, then plug the phone in.
- Bluetooth permission is requested when you tap *Connect WHOOP HR*.

### Find your laptop's local IP

The phone and the laptop must be on the **same Wi-Fi**.

| OS | Command |
|---|---|
| macOS | `ipconfig getifaddr en0` |
| Linux | `hostname -I` |
| Windows | `ipconfig` → "IPv4 Address" |

### In the app

1. **Settings:**
   - Backend base URL: `http://<laptop-ip>:8000` (e.g. `http://192.168.1.23:8000`). Tap **Test
     connection**.
   - Athlete ID: the number from step 3. Tap **Save**.
   - Pick your default sport, session type and sensor placement (e.g. `phone_armband`).
2. **WHOOP app on the phone:** turn on **Heart Rate Broadcast** in the device settings.
3. **Live tab:** tap **Connect WHOOP HR**. The big BPM number starts updating, motion shows live
   magnitude, and the recovery card shows today's recovery.

## 5. Record a session

1. On the Live tab, check the Sport, Type and Sensor-on chips (tap to change for this session) and
   add notes if you like.
2. Put the phone in an armband or pocket. Tap **Start session**.
3. Do 3 quick vertical jumps and tap **Mark sync jumps**. Later this lines up an external sensor's
   clock with the phone's.
4. Train. Use **Mark event** for a quick marker, or the ✎ button for a labelled one (`drill_start`, …).
5. **Hold to stop**. A short tap only shows a hint, so a pocket touch can't end the session.

Keep the app **open and on screen** while recording. The screen stays awake automatically. iOS
pauses motion sensors for background apps.

## 6. Upload it

**Sessions tab** → tap the cloud icon on the session. The status changes to *Uploaded*.

Uploaded files go to `backend/data/sessions/<session_id>.csv` and `.json`. They're also available at:
- `GET /sessions` (filters: `?athlete_id=1&sport=soccer`)
- `GET /sessions/<id>`
- `GET /sessions/<id>/csv`

## 7. Analyse it

```bash
cd analysis && . .venv/bin/activate
ls ../backend/data/sessions/
python analyze_session.py ../backend/data/sessions/<session_id>.csv                 # profile from metadata sport
python analyze_session.py ../backend/data/sessions/<session_id>.csv --profile general
```

The console prints efforts, HR recovery 60 s after each effort, and the fatigue verdict. A PNG is
written next to the CSV (or to `--out <png>`).

Phone-in-armband magnitudes differ from the synthetic data, so tune the thresholds on real
sessions with the check below.

### Check detection accuracy and tune the threshold

1. Record a session with real hard efforts (sprints, intervals, jump sets). Tap **Mark** right
   after each one, and only then.
2. Upload it and run:

```bash
python validate_session.py ../backend/data/sessions/<session_id>.csv
```

It lists each marked effort as found or MISSED and each unmarked detection as EXTRA. It prints
precision (detections that were real) and recall (real efforts that were found) at the current
threshold and at every other threshold. Then it suggests a threshold: the middle of the band with
the best score, so small changes in effort don't flip the result. Change
`profiles/sport_profiles.yaml` only once a few sessions agree, and run the check per placement
(armband, shin and so on), because each placement has its own threshold.

## Live calls

While recording, the app makes these calls on the Live tab (the Coach card) and buzzes:

| Call | When |
|---|---|
| **High / Moderate / Low readiness** | At start, from today's WHOOP recovery (bands in `general.readiness`) |
| **Warmed up, go** | Once, after `warmup.min_minutes`, when HR has held `hr_above_rest_bpm` above resting for `sustain_s` (resting = WHOOP resting HR, else the lowest HR of the first minute) |
| **Effort N** | Each detected effort, with its length and peak (light buzz) |
| **Fatigue building** | An effort after the baseline window that is weaker than the early efforts and whose HR recovered slower (the same rule as the analysis) |

Every call is also written to the session file as an event (`call_warmed_up`, `call_fatigue`, and
so on), so it shows on the analysis plot.

The coach (`mobile/lib/coach/live_coach.dart`) is a streaming port of `analysis/ltlib/core.py`.
`mobile/test/coach_parity_test.dart` replays a synthetic session through it and must find the same
efforts (start and end ±1 s, peak ±2 %), HR recoveries (±2 bpm) and fatigue flags as the Python
analysis. If you change the analysis, run `python make_parity_fixture.py` in `analysis/` and make
the app's test pass again. The app reads the profiles from `mobile/assets/sport_profiles.yaml`, a
copy of `profiles/sport_profiles.yaml`. Copy the file after editing it; `analysis/tests/test_profiles_sync.py`
fails if they differ.

## Apple Watch as the motion sensor

Strap an Apple Watch to your lower leg as the body-worn motion sensor. A small watch app records
accelerometer and gyroscope data, sends the session to the iPhone, and `analysis/merge_sessions.py`
lines it up with the phone's WHOOP heart rate. Setup and use: [docs/apple-watch.md](docs/apple-watch.md).

## Adding a sport

Add a profile to `profiles/sport_profiles.yaml` with only the keys that differ from `general`
(for example `effort.threshold`, `effort.min_duration_s`, `placements.shin.threshold`). Add the
sport's name to `sportOptions` in `mobile/lib/config.dart` so it appears in the picker. No core
code changes.

## Adding a sensor (Movesense, XIAO, Polar, …)

1. Implement `MotionSource` (`mobile/lib/sources/motion_source.dart`) and emit `Sample`s with a new
   `source` id.
2. Add that id to `docs/session-format.md` and `SOURCES` in `backend/app/session_format.py`.

The recorder, upload and analysis don't change.

## Tests

```bash
cd backend  && .venv/bin/pytest # CSV validation, upload/listing, OAuth state, token refresh (httpx.MockTransport)
cd analysis && pytest          # effort detection, HR recovery, fatigue rule, profiles, validation, end-to-end
cd mobile   && flutter test    # heart-rate parser, CSV rows, recorder, motion magnitude, live coach (+ parity with the analysis)
```

---

## Decisions

Where the spec was open, I picked the simplest option that works and noted it here.

**Product and wording**
1. User-facing language is "fatigue", "readiness", "load". Nothing in the app or analysis claims to
   predict injuries.

**Sport profiles and analysis**

2. **Profiles live in top-level `profiles/`**, not `analysis/`, because the app will need them for
   live calls. Each profile is deep-merged over `general`.
3. **Thresholds depend on placement.** `placements.<name>` overrides the profile's `effort` block,
   because a shin sensor reads far more acceleration than a waist sensor for the same sprint.
4. **Motion magnitude = `| |acc| − 9.81 |`**: gravity removed, so it works in any orientation. It's
   binned to 10 Hz and smoothed with a 1 s centred rolling mean. The app's live readout uses the same
   definition (0.5 s moving average).
5. **Efforts** are runs above the profile threshold lasting at least `min_duration_s`. Runs separated
   by less than `merge_gap_s` are merged. "Peak" is the maximum smoothed magnitude in the effort.
6. **HR recovery** = HR (interpolated) at the end of the effort minus HR 60 s later. It's skipped if
   the next effort starts inside those 60 s, or if there's no HR within 5 s of either point.
7. **Fatigue rule:**
   - The baseline is the efforts that *start* in the first 15 minutes: the mean of their peaks and
     the mean of their HR recoveries.
   - A later effort is flagged when **both** of these hold for that same effort: its peak is at
     least 5% below the baseline peak, and its HR recovery is lower than the baseline recovery.
   - The first flagged effort is reported as "fatigue building from mm:ss".
   - All these numbers come from the profile.
8. **Motion load** = the integral of the smoothed magnitude, in (m/s²)·min. A simple,
   sport-agnostic load number.
9. **The app's sport list** (`mobile/lib/config.dart`) is only the picker options. Behaviour lives in
   the profiles. Later the backend can serve the profiles to the app.
10. `scipy` is listed in the analysis requirements as specified, but v1 doesn't need it.

**Session format**

11. Added `polar` as an allowed `source`, for a possible Polar Verity Sense.
12. Rows are written in arrival order and aren't guaranteed to be strictly sorted. Readers sort by
    `t_ms`.
13. **Timestamps are taken on arrival** from one `Stopwatch`, not from sensor hardware timestamps.
    That's simple and uses one clock for every stream. Expect a few ms of jitter from OS batching.
14. **The metadata JSON is written at start and again at stop.** A session cut short (app killed)
    still has a valid, uploadable CSV, marked `"complete": false`. The app also writes
    `duration_ms`, and `sample_rate_hz` is the *measured* average rate.
15. Event labels are sanitised (no commas, quotes or newlines). The app writes `session_start` and
    `session_end` automatically.

**Backend**

16. **The WHOOP login must be finished on the laptop**, because the registered redirect is
    `localhost`. The app's *Connect WHOOP account* button opens the same URL and explains this.
17. **Token refresh is serialised with an in-process lock per athlete.** The token is re-read inside
    the lock, and every new refresh token is saved immediately. Running several server processes would
    need a DB row lock (`SELECT … FOR UPDATE` on Postgres), so run one uvicorn worker.
18. **A 401 from WHOOP triggers one refresh and one retry.** A rejected refresh token returns 401
    "reconnect WHOOP".
19. **WHOOP 429** is passed through as HTTP 429 with `Retry-After`. There's no automatic retry or caching.
20. **"Latest" recovery or sleep** is the first record of the collection with `limit=1`. WHOOP
    returns the newest first.
21. **No backend authentication. Tokens are stored as plain text in the DB.** This is for local or LAN
    development only, so don't expose the server to the internet as is.
22. **Tables are created on startup** (no Alembic migrations yet).
23. **Uploads:**
    - `athlete_id` is optional, but if set, the athlete must exist.
    - Uploading the same `session_id` twice returns 409, which the app treats as "already
      uploaded".
    - The CSV is validated by streaming from a temp file, so it's never held in memory.

**Mobile**

24. **Recording only happens in the foreground with the screen kept on.** There's no background
    service yet. **Stop needs a long press.**
25. **The HR source accepts any standard BLE heart-rate device** and prefers one whose name contains
    "WHOOP". If the link drops, it reconnects automatically. WHOOP's broadcast may not include RR
    intervals; everything works without them.
26. **iOS shows its own Bluetooth prompt**, so `permission_handler` only *requests* permissions on
    Android (scan and connect on Android 12+, location on 11 and older). On iOS it only reads the
    Motion & Fitness status, to explain a missing motion stream.
27. **The app talks to the backend over plain HTTP on the LAN.**
    - Android allows cleartext traffic.
    - The app's own requests use Dart's sockets, which App Transport Security doesn't cover.
      Info.plist still sets `NSAllowsLocalNetworking` and HTTP exceptions for the private IP
      ranges (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`), so anything that does go
      through `URLSession` works too.
    - iOS asks for **Local Network** permission on first use.
    - Use HTTPS before this leaves the LAN.
28. **iOS minimum is 15.0.** Flutter 3.47 requires it; the plugins need 13.0 at most. The Podfile
    and the Xcode project both say 15.0.
29. **The iOS bundle identifier lives in one place:** `mobile/ios/Flutter/AppIdentity.xcconfig`
    (`APP_BUNDLE_ID = com.shrish186.livetraining`).
30. **The app checks the Bluetooth adapter before scanning** (off, permission denied, unsupported)
    and watches it while connected. Motion problems are detected by the absence of data: iOS gives
    raw accelerometer data without Motion & Fitness access, so that prompt may never appear, and the
    app only mentions the permission if it is explicitly denied.
31. **Extra packages:** `uuid` (session IDs). `device_info_plus` was removed: 12.4+ calls an
    Xcode 26-only API (`isiOSAppOnVision`) and fails to build on Xcode 16.4. Older versions predate
    Flutter 3.44's Swift Package Manager setup. `device_model` in the metadata is now the OS name
    and version from `dart:io` (e.g. `ios Version 18.5 (Build 22F76)`). On Android, the app
    requests Bluetooth scan/connect plus location without needing the SDK level.
    Upload status is kept in `shared_preferences`.
32. **The Apple Watch app is native Swift.** Flutter can't build watch apps. It records during a
    HealthKit workout, which keeps it running with the screen off, and sends finished sessions to
    the iPhone over WatchConnectivity. The iPhone side is a small receiver in `AppDelegate.swift` that
    writes into the same sessions folder, so it needs no Flutter plugin. The watch target is added
    once in Xcode (`docs/apple-watch.md`), because hand-editing the project file is fragile.
33. **Two-device sessions are merged in the analysis, not on the phone.** Alignment uses the
    `started_at` clocks (millisecond precision) and is refined by cross-correlating the sync jumps.
    The jump match is only used when its correlation is at least 0.5. Merged metadata names
    `motion_source` and `hr_source`. Without them, the analysis prefers a body-worn sensor over the
    phone and WHOOP heart rate over others.
34. **Lower-leg thresholds (`ankle`, `shin`) live in `general`** because they reflect where the
    sensor sits, not the sport. They're untuned starting guesses.
35. **Live calls reuse the offline rule rather than a new model.** Smoothing is trailing (the
    coach can't look ahead), which shifts times by about half a window, so the parity tolerance is
    ±1 s. HR recovery is known only once its 60 s window has passed, so a fatigue call comes about a
    minute after the effort. That is late, but it is the same evidence the analysis uses.
36. **The app bundles a copy of the profiles** (`mobile/assets/sport_profiles.yaml`) instead of
    fetching them from the backend, so calls work with no network. A test keeps the copy identical.
37. **Accuracy is checked against the athlete's own Mark taps**, because there is no ground truth
    otherwise. A tap counts for an effort when it falls between 5 s before the effort starts and 15 s
    after it ends. The validation tool only suggests a threshold. Profiles change by hand.

## Status

- **Verified in development:**
  - Backend: 64 tests passing
  - Analysis: 27 tests passing
  - Flutter: 53 tests passing (including live-coach parity with the analysis), `flutter analyze` clean
  - End to end against a running server: upload the synthetic session → list → download
    (byte-identical) → analyse
- **Not yet verified:** a build on a physical phone (no Android SDK or Xcode in the development
  environment) and a real WHOOP OAuth round trip. Both are the first things to try with the steps
  above.
- **Next:**
  - Tune thresholds on real sessions with `validate_session.py`, per placement
  - Live calls from the Apple Watch's motion (today, live calls use the phone's motion)
  - A Movesense `MotionSource`
