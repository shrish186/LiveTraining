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
- Tests: `.venv/bin/pytest` (58 tests, no network needed). To start manually:
  `.venv/bin/uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000`.
- Data is stored in `backend/data/` (SQLite DB and uploaded sessions; gitignored). For Postgres, set
  `DATABASE_URL=postgresql+psycopg://user:pass@host/db` and `pip install "psycopg[binary]"`.
- Run a single worker (the default). See Decisions #4.

## 3. Connect your WHOOP account

Do this in a browser **on the laptop** (the redirect URL points at `localhost`):

1. Open <http://localhost:8000/auth/whoop/login>.
2. Log in to WHOOP and approve.
3. You'll land on **"Connected as <your name>. Athlete ID: 1"**. Note the ID.

Check that it works: <http://localhost:8000/athletes/1/whoop/recovery/latest> should return today's
recovery.

## 4. Run the app on your phone

Needs the Flutter SDK (<https://docs.flutter.dev/get-started/install>). The platform folders
(`mobile/android`, `mobile/ios`) are already generated and include the permissions.

```bash
cd mobile
flutter pub get
flutter test            # 21 tests
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

Phone-in-armband magnitudes differ from the synthetic data, so expect to tune the thresholds in
`profiles/sport_profiles.yaml` after your first real sessions.

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
cd analysis && pytest          # effort detection, HR recovery, fatigue rule, profiles, end-to-end on synthetic data
cd mobile   && flutter test    # heart-rate parser, CSV rows, recorder, motion magnitude
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
26. **iOS shows its own Bluetooth prompt**, so `permission_handler` is only used on Android: scan and
    connect on Android 12+, location on 11 and older.
27. **The app talks to the backend over plain HTTP on the LAN.** Android allows cleartext traffic,
    and iOS uses `NSAllowsLocalNetworking`. Use HTTPS before this leaves the LAN.
28. **Extra packages:** `uuid` (session IDs) and `device_info_plus` (device model in the metadata).
    Upload status is kept in `shared_preferences`.

## Status

- **Verified in development:**
  - Backend: 58 tests passing
  - Analysis: 15 tests passing
  - Flutter: 21 tests passing, `flutter analyze` clean
  - End to end against a running server: upload the synthetic session → list → download
    (byte-identical) → analyse
- **Not yet verified:** a build on a physical phone (no Android SDK or Xcode in the development
  environment) and a real WHOOP OAuth round trip. Both are the first things to try with the steps
  above.
- **Next:**
  - Live calls on the phone, reusing the analysis logic and the profiles
  - A Movesense `MotionSource`
  - Tuning thresholds on real sessions
