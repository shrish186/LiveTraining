# Leg sensor firmware

## v0: Seeed XIAO nRF52840 Sense (built-in motion sensor)

`leg_sensor/` streams accelerometer (±16 g) and gyroscope (±2000 °/s) at 104 Hz over Bluetooth, in the packet
format of [docs/sensor-protocol.md](../../docs/sensor-protocol.md). The app's **Squad** tab connects to it.

### Flash it (no tools needed)

1. Plug the XIAO into your computer with a USB-C **data** cable.
2. **Double-tap the tiny reset button** next to the USB port. A drive called `XIAO-SENSE` appears.
3. Drag `build/leg_sensor_v0.uf2` onto that drive. The board restarts by itself.
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

### Status and limits of v0

- Compiles for the board (120 kB, 14% of flash). **Not yet run on real hardware**: first power-on may need fixes.
- ±16 g: hard landings clip. The firmware counts clipped samples and the app's quality check flags them.
- No recording to flash, no EMG, no button or vibration motor: those come with the high-g IMU and the custom board
  (`../DESIGN.md`). Streaming starts as soon as the app subscribes.
- Battery percentage is a rough estimate from the battery voltage.
