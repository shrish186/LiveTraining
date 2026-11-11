// Stream packet layout: docs/sensor-protocol.md (v1). Plain C so it also compiles on a PC for the
// cross-check test (hardware/firmware/test_packet.cpp -> mobile/test/fixtures/sensor_packet.hex).
#pragma once
#include <stdint.h>
#include <string.h>

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
