# Leg sensor: first power-on and checks

What to do when the parts arrive (XIAO nRF52840 **Sense**, Adafruit **ADXL375**, STEMMA QT cable **with female
sockets**), in order. Every step says what you should see and what to do if you don't. About an hour.

## 1. The XIAO alone (5 min)

1. Plug the XIAO into the laptop with a USB-C **data** cable (some cables only charge: if nothing happens, try
   another).
2. Double-tap the tiny reset button next to the USB port. A drive called `XIAO-SENSE` appears.
3. Drag `hardware/firmware/build/leg_sensor_v1.uf2` onto it. The drive disappears and the board restarts.

**Expect:** one long **red** flash (no ADXL375 yet, that's fine), then **blue blinks** once a second (advertising).
**Red flash every second instead:** the built-in motion sensor didn't start. Check it's the *Sense* board (the
plain XIAO nRF52840 has no motion sensor).

## 2. Connect the app (10 min)

1. On the phone: **Live** tab › **Leg sensor** card › **Connect sensor**. `LT-xxxx` appears. Pick it. (The app
   remembers it and reconnects by itself next time.)
2. The XIAO's LED turns **green**, and the card shows the live peak g and about **104 Hz**.
3. **Start session**, shake the board for 10 s, put it flat on the table for 10 s, hold to stop.
4. Sessions tab › tap the session for the report. To get the files onto the laptop: long-press the session ›
   **Share files** (AirDrop works).

For several players at once, use the **Squad** tab instead: one sensor per player.

**Expect:** motion while shaking, about 1 g while flat, a data-quality card that says **good**, rate ~104 Hz.
**Check with the scripts** (after uploading or copying the session to the laptop):

```bash
cd analysis
python check_rate.py <session.csv>        # xiao: ~104 Hz, no gaps
python analyze_session.py <session.csv>   # quality: gravity error under 5 %
```

**Rate well below 104 or many dropouts:** keep the phone within 2 m, and try another phone. Note the phone model.

## 3. Add the ADXL375 (10 min, no soldering)

| ADXL375 (STEMMA QT wire) | XIAO pin |
|---|---|
| VIN (red) | 3V3 |
| GND (black) | GND |
| SDA (blue) | D4 |
| SCL (yellow) | D5 |

Plug the JST end into either STEMMA port on the ADXL375, then push the four sockets onto the XIAO's pins.
Double-check 3V3 and GND before powering: swapped power can kill the breakout. Then unplug and replug USB.

**Expect:** one long **green** flash at power-on (high-g sensor found), then blue blinks.
**Long red flash:** not found. Check SDA/SCL aren't swapped and the cable is fully in.

## 4. Does the high-g range work? (10 min)

Tape the XIAO and the ADXL375 **firmly** to something rigid together (a thick book, a piece of wood): the two
must move as one. Record a squad session: 10 s still, then **drop the book flat onto a carpeted floor from
about 30 cm**, five times, 5 s apart, then 10 s still.

**Expect** in `python analyze_session.py <csv>` and the report:
- impact peaks **above 16 g** on at least some drops (before the ADXL375, they stopped at 16 g)
- the data-quality card does **not** say "sensor hit its limit"
- gravity at rest still within 5 % of 1 g

**Peaks stop at exactly 16 g with the ADXL375 connected:** fusion isn't working. Send the CSV, it will show which.

## 5. On the leg (15 min)

With the bench build (USB-C power bank in a pocket, cable to the sensor), strap it **above the ankle, outside of
the leg, arrow toward the foot**, tight. Session placement: **ankle**.

- Walk 1 min, jog 1 min, 4 × 10 s sprints with 30 s walking between, 3 standing jumps.
- In the report: footstrikes counted, impact load, jumps with heights, 4 efforts.
- Compare with the earlier SensorLog ankle session (4/4 sprints, strides ~600 ms, peaks 10–15 g, watch hit 26 g).

## 6. Cricket check (when a bowler is available)

Sport **cricket**, placement **ankle**, sensor on the **front (landing) leg**. The coach taps **Mark** once per
delivery as the ball is bowled. Bowl 2–3 overs.

```bash
python validate_session.py <session.csv>   # deliveries vs marks: precision, recall, min_peak_g suggestion
```

Thresholds in `profiles/sport_profiles.yaml › cricket › actions` are untuned guesses. Change them only once two
or three sessions agree.

## What to send back after each step

The session CSV + JSON, the phone model, and one line on anything odd (LED colours, disconnects, how it felt on the
leg). That is enough to fix things remotely.
