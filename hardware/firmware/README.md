# Leg sensor firmware

## v1: Seeed XIAO nRF52840 Sense + Adafruit ADXL375 (high-g)

`leg_sensor/` streams accelerometer and gyroscope (±2000 °/s) at 104 Hz over Bluetooth, in the packet
format of [docs/sensor-protocol.md](../../docs/sensor-protocol.md). The app's **Squad** tab connects to it.

The XIAO's own motion sensor stops at ±16 g, and a sprint footstrike already reached 26 g on the watch. The
ADXL375 (±200 g) fills that in: below 12 g the precise built-in reading is sent as is; from 12 g to 16 g the
firmware blends towards the ADXL375's magnitude, keeping the built-in sensor's direction. Only the magnitude is
borrowed, so it does not matter which way round the breakout sits in the case. With the ADXL375 the packets carry
10 mg per count (±327 g); without it the same firmware sends 1 mg per count and simply clips at 16 g.

### Wiring (4 wires, STEMMA QT cable to male headers)

| ADXL375 (STEMMA QT wire) | XIAO pin |
|---|---|
| VIN (red) | 3V3 |
| GND (black) | GND |
| SDA (blue) | D4 |
| SCL (yellow) | D5 |

Solder the header ends to the XIAO's pads (or plug them into a breadboard first to test). Keep the wires short and
fix the breakout flat with foam tape: a loose board rattles and adds fake peaks. The breakout has its own pull-up
resistors, so nothing else is needed.

At power-on the LED shows **one long green flash** if the ADXL375 was found, **one long red flash** if not
(it then runs as ±16 g only, so check the wiring).

### Flash it (no tools needed)

1. Plug the XIAO into your computer with a USB-C **data** cable.
2. **Double-tap the tiny reset button** next to the USB port. A drive called `XIAO-SENSE` appears.
3. Drag `build/leg_sensor_v1.uf2` onto that drive. The board restarts by itself.
4. The LED **blinks blue**: it is advertising as `LT-xxxx`. In the app: Squad › Add player › Add sensor.
   The LED turns **green** while connected. A **red flash** every second means the motion sensor did not start.

### Build it yourself

Arduino IDE: add the board URL `https://files.seeedstudio.com/arduino/package_seeeduino_boards_index.json`,
install **Seeed nRF52 Boards**, pick **Seeed XIAO nRF52840 Sense**, open `leg_sensor/leg_sensor.ino`, Upload.

Command line:

```bash
arduino-cli core install Seeeduino:nrf52 --additional-urls https://files.seeedstudio.com/arduino/package_seeeduino_boards_index.json
pip install adafruit-nrfutil
arduino-cli compile --fqbn Seeeduino:nrf52:xiaonRF52840Sense leg_sensor
```

### Packet cross-check

`test_packet.cpp` builds packets with the firmware's own `leg_sensor/packet.h` and writes them to
`mobile/test/fixtures/sensor_packet.hex`; the app's `sensor_protocol_test.dart` parses that file. Run it after any
change to the packet layout:

```bash
g++ -std=c++17 -o /tmp/test_packet test_packet.cpp && /tmp/test_packet > ../../mobile/test/fixtures/sensor_packet.hex
```

`test_packet.cpp` also checks the high-g fusion (`lt_fuse_mg`) with asserts: it exits with an error if the
fusion is wrong.

### Status and limits of v1

- Compiles for the board (121 kB, 14% of flash). **Not yet run on real hardware**: first power-on may need fixes.
- Without the ADXL375, hard landings clip at 16 g. The firmware counts clipped samples (only when nothing covers
  them) and the app's quality check flags them.
- The ADXL375 is read once per built-in sample (104 Hz), not at its own 400 Hz. Enough for peak height in our
  impact metrics; the custom board's single ±320 g IMU removes the second chip altogether.
- No recording to flash, no EMG, no button or vibration motor: those come with the custom board
  (`../DESIGN.md`). Streaming starts as soon as the app subscribes.
- Battery percentage is a rough estimate from the battery voltage.
