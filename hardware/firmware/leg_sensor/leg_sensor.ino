// Leg sensor firmware, prototype v1: Seeed XIAO nRF52840 Sense (built-in LSM6DS3TR-C) plus an
// optional Adafruit ADXL375 (+-200 g) on the external I2C pins (SDA D4, SCL D5, address 0x53).
// Streams accelerometer and gyroscope (+-2000 dps) at 104 Hz over Bluetooth LE, in the packet
// format of docs/sensor-protocol.md. Board: "Seeed XIAO nRF52840 Sense" (Seeed nRF52 Boards).
//
// With the ADXL375 fitted the sensor fuses the two accelerometers (lt_fuse_mg in packet.h) and
// sends 10 mg per count, so landings up to +-200 g arrive unclipped. Without it, it behaves like
// v0: +-16 g at 1 mg per count, and clipped samples are counted in the status.
// UNTESTED ON HARDWARE: compiled and the fusion maths unit-tested, nothing more yet.
//
// LED: blue blinking = advertising, green = connected and streaming, red flash = IMU not found.
// At start-up: one long green flash = high-g sensor found, one long red = not found (still works).
// Not here yet: flash recording, EMG. Those arrive with the custom board (hardware/DESIGN.md).

#include <bluefruit.h>
#include <Wire.h>

#include "packet.h"

// ---- protocol ---------------------------------------------------------------------------------
// 4c54000X-7d2a-4b6e-9f3c-5a1e2b3c4d5e, least significant byte first
#define LT_UUID(n) {0x5e, 0x4d, 0x3c, 0x2b, 0x1e, 0x5a, 0x3c, 0x9f, 0x6e, 0x4b, 0x2a, 0x7d, n, 0x00, 0x54, 0x4c}
const uint8_t UUID_SERVICE[16] = LT_UUID(0x01);
const uint8_t UUID_STREAM[16] = LT_UUID(0x02);
const uint8_t UUID_CONTROL[16] = LT_UUID(0x03);
const uint8_t UUID_STATUS[16] = LT_UUID(0x04);

BLEService service(UUID_SERVICE);
BLECharacteristic streamChar(UUID_STREAM);
BLECharacteristic controlChar(UUID_CONTROL);
BLECharacteristic statusChar(UUID_STATUS);

// ---- IMU (LSM6DS3TR-C on the internal I2C bus) ---------------------------------------------------
#define IMU_ADDR 0x6A
#define REG_WHO_AM_I 0x0F
#define REG_CTRL1_XL 0x10
#define REG_CTRL2_G 0x11
#define REG_CTRL3_C 0x12
#define REG_STATUS 0x1E
#define REG_OUTX_L_G 0x22
#define SAMPLE_PERIOD_US 9615  // 104 Hz
#define ACC_MG_PER_COUNT 0.488f  // +-16 g range
#define ACC_LIMIT_COUNTS 32700   // at the sensor's range limit

static bool imuWrite(uint8_t reg, uint8_t value) {
  Wire1.beginTransmission(IMU_ADDR);
  Wire1.write(reg);
  Wire1.write(value);
  return Wire1.endTransmission() == 0;
}

static bool imuRead(uint8_t reg, uint8_t *buf, uint8_t len) {
  Wire1.beginTransmission(IMU_ADDR);
  Wire1.write(reg);
  if (Wire1.endTransmission(false) != 0) return false;
  if (Wire1.requestFrom((uint8_t)IMU_ADDR, len) != len) return false;
  for (uint8_t i = 0; i < len; i++) buf[i] = Wire1.read();
  return true;
}

static bool imuBegin() {
  pinMode(PIN_LSM6DS3TR_C_POWER, OUTPUT);
  digitalWrite(PIN_LSM6DS3TR_C_POWER, HIGH);
  delay(20);
  Wire1.begin();
  Wire1.setClock(400000);
  uint8_t who = 0;
  if (!imuRead(REG_WHO_AM_I, &who, 1) || who != 0x6A) return false;
  return imuWrite(REG_CTRL3_C, 0x44)      // block data update, register auto-increment
         && imuWrite(REG_CTRL1_XL, 0x44)  // accelerometer 104 Hz, +-16 g
         && imuWrite(REG_CTRL2_G, 0x4C);  // gyroscope 104 Hz, +-2000 dps (70 mdps per count)
}

