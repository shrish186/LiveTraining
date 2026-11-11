// Builds stream packets with the firmware's own code (leg_sensor/packet.h) and prints them as hex.
// The app parses this output in mobile/test/sensor_protocol_test.dart, so the firmware and the
// app can't drift apart.
//   g++ -std=c++17 -o /tmp/test_packet test_packet.cpp && /tmp/test_packet > ../../mobile/test/fixtures/sensor_packet.hex
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
  return 0;
}
