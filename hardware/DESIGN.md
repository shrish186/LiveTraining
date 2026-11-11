# Leg sensor v1: design for review

**Status:** draft for ECE review · **Owner:** product + firmware (Shrish), electronics review (ECE cofounder)
**Goal:** a strap-on sensor for the bowler's **landing (load-bearing) leg** that captures everything raw at high rate,
streams enough live for real-time calls, and never clips on hard landings.

Everything marked **[verify]** is from memory or an estimate and must be checked against the datasheet or a quote
before the design is frozen.

---

## 1. What it must measure

| Need | Signal | Requirement |
|---|---|---|
| Delivery detection, run-up strides, cadence | 3-axis acc + 3-axis gyro | ±16 g, ±2000 dps, ≥ 200 Hz |
| **Front-foot landing impact** (peak, loading rate) | high-g acc | **±200–320 g, ≥ 1 kHz**: our ankle data already hit 26 g at 100 Hz, so true peaks are higher |
| Ground contact time, shank rotation | gyro + acc | ≥ 500 Hz (2 ms resolution) |
| **Fatigue on the load-bearing leg** (drift across a spell) | all of the above, per delivery | consistent mounting + per-unit calibration |
| Live calls during the session | decimated stream | ~100 Hz to the phone, < 1 s latency |
| Multi-player sessions | many sensors → one phone | 6 sensors on one phone, synchronised to ≤ 5 ms |
| **Muscle fatigue (EMG)** | surface EMG, calf (gastrocnemius) or shin muscle (tibialis anterior) | 1 channel, 20–450 Hz band, **≥ 1 kHz** (2 kHz preferred) |
| Drift-free shank orientation | 3-axis magnetometer | 50–100 Hz |
| Worn / not worn, fast player assignment, buzz on the leg | on-skin detection, NFC tag, vibration motor | |

Placement: lateral shank, just above the ankle bone, on the **front (landing) leg**. An optional second unit on the
back leg gives back-foot contact and left/right comparison.

## 2. Block diagram

```
 USB-C (5 V + USB data) ──► charger ──► LiPo 250 mAh (with protection)
                                  │
                                  ▼
                              3.3 V LDO
                                  │
   ┌──────────────────────────────┼──────────────────────────────────────────────┐
   ▼                              ▼                                              ▼
 nRF52840 module           LSM6DSV320X (±16 g + ±320 g + gyro) ── SPI + 2 INT   SPI NOR flash 2 Gbit ── SPI/QSPI
 (BLE 5, USB, MCU)         LIS2MDL magnetometer ─────────────── I2C/SPI
   │                       EMG front end (ADS1292R or analog AFE) ── SPI + DRDY
   │                          └─ 3 electrodes (2 sensing + reference) on the strap's inner face
   ├─► RGB LED, button, vibration motor (MOSFET), capacitive on-skin pad
   ├─► battery sense (divider + switch to ADC), charger status
   └─► SWD (Tag-Connect TC2030 footprint)
 Passive NFC tag in the case (no wiring): tap a phone to assign the sensor to a player
```

## 3. Parts (first pick + alternatives)