// ---- high-g accelerometer (ADXL375 on the external I2C bus, optional) -----------------------------
#define HIGHG_ADDR 0x53
#define HIGHG_DEVID 0x00          // reads 0xE5
#define HIGHG_BW_RATE 0x2C
#define HIGHG_POWER_CTL 0x2D
#define HIGHG_DATA_FORMAT 0x31
#define HIGHG_DATAX0 0x32
#define HIGHG_MG_PER_COUNT 49.0f
#define SCALE_LOWG 1   // packet mg per count without the high-g sensor (+-32 g fits)
#define SCALE_HIGHG 10 // with it (+-327 g fits)

static bool haveHighG = false;

static bool highgWrite(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(HIGHG_ADDR);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

static bool highgRead(uint8_t reg, uint8_t *buf, uint8_t len) {
  Wire.beginTransmission(HIGHG_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((uint8_t)HIGHG_ADDR, len) != len) return false;
  for (uint8_t i = 0; i < len; i++) buf[i] = Wire.read();
  return true;
}

static bool highgBegin() {
  Wire.begin();
  Wire.setClock(400000);
  uint8_t id = 0;
  if (!highgRead(HIGHG_DEVID, &id, 1) || id != 0xE5) return false;
  return highgWrite(HIGHG_BW_RATE, 0x0C)        // 400 Hz output, 200 Hz bandwidth: keeps short peaks
         && highgWrite(HIGHG_DATA_FORMAT, 0x0B)  // right-justified, +-200 g (49 mg per count)
         && highgWrite(HIGHG_POWER_CTL, 0x08);   // measure
}

// ---- state ------------------------------------------------------------------------------------
#define MAX_BATCH 19  // acc + gyro samples in one 244-byte notification
static lt_sample_t batch[MAX_BATCH];
static uint8_t batchCount = 0;
static uint32_t batchFirstMs = 0;
static uint16_t seq = 0;
static uint16_t clipped = 0;
static bool streaming = false;
static uint16_t connHandle = BLE_CONN_HANDLE_INVALID;
static uint32_t lastStatusMs = 0;

static uint8_t batteryPercent() {
#if defined(PIN_VBAT) && defined(VBAT_ENABLE)
  pinMode(VBAT_ENABLE, OUTPUT);
  digitalWrite(VBAT_ENABLE, LOW);  // connect the divider
  analogReference(AR_INTERNAL_3_0);
  analogReadResolution(12);
  float volts = analogRead(PIN_VBAT) * 3.0f / 4096.0f * 2.96f;  // 1M / 510k divider
  int pct = (int)((volts - 3.3f) / (4.2f - 3.3f) * 100.0f);
  return (uint8_t)constrain(pct, 0, 100);
#else
  return 255;  // unknown
#endif
}

static void sendStatus() {
  uint8_t s[6];
  s[0] = batteryPercent();
  s[1] = 0;  // flags: charging / recording / worn are not available on the v0 prototype
  lt_put16(s + 2, clipped);
  lt_put16(s + 4, 2);  // firmware version
  statusChar.write(s, sizeof(s));
  if (connHandle != BLE_CONN_HANDLE_INVALID) statusChar.notify(connHandle, s, sizeof(s));
}

static void flushBatch() {
  if (batchCount == 0 || connHandle == BLE_CONN_HANDLE_INVALID) {
    batchCount = 0;
    return;
  }
  uint8_t out[LT_HEADER_SIZE + MAX_BATCH * LT_RECORD_ACC_GYRO];
  uint16_t len = lt_build_packet(out, seq, batchFirstMs, SAMPLE_PERIOD_US, haveHighG ? SCALE_HIGHG : SCALE_LOWG, true, batch,
                                 batchCount);
  // If the radio queue is full the packet is dropped; the app sees the gap in the sequence numbers.
  streamChar.notify(connHandle, out, len);
  seq++;
  batchCount = 0;
}

static void onControl(uint16_t conn, BLECharacteristic *chr, uint8_t *data, uint16_t len) {
  (void)conn;
  (void)chr;
  if (len < 1) return;
  if (data[0] == 0x01) streaming = true;
  if (data[0] == 0x02) streaming = false;
  // 0x03 mark and 0x04 buzz need the button and motor of the custom board.
}

static void onConnect(uint16_t conn) {
  connHandle = conn;
  BLEConnection *c = Bluefruit.Connection(conn);
  c->requestPHY();                 // 2M PHY when the phone supports it
  c->requestDataLengthUpdate();
  c->requestMtuExchange(247);
  seq = 0;
  batchCount = 0;
  clipped = 0;
  streaming = true;  // the app only has to subscribe
}

static void onDisconnect(uint16_t conn, uint8_t reason) {
  (void)conn;
  (void)reason;
  connHandle = BLE_CONN_HANDLE_INVALID;
  streaming = false;
}

void setup() {
  pinMode(LED_RED, OUTPUT);
  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_BLUE, OUTPUT);
  digitalWrite(LED_RED, HIGH);  // LEDs are active low
  digitalWrite(LED_GREEN, HIGH);
  digitalWrite(LED_BLUE, HIGH);

  while (!imuBegin()) {  // keep trying, flashing red
    digitalWrite(LED_RED, LOW);
    delay(100);
    digitalWrite(LED_RED, HIGH);
    delay(900);
  }
  haveHighG = highgBegin();
  uint8_t led = haveHighG ? LED_GREEN : LED_RED;
  digitalWrite(led, LOW);
  delay(600);
  digitalWrite(led, HIGH);

  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);  // large MTU and queue for streaming
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.autoConnLed(false);

  char name[8];
  ble_gap_addr_t addr = Bluefruit.getAddr();
  snprintf(name, sizeof(name), "LT-%02X%02X", addr.addr[1], addr.addr[0]);
  Bluefruit.setName(name);
  Bluefruit.Periph.setConnectCallback(onConnect);
  Bluefruit.Periph.setDisconnectCallback(onDisconnect);
  Bluefruit.Periph.setConnInterval(6, 12);  // 7.5-15 ms

  service.begin();
  streamChar.setProperties(CHR_PROPS_NOTIFY);
  streamChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  streamChar.setMaxLen(244);
  streamChar.begin();
  controlChar.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  controlChar.setPermission(SECMODE_OPEN, SECMODE_OPEN);
  controlChar.setMaxLen(4);
  controlChar.setWriteCallback(onControl);
  controlChar.begin();
  statusChar.setProperties(CHR_PROPS_READ | CHR_PROPS_NOTIFY);
  statusChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  statusChar.setFixedLen(6);
  statusChar.begin();
  sendStatus();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addService(service);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(160, 400);  // 100-250 ms
  Bluefruit.Advertising.start(0);
}

