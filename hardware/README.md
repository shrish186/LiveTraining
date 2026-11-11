# Leg sensor hardware

Our own motion sensor, so the product doesn't depend on someone else's watch or pod.

## Prototype (now): off-the-shelf board in a printed case

| Part | Example | Approx. cost |
|---|---|---|
| Board: BLE + 6-axis IMU + LiPo charger | Seeed **XIAO nRF52840 Sense** (21 × 17.8 mm) | $15 |
| High-g accelerometer (±200 g) | Adafruit **ADXL375** STEMMA QT breakout (25.6 × 17.8 mm) | $15 |
| Cable (bench test) | STEMMA QT / Qwiic JST SH 4-pin cable **with female sockets** (fits a pre-soldered XIAO) | $1 |
| Battery | 502030 LiPo, ~250 mAh, with wire leads | $5–8 |
| Case | `sensor_case/` (3D printed, PETG) | ~$1 of plastic |
| Strap | 25 mm elastic or hook-and-loop strap | $2–3 |
| **Total** | | **≈ $40** |

Two builds:

- **Bench (no soldering):** pre-soldered XIAO + ADXL375 on the female-socket cable, powered over USB-C. Good for
  the first power-on, the app connection and shaking/drop tests. Too tall for the case.
- **Wearable (soldering, ~20 min):** XIAO *without* headers, four short wires to the ADXL375 (3V3, GND, D4, D5) and
  the battery on the XIAO's BAT+/BAT− pads underneath. Fits the case: 35.6 × 40.6 × 23.3 mm incl. strap loops.

Print: `sensor_case/case_body.stl` and `case_lid.stl` (PETG, 0.2 mm layers, 30% infill, no supports needed with the
lid printed upside down). ADXL375 flat on the floor with thin, firm double-sided tape (VHB, not soft foam: it must
move with the case), battery on top of it, XIAO on top with its USB-C port in the case opening, lid pressed on. The arrow on the lid points to the foot. Wear it on the outside of the lower shin or above the ankle,
strap tight.

Change dimensions in `sensor_case/sensor_case.py` (all parameters at the top) and run it to regenerate STEP + STL.
`render_preview.py <sensor_case.py> <out.png>` draws the exploded view and two cross-sections with the parts placed.

### Known limits of the prototype

- **The XIAO's IMU tops out at ±16 g.** Hard landings at the shin reach 20–30 g (our ankle session peaked at 26 g).
  The ADXL375 covers that: the firmware fuses the two (`firmware/README.md`). Without it, impact peaks clip.
- Firmware: `firmware/` (flash by drag and drop). The app's Squad tab connects to it. Battery life is unmeasured.

## Production direction (once people want it)

Same function on our own PCB:

| Block | Candidate | Why |
|---|---|---|
| Radio + MCU | Pre-certified nRF52 module | BLE to the phone; a certified module avoids most radio certification work |
| IMU | **ST LSM6DSV320X** | 6-axis plus a second **±320 g** accelerometer channel made for impact: no clipping on landings |
| Storage | SPI flash | Record at 800+ Hz on the sensor, stream ~100 Hz live, upload the rest after the session |
| Power | 150–250 mAh LiPo + charger IC | A full training day per charge |

Rough bill of materials at ~1,000 units: **$15–25**. Selling needs FCC/CE (and UKCA) testing and UN38.3 for shipping
lithium batteries: budget thousands of dollars, but only once you sell, not for prototypes.
