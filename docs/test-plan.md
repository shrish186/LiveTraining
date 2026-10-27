# Field test plan

What to record so the analysis can be checked and tuned. Each session takes about 20 minutes.

## Setup (every session)

1. **Leg sensor:** the watch, tight on the outside of the ankle (just above the ankle bone) or the
   lower shin. Same spot every time. Our watch app, or SensorLog (file, 100 Hz, accelerometer).
2. **Phone app:** Sport, Type, and Sensor on = where the motion sensor is. With our watch app streaming,
   that is set for you. With SensorLog, choose `phone_pocket` (the phone's own motion). WHOOP connected.
3. **Start the phone session**, phone in your pocket. Then start the watch.
4. **Sync:** stand still 5 s, do **3 firm vertical jumps** about 2 s apart with the phone in your
   pocket, then tap **Sync jumps once**. The jumps also give a jump-height reading.

## Session A: detection accuracy (do 2–3 of these)

- 6 min easy jog (warm-up; watch for "Warmed up, go").
- **6 straight sprints, 10–15 s each, full effort.** Tap **Mark** right after each one, and at no other time.
- Walk **90 s** between sprints (this is what lets HR recovery be measured; with 30 s rests you
  still get detection accuracy, but no fatigue reading).
- Then 3 min of easy jogging, walking and direction changes with **no** Mark: checks for false efforts.

## Session B: fatigue (one, when fresh enough)

- Warm-up 6 min, then **10–12 sprints of 15 s**, one every 2 minutes (walk in between), Mark after each.
- 25–30 min total, so there are efforts in the first 15 min (baseline) and after it.

## Session C: harder cases (later)

- 3–5 s bursts out of a jog, sprints with a cut halfway, decelerations. Mark after each.

## After each session

1. Stop the watch, then hold to stop on the phone. Upload the phone session (Sessions tab).
2. SensorLog: on the watch, Log & Config Files › send to iPhone, then share the zip **straight to the
   Mac with AirDrop**. Don't open it on the phone (it turns into a Numbers file).
3. On the Mac:

```bash
cd ~/LiveTraining/analysis && . .venv/bin/activate
python import_sensorlog.py ~/Downloads/sensorlog/*/"<file> Apple Watch.csv" --placement ankle   # SensorLog only
python merge_sessions.py ../backend/data/sessions/<phone_id>.csv output/<watch id>.csv           # SensorLog only
python analyze_session.py <session or merged csv>     # efforts, fatigue, steps, impact, jumps, drift
python validate_session.py <session or merged csv>    # detection vs your Mark taps
```

Write down anything unusual (a sprint you cut short, a stumble, a fall): it explains outliers later.
