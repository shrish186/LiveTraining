# Leg sensor hardware

Our own motion sensor, so the product doesn't depend on someone else's watch or pod.

## Prototype (now): off-the-shelf board in a printed case

| Part | Example | Approx. cost |
|---|---|---|
| Board: BLE + 6-axis IMU + LiPo charger | Seeed **XIAO nRF52840 Sense** (21 × 17.8 mm) | $15 |
| Battery | 502030 LiPo, ~250 mAh, JST-PH or solder tabs | $5 |
| Case | `sensor_case/` (3D printed, PETG) | ~$1 of plastic |
| Strap | 25 mm elastic or hook-and-loop strap | $2–3 |
| **Total** | | **≈ $25** |

Print: `sensor_case/case_body.stl` and `case_lid.stl` (PETG, 0.2 mm layers, 30% infill, no supports needed with the
lid printed upside down). Battery on the floor (foam tape), XIAO on top with its USB-C port in the case opening, lid
pressed on. The arrow on the lid points to the foot. Wear it on the outside of the lower shin or above the ankle,
strap tight.

Change dimensions in `sensor_case/sensor_case.py` (all parameters at the top) and run it to regenerate STEP + STL.
`render_preview.py <sensor_case.py> <out.png>` draws the exploded view and two cross-sections with the parts placed.

### Known limits of the prototype

- **The XIAO's IMU tops out at ±16 g.** Hard landings at the shin reach 20–30 g (our ankle session peaked at 26 g),
  so impact peaks clip. Fine for efforts, strikes, deliveries and drift; not for true peak impact.
- Battery life, firmware and the app's `xiao` motion source are next (the session format already has `xiao`).

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