void loop() {
  uint32_t now = millis();

  // LED: blue blink while advertising, green while streaming.
  bool connected = connHandle != BLE_CONN_HANDLE_INVALID;
  digitalWrite(LED_GREEN, connected ? LOW : HIGH);
  digitalWrite(LED_BLUE, (!connected && (now % 1000) < 60) ? LOW : HIGH);

  if (now - lastStatusMs > 10000) {
    lastStatusMs = now;
    sendStatus();
  }

  uint8_t status = 0;
  if (!imuRead(REG_STATUS, &status, 1) || !(status & 0x01)) {  // no new accelerometer sample yet
    delay(1);
    return;
  }
  uint8_t raw[12];
  if (!imuRead(REG_OUTX_L_G, raw, sizeof(raw))) return;
  if (!streaming || !connected || !streamChar.notifyEnabled(connHandle)) return;

  int16_t g[3], a[3];
  memcpy(g, raw, 6);
  memcpy(a, raw + 6, 6);
  float low[3], high[3] = {0, 0, 0}, fused[3];
  bool atLimit = false;
  for (uint8_t i = 0; i < 3; i++) {
    low[i] = a[i] * ACC_MG_PER_COUNT;
    if (a[i] >= ACC_LIMIT_COUNTS || a[i] <= -ACC_LIMIT_COUNTS) atLimit = true;
  }
  bool highOk = false;
  if (haveHighG) {
    uint8_t hraw[6];
    if (highgRead(HIGHG_DATAX0, hraw, sizeof(hraw))) {
      int16_t h[3];
      memcpy(h, hraw, 6);
      for (uint8_t i = 0; i < 3; i++) high[i] = h[i] * HIGHG_MG_PER_COUNT;
      highOk = true;
    }
  }
  if (atLimit && !highOk) clipped++;  // only a real loss when the high-g sensor can't cover it
  lt_fuse_mg(low, high, highOk, fused);
  uint8_t scale = haveHighG ? SCALE_HIGHG : SCALE_LOWG;
  lt_sample_t &s = batch[batchCount];
  s.ax = lt_to_counts(fused[0], scale);
  s.ay = lt_to_counts(fused[1], scale);
  s.az = lt_to_counts(fused[2], scale);
  s.gx = g[0];
  s.gy = g[1];
  s.gz = g[2];
  if (batchCount == 0) batchFirstMs = now;
  batchCount++;

  // Send ~10 packets per second, or earlier if the negotiated MTU only fits fewer samples.
  uint8_t fit = lt_max_samples(Bluefruit.Connection(connHandle)->getMtu() - 3, true);
  if (fit > MAX_BATCH) fit = MAX_BATCH;
  if (fit == 0) fit = 1;
  if (batchCount >= fit || batchCount >= 10) flushBatch();
}
