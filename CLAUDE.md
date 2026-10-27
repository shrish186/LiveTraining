# Live Training Intelligence: project context

A sports training app for athletes in any sport. It combines a body-worn motion sensor with
WHOOP heart rate and recovery to give live calls during training ("warmed up, go",
"fatigue building, cut the last set").

v1 is the data pipeline. It records phone motion and WHOOP HR on the phone, uploads sessions
to the backend, pulls WHOOP recovery through the official API, and analyses sessions offline.
The first live calls (readiness, warm-up, effort, fatigue) run on the phone and reuse the analysis
logic and the sport profiles.

## Layout

| Path | What |
|---|---|
| `mobile/` | Flutter app (iOS and Android): BLE HR, phone motion, session recorder, upload |
| `mobile/ios/LiveTrainingWatch Watch App/` | Apple Watch app (Swift): leg/wrist motion + HR, sends sessions to the iPhone. Setup: `docs/apple-watch.md` |
| `backend/` | FastAPI and SQLAlchemy: WHOOP OAuth and API proxy, session upload and storage |
| `analysis/` | Python: synthetic sessions, offline session analysis and plots |
| `profiles/sport_profiles.yaml` | **all** sport-specific logic: thresholds, min durations, placements |
| `docs/session-format.md` | the session CSV and metadata JSON spec. It is the contract between the three parts. |

## Hard rules (never break these)

1. **WHOOP: official APIs only.** Use the developer API (OAuth 2.0) and the strap's built-in Heart
   Rate Broadcast (standard BLE Heart Rate service 0x180D, characteristic 0x2A37). Never
   reverse-engineer the strap or its private Bluetooth protocol.
2. **No secrets in git.** WHOOP client ID and secret live in `backend/.env` (gitignored). Keep
   `backend/.env.example` up to date instead.
3. **Wording:** user-facing text says "fatigue", "readiness", "load". Never "injury prediction"
   or anything that suggests a medical or diagnostic claim.
4. **Sport-agnostic core.** No sport name, threshold or placement may be hard-coded in the core
   (recorder, backend, analysis pipeline). Sport-specific behaviour lives only in sport profiles.
   Adding a sport = adding a profile.
5. Simple and working beats clever. Write tests for pure logic.

## Conventions

- The session format is defined once in `docs/session-format.md`. If it changes, update the doc,
  `backend/app/session_format.py`, `analysis/ltlib/session_io.py` and `mobile/lib/recording/csv_row.dart`
  together.
- One monotonic clock (a phone `Stopwatch`) stamps every stream. `t_ms` is ms since session start.
- Motion magnitude = `| |acc| - 9.81 |` (gravity removed), then a rolling mean. Used in the app and
  in the analysis alike.
- `mobile/assets/sport_profiles.yaml` is a copy of `profiles/sport_profiles.yaml` (the app's live
  coach reads it). Edit the root file, then copy it; a test fails if they differ.
- The live coach (`mobile/lib/coach/live_coach.dart`) mirrors `analysis/ltlib/core.py`. After an
  analysis change, run `python make_parity_fixture.py` and keep `coach_parity_test.dart` passing.
- Live calls are written to the session as `call_*` events. Accuracy is checked with
  `analysis/validate_session.py` against the athlete's `mark` events.
- WHOOP token refresh invalidates the old access and refresh tokens. Always persist the new refresh
  token and serialise refreshes per athlete (see `backend/app/whoop.py`).
- Backend tests never call the real WHOOP API. Use `httpx.MockTransport`.
- Python: 3.11+, type hints, `pytest`. Dart: `flutter analyze` clean, `flutter test`.
- New motion sensors implement `MotionSource` (`mobile/lib/sources/motion_source.dart`) and get a
  new `source` value in the session format. The recorder must not change.

## Commands

```bash
# backend
cd backend && python -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
pytest
./run_dev.sh            # or: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# analysis
cd analysis && pip install -r requirements.txt
python make_synthetic_session.py --out output/
python analyze_session.py output/synthetic.csv --metadata output/synthetic.json --profile soccer
python validate_session.py <session.csv>   # detection vs your Mark taps, threshold suggestion
python check_rate.py <session.csv>         # real sample rate per stream (e.g. did the watch get 800 Hz)
python make_parity_fixture.py             # after an analysis change (app parity test)
pytest

# mobile
cd mobile && flutter pub get && flutter analyze && flutter test
flutter run            # with a phone connected
```
