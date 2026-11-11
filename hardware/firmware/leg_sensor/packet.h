// Stream packet layout: docs/sensor-protocol.md (v1). Plain C so it also compiles on a PC for the
// cross-check test (hardware/firmware/test_packet.cpp -> mobile/test/fixtures/sensor_packet.hex).
#pragma once
#include <stdint.h>
#include <string.h>
#include <math.h>

#define LT_PACKET_VERSION 1
#define LT_HEADER_SIZE 12
#define LT_FLAG_GYRO 0x01
#define LT_RECORD_ACC 6
#define LT_RECORD_ACC_GYRO 12

typedef struct {
  int16_t ax, ay, az;  // milli-g / scale_mg, gravity included
  int16_t gx, gy, gz;  // 70 mdps per count
} lt_sample_t;

static inline void lt_put16(uint8_t *p, uint16_t v) { p[0] = v & 0xFF; p[1] = v >> 8; }
static inline void lt_put32(uint8_t *p, uint32_t v) { lt_put16(p, v & 0xFFFF); lt_put16(p + 2, v >> 16); }

// How many samples fit in one notification of `payload` bytes (ATT MTU - 3).
static inline uint8_t lt_max_samples(uint16_t payload, bool gyro) {
  uint16_t record = gyro ? LT_RECORD_ACC_GYRO : LT_RECORD_ACC;
  if (payload < LT_HEADER_SIZE + record) return 0;
  uint16_t n = (payload - LT_HEADER_SIZE) / record;
  return n > 255 ? 255 : (uint8_t)n;
}

// Writes one packet into `out`; returns its length in bytes.
static inline uint16_t lt_build_packet(uint8_t *out, uint16_t seq, uint32_t first_ms, uint16_t period_us,
                                       uint8_t scale_mg, bool gyro, const lt_sample_t *samples, uint8_t n) {
  out[0] = LT_PACKET_VERSION;
  out[1] = gyro ? LT_FLAG_GYRO : 0;
  lt_put16(out + 2, seq);
  lt_put32(out + 4, first_ms);
  lt_put16(out + 8, period_us);
  out[10] = n;
  out[11] = scale_mg;
  uint8_t *p = out + LT_HEADER_SIZE;
  for (uint8_t i = 0; i < n; i++) {
    lt_put16(p, (uint16_t)samples[i].ax); lt_put16(p + 2, (uint16_t)samples[i].ay); lt_put16(p + 4, (uint16_t)samples[i].az);
    p += LT_RECORD_ACC;
    if (gyro) {
      lt_put16(p, (uint16_t)samples[i].gx); lt_put16(p + 2, (uint16_t)samples[i].gy); lt_put16(p + 4, (uint16_t)samples[i].gz);
      p += 6;
    }
  }
  return (uint16_t)(p - out);
}

// ---- low-g / high-g fusion -------------------------------------------------------------------
// The 6-axis IMU is precise but stops at +-16 g; the high-g accelerometer (ADXL375, +-200 g) is
// coarse (49 mg per count) but never clips on a landing. `high` is the hardest high-g sample since
// the previous IMU sample (the high-g chip runs 4x faster, so short impact peaks aren't missed).
// While both read below LT_BLEND_FROM_MG we send the precise reading. Towards the limit, or when
// the high-g chip caught a harder peak, we keep the IMU's direction but take the magnitude from the
// high-g sensor. Using only the magnitude means the two chips don't need their axes lined up: it
// works however the breakout sits in the case. All our metrics use |acc| anyway.
#define LT_LOWG_LIMIT_MG 16000.0f
#define LT_BLEND_FROM_MG 12000.0f

static inline void lt_fuse_mg(const float low[3], const float high[3], bool have_high, float out[3]) {
  out[0] = low[0]; out[1] = low[1]; out[2] = low[2];
  if (!have_high) return;
  float low_mag = sqrtf(low[0] * low[0] + low[1] * low[1] + low[2] * low[2]);
  float high_mag = sqrtf(high[0] * high[0] + high[1] * high[1] + high[2] * high[2]);
  float level = fmaxf(fabsf(low[0]), fmaxf(fabsf(low[1]), fabsf(low[2])));
  if (high_mag > level) level = high_mag;  // a peak the IMU sample missed
  if (level <= LT_BLEND_FROM_MG) return;
  float w = (level - LT_BLEND_FROM_MG) / (LT_LOWG_LIMIT_MG - LT_BLEND_FROM_MG);
  if (w > 1.0f) w = 1.0f;
  if (low_mag < 1.0f || high_mag <= low_mag) return;  // the high-g sensor shows nothing bigger
  float k = 1.0f + w * (high_mag / low_mag - 1.0f);
  out[0] = low[0] * k; out[1] = low[1] * k; out[2] = low[2] * k;
}

// mg -> packet counts at `scale_mg` per count, saturating at int16.
static inline int16_t lt_to_counts(float mg, uint8_t scale_mg) {
  float c = mg / (float)scale_mg;
  if (c > 32767.0f) return 32767;
  if (c < -32768.0f) return -32768;
  return (int16_t)lroundf(c);
}
