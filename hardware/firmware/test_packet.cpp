// Builds stream packets with the firmware's own code (leg_sensor/packet.h) and prints them as hex.
// The app parses this output in mobile/test/sensor_protocol_test.dart, so the firmware and the
// app can't drift apart.
//   g++ -std=c++17 -o /tmp/test_packet test_packet.cpp && /tmp/test_packet > ../../mobile/test/fixtures/sensor_packet.hex
#include <cassert>
#include <cmath>
#include <cstdio>

#include "leg_sensor/packet.h"

static void dump(const uint8_t *b, uint16_t n) {
  for (uint16_t i = 0; i < n; i++) printf("%02x", b[i]);
  printf("\n");
}

int main() {
  uint8_t out[300];
  // Line 1: acc + gyro, 3 samples. Standing still (1 g on y), then a hard landing, then rotation.
  lt_sample_t a[3] = {{0, 1000, 0, 0, 0, 0}, {-2500, 16000, 300, 10, -20, 30}, {12, 990, -7, 1000, 0, -1000}};
  dump(out, lt_build_packet(out, 513, 123456789u, 9615, 1, true, a, 3));
  // Line 2: acc only, high-g scale (10 mg per count): 250 g on x.
  lt_sample_t b[1] = {{25000, -100, 0, 0, 0, 0}};
  dump(out, lt_build_packet(out, 65535, 4000000000u, 1042, 10, false, b, 1));
  // Line 3: how many samples fit a 244-byte notification (acc+gyro, acc only) and a 20-byte one.
  printf("%d %d %d %d\n", lt_max_samples(244, true), lt_max_samples(244, false), lt_max_samples(20, true),
         lt_max_samples(20, false));
  // Fusion checks (asserts: the program fails if the fusion is wrong).
  float fo[3];
  const float still[3] = {0, 1000, 0}, hi_still[3] = {30, 980, -20};
  lt_fuse_mg(still, hi_still, true, fo);  // calm: the precise reading, untouched
  assert(fo[0] == 0 && fo[1] == 1000 && fo[2] == 0);
  const float clipped[3] = {16000, 4000, 0}, hi_land[3] = {-5000, 38000, 2000};  // axes differ, magnitude ~38.4 g
  lt_fuse_mg(clipped, hi_land, true, fo);
  float mag = sqrtf(fo[0] * fo[0] + fo[1] * fo[1] + fo[2] * fo[2]);
  float hi_mag = sqrtf(5000.0f * 5000 + 38000.0f * 38000 + 2000.0f * 2000);
  assert(fabsf(mag - hi_mag) < 1.0f);         // magnitude from the high-g sensor
  assert(fo[0] > 0 && fo[1] > 0);           // direction from the IMU
  lt_fuse_mg(clipped, hi_land, false, fo);   // no high-g sensor: unchanged
  assert(fo[0] == 16000);
  const float mid[3] = {13000, 0, 0}, hi_mid[3] = {13400, 0, 0};
  lt_fuse_mg(mid, hi_mid, true, fo);         // level 13.4 g = 35% into the blend: 35% of the way to the high-g value
  assert(fabsf(fo[0] - 13140) < 1.0f);
  const float off_peak[3] = {0, 8000, 0}, hi_peak[3] = {0, 30000, 0};  // IMU sampled beside a 30 g peak
  lt_fuse_mg(off_peak, hi_peak, true, fo);
  assert(fabsf(fo[1] - 30000) < 1.0f);
  const float walk[3] = {300, 2500, 0}, hi_walk[3] = {500, 3000, 0};  // both calm: precise reading kept
  lt_fuse_mg(walk, hi_walk, true, fo);
  assert(fo[1] == 2500);
  assert(lt_to_counts(250000.0f, 10) == 25000 && lt_to_counts(500000.0f, 10) == 32767);
  return 0;
}