| Block | First pick | Alternatives | Why |
|---|---|---|---|
| Radio + MCU | **Pre-certified nRF52840 module** (e.g. Raytac MDBT50Q, Fanstel BT840, u-blox NINA-B3) [verify current certs] | nRF54L15 module (newer, lower power) | Native USB, mature SDK, multi-connection BLE. A **module with FCC/IC/CE grants** removes most radio certification cost |
| IMU | **ST LSM6DSV320X** [verify ranges/ODR/package] | LSM6DSV16X + separate high-g ADXL375 / H3LIS331DL | One package with a low-g ±16 g channel **and** a high-g ±320 g channel, gyro, FIFO, timestamps. Exactly the impact problem we have |
| Storage | **2 Gbit** SPI NOR [verify availability; else 1 Gbit W25Q01JV] | 2 Gbit NAND (needs bad-block handling) | ~3 h of raw data incl. EMG (budget in §5); NOR is simpler and robust |
| Charger | TI BQ25180 or MCP73831 [verify] | BQ21080 | Single-cell LiPo, ~100–200 mA charge, small |
| 3.3 V regulator | TPS7A02 (very low Iq) [verify] | nRF52840 internal REG0 (VDDH mode) if peak current fits | Flash write peaks can exceed what REG0 should supply externally |
| Battery | 502030 LiPo ~250 mAh **with protection circuit** | 402030 ~200 mAh | Certified cells (UN38.3, IEC 62133) save certification work |
| Connector | USB-C (charging + data) | Pogo pins + dock (for sealed case v2) | USB lets us copy 100+ MB after a session |
| UI | RGB LED, one button | + small vibration motor (DNP footprint) | Button = start/stop/**mark** (labels for training data). Motor = buzz on the leg for live calls |
| Debug | Tag-Connect TC2030 pads, UART test pads | | Production programming + debugging |
| **EMG front end** | **TI ADS1292R** (24-bit biopotential AFE, SPI) [verify] | Analog AFE (instrumentation amp + 20–450 Hz band-pass) into the nRF SAADC; prototype: MyoWare 2.0 raw output [verify] | Raw EMG at 1–2 kHz for frequency analysis (fatigue = median frequency falls, RMS rises) |
| Electrodes | Snap connectors for **disposable gel electrodes** (v1) | Dry conductive-silicone electrodes in the strap (v2) | Gel gives a clean signal now; dry is the convenient product later |
| Magnetometer | ST LIS2MDL [verify] | MMC5983MA | Heading for 9-axis fusion; keep away from the motor and battery wiring |
| On-skin detection | Capacitive pad on the case base | Proximity sensor | Auto-start; flags a loose strap |
| NFC | Passive NTAG sticker inside the case | nRF52840 NFC-A pins [verify] | Tap phone to sensor = assign to player |
| Haptics | Small ERM coin motor + MOSFET + flyback diode | LRA + driver | Buzz on the leg for live calls |
| Protection | ESD diode on USB D+/D-/VBUS, reverse-battery protection | | Field use, sweaty connectors |

## 4. Net list (for schematic review)

Pin numbers are left to the layout: assign to module GPIOs that keep traces short. Rules:

| Net | From → to | Notes |
|---|---|---|
| IMU_SCK / MOSI / MISO / CS | nRF SPIM (high-speed instance) ↔ LSM6DSV320X | SPI up to 8–10 MHz [verify]; short traces |
| IMU_INT1 | IMU → nRF GPIO (interrupt-capable) | FIFO watermark |
| IMU_INT2 | IMU → nRF GPIO | high-g event / wake-up |
| MAG_SDA/SCL (or SPI) + MAG_DRDY | nRF ↔ LIS2MDL | separate bus from the IMU if possible |
| EMG_SCK/MOSI/MISO/CS + EMG_DRDY + EMG_START/RESET | nRF ↔ ADS1292R | electrode inputs IN1P/IN1N + RLD/reference via protection resistors + ESD |
| CAP_SENSE | base pad → nRF GPIO/comparator | on-skin detection |
| FLASH_SCK / MOSI / MISO / CS (or QSPI IO0–3) | nRF ↔ NOR flash | QSPI if the module exposes it: faster dumps |
| USB_DP / USB_DN / VBUS | USB-C ↔ nRF (native USB) + charger | CC1/CC2 5.1 kΩ pull-downs (sink) |
| CHG_STAT | charger → nRF GPIO | charging state for the LED/app |
| VBAT_SENSE + VBAT_SENSE_EN | divider → ADC, switched | no constant divider drain |
| BTN | button → GPIO (pull-up, wake from sleep) | |
| LED_R / G / B | GPIO → LED via resistors | |
| MOTOR_EN (DNP) | GPIO → MOSFET → motor | flyback diode |
| SWDIO / SWDCLK / RESET / VDD / GND | TC2030 | |

## 5. Data, rates and budgets

**Recording (on the sensor, to flash):**

| Stream | Rate | Bytes/s |
|---|---|---|
| Low-g acc + gyro (6 × int16) | 960 Hz | 11.5 kB |
| High-g acc (3 × int16) | 960 Hz | 5.8 kB |
| Timestamps + headers | per FIFO batch | ~0.3 kB |
| EMG (1 ch × 24-bit) | 2 kHz | 6.0 kB |
| Magnetometer (3 × int16) | 100 Hz | 0.6 kB |
| **Total** | | **~24 kB/s ≈ 87 MB/hour** |

256 MB flash ≈ 3 hours at full rate (128 MB would give ~1.5 h with EMG). If that's too short: record high-g at full rate only in windows around detected
landings (±300 ms), which brings it to ~12 kB/s ≈ 3 hours. **[decide with review]**

**Live stream (BLE notifications):** acc + gyro decimated to 104 Hz (≈ 1.3 kB/s per sensor) **plus** per-landing
features computed on the sensor (peak high-g, time of impact). 6 sensors ≈ 8 kB/s total, comfortably within BLE 2M PHY
on one phone.

**Time sync:** every FIFO batch carries the sensor's sample counter + 32.768 kHz RTC tick. The phone records its own
receive time per packet; offline we fit sensor clock → phone clock per sensor (linear, removes drift). Target
cross-sensor sync ≤ 5 ms. A sync jump at the start remains the check.

**Power budget (estimate) [verify by measurement]:**

| Consumer | Average |
|---|---|
| nRF52840 BLE streaming + CPU | 3–5 mA |
| LSM6DSV320X high-performance, 960 Hz, both channels | ~1–1.5 mA |
| Flash writes (averaged) | 1–3 mA |
| LED blips, LDO, leakage | < 0.5 mA |
| **Total** | **~6–10 mA → 25–40 h on 250 mAh** |

**EMG notes:** electrodes sit on the strap's inner face over the muscle belly, ~2 cm apart, reference over bone.
Landing impacts cause big motion artefacts: high-pass ≥ 20 Hz, and analyse EMG in windows that exclude ±50 ms around
each impact (the IMU tells us exactly when). Fatigue features: median/mean power frequency and RMS per delivery,
compared with the start of the spell. Wellness use only: no medical or diagnostic claims.

## 6. Mechanical

- PCB target ≤ 25 × 30 mm, 4-layer (solid ground plane, short SPI runs), IMU near the board centre and **rigidly fixed**:
  no foam under the PCB, the board screws or clips to the case. A loose board ruins impact data.
- Case: current printed prototype is `sensor_case/` (dev-kit stack). v1 case for the custom PCB: same strap loops and
  curved base, sealed lid with gasket (sweat), button membrane, LED light pipe.
- Axis marking on PCB silkscreen and case (arrow to the foot), so the software knows the mounting orientation.

## 7. Firmware outline (nRF Connect SDK / Zephyr)

1. IMU: both channels into the FIFO with timestamps; FIFO watermark interrupt; burst-read over SPI.
2. Writer: double-buffered pages to flash; session index (start time, counters, battery, firmware version).
3. BLE: custom service with
   - `stream` (notify): decimated 104 Hz packets with sample counter
   - `events` (notify): per-landing features
   - `control` (write): start/stop/mark/sync, set rates
   - `status` (read/notify): battery, flash use, clipping counters
4. USB: mass-storage or CDC download of session files after training.
5. Device ID + per-unit calibration stored in flash (written at factory test).

## 8. Raw data → proper data (the software "model")

The pipeline that turns raw sensor bytes into numbers a coach can trust. It builds on `analysis/ltlib` (sync, steps,
impact, drift) and runs offline first, then live in the app for the parts that need to be real time.

| Stage | What it does |
|---|---|
| 1. Integrity | Detect lost packets (sample counters), rebuild exact timestamps, fit sensor→phone clock |
| 2. Calibration | Per-unit bias/scale (factory), temperature compensation |
| 3. **Dual-range fusion** | Low-g channel below ~14 g, high-g above, blended: one clean signal with no clipping; flag any saturation |
| 4. Mounting alignment | 3 s standing pose at start → gravity direction → shank frame (vertical, forward, lateral). Removes strap-angle differences between sessions and players |
| 5. Orientation | Gyro + acc complementary filter for shank angle through each stride |
| 6. Events | Footstrikes (have), jumps (have), **run-up**, **back-foot contact**, **front-foot landing**, **delivery** (the sequence), follow-through |
| 7. Per-delivery metrics | Front-foot peak g, loading rate (g/s), contact time, shank angular velocity peak, run-up stride count/cadence/intensity |
| 8. **Fatigue on the load-bearing leg** | Each delivery vs the first N deliveries of the spell (and the player's history): peak g, loading rate, contact time, run-up cadence, stride variability. Live call when drift passes profile thresholds. Wording: workload and fatigue only |
| 9. Quality report | Per session: % packets lost, % clipped, mounting check, battery: so bad data is never shown as good |
| 10. Learning (later) | Button marks + video labels → a trained delivery/quality model on top of the rules |

All thresholds go in a `cricket_fast_bowling` sport profile (`profiles/sport_profiles.yaml`), not in code.

## 9. Test plan

1. Bench: power-on current, BLE range, flash write/read speed, charge cycle, button/LED.
2. Static: 6-orientation accelerometer calibration, gyro bias; drop test (impact channel vs reference).
3. Sync: 2–6 sensors tapped together → timestamp agreement.
4. Field: jumps (height vs flight time), sprints (strides vs video), **bowling spells with button marks** (delivery
   detection rate, false calls).
5. Endurance: 3-hour session, battery and flash use.

## 10. Certification and safety (to plan, not to do in two weeks)

US first: **FCC Part 15** (with a pre-certified module: mostly unintentional-radiator testing, $1.5–5k), battery
UN38.3 / IEC 62133 via certified cells, product liability insurance, COPPA for under-13 players. Then UKCA (England),
RCM (AU/NZ). Manufacturing in South Asia; check current US import tariffs per country of assembly.

## 11. Cost (estimates, [verify] with real quotes)

**Prototype from dev boards (now):**

| Item | Per unit |
|---|---|
| nRF52840 board (e.g. XIAO nRF52840) | $10–15 |
| LSM6DSV320X breakout/eval board | $15–30 |
| Magnetometer breakout | $8–10 |
| EMG board (e.g. MyoWare 2.0) + gel electrodes | $40–45 |
| Battery, vibration motor, NFC sticker, wiring | $10–15 |
| Printed case + strap | $5 |
| **Per prototype** | **≈ $90–120** |

**Custom v1 board (assembled in India):**

| | ~100 units | ~1,000 units |
|---|---|---|
| nRF52840 module | $6–9 | $5–7 |
| LSM6DSV320X | $5–8 | $4–6 |
| EMG front end (ADS1292R) | $8–12 | $6–9 |
| Magnetometer, 2 Gbit flash, charger, LDO | $7–11 | $5–8 |
| Motor, NFC, cap-sense, LED, button, USB-C, passives | $3–5 | $2–3 |
| PCB (4-layer) + assembly + test | $6–10 | $3–5 |
| Battery, sealed case, strap with electrode snaps | $8–12 | $5–8 |
| **Per sensor** | **≈ $45–65** | **≈ $30–45** |

Consumable: gel electrodes ≈ $0.30–0.60 per player per session (v2 dry electrodes remove this).

**One-time to the India trial:** 2–3 board revisions × ~10 boards ($300–800 each) + parts and tools ≈ **$1.5–3k**.

## 12. Questions for the reviewer

1. LSM6DSV320X: confirm both channels can run at ~960 Hz into the FIFO together with the gyro, and SPI bandwidth.
2. REG0 (VDDH mode) vs external LDO for flash write peaks.
3. Flash: 1 Gbit NOR vs NAND; QSPI on the chosen module?
4. 4-layer vs 2-layer for a 25 × 30 mm board with a chip-antenna module (keep-out zone!).
5. Charger choice and charge current for 250 mAh; thermal limits in a sealed case.
6. Vibration motor: placement so it doesn't disturb the IMU or the magnetometer.
8. EMG: ADS1292R vs analog AFE + SAADC; input protection and ESD on the electrode lines; electrode lead routing
   through the strap; motion-artefact rejection (driven reference).
7. Anything to change so the same board can be assembled in India at low volume (10–100 units).
