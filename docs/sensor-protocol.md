# Leg sensor Bluetooth protocol (v1)

The contract between the sensor firmware (`hardware/`) and the app (`mobile/lib/sources/sensor_protocol.dart`).
Change them together, and bump the packet version for any incompatible change.

## GATT

| | UUID | Properties |
|---|---|---|
| Service (advertised) | `4c540001-7d2a-4b6e-9f3c-5a1e2b3c4d5e` | |
| Stream | `4c540002-7d2a-4b6e-9f3c-5a1e2b3c4d5e` | notify |
| Control | `4c540003-7d2a-4b6e-9f3c-5a1e2b3c4d5e` | write |
| Status | `4c540004-7d2a-4b6e-9f3c-5a1e2b3c4d5e` | read, notify |

Device name: `LT-xxxx` (last 4 hex digits of the device address), also printed on the case.

## Stream packet (little-endian)

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | version = 1 |
| 1 | u8 | flags: bit 0 = gyro present |
| 2 | u16 | sequence number (wraps at 65536); a jump means lost packets |
| 4 | u32 | sensor clock in ms at the **first** sample of this packet |
| 8 | u16 | sample period in microseconds (9615 = 104 Hz) |
| 10 | u8 | number of samples n |
| 11 | u8 | acceleration scale: milli-g per count (1 → ±32 g, 10 → ±327 g) |
| 12 | n × record | samples, oldest first |

Record: `ax, ay, az` as i16 (× scale = milli-g, gravity included, low-g and high-g ranges already fused on the
sensor: below 12 g the precise low-g reading, above it the low-g direction with the magnitude of the hardest high-g
reading since the previous sample (peak hold); see
`lt_fuse_mg` in `hardware/firmware/leg_sensor/packet.h` and `fuse_ranges` in `analysis/ltlib/quality.py`). The prototype
sends scale 1 without a high-g sensor and 10 with one. With the gyro flag: followed by `gx, gy, gz` as i16 in units of 70 mdps (±2294 °/s).

A 244-byte notification carries 38 acc-only samples or 19 acc+gyro samples.

## Time

The sensor stamps samples with its own clock. The app keeps, per sensor, the smallest observed
(phone receive time − sensor time of the packet's last sample): radio delay only ever makes packets late, so the
smallest difference is the true clock offset (allowed to creep to follow drift). Each sample is then placed at its own
time on the phone's session clock. See `SensorClock` and `analysis/ltlib/quality.py: fit_clock`.

## Control (write)

| Bytes | Command |
|---|---|
| `01` | start streaming |
| `02` | stop streaming |
| `03` | mark (same as pressing the button) |
| `04 hh` | buzz the vibration motor for `hh` × 10 ms |

## Status (read / notify)

`u8 battery %`, `u8 flags` (bit 0 charging, bit 1 recording to flash, bit 2 worn), `u16 clipped-sample count since
start` (samples at the limit that no high-g sensor covered), `u16 firmware version` (2 = high-g fusion).
