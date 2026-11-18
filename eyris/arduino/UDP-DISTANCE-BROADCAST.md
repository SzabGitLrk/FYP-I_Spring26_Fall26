# ESP32 UDP distance sender

Include `eyris_udp_distance_broadcast.h` in the existing ESP32 camera sketch.
After Wi-Fi connects, initialize one global `WiFiUDP` with
`eyrisBeginDistanceBroadcast(udp)`. In `loop()`, use a 150 ms timer and pass
the current ultrasonic measurement in whole centimeters to
`eyrisSendDistanceCentimeters(udp, distanceCm)`. The helper sends a plain
integer datagram to both the subnet broadcast address and `255.255.255.255`,
on destination port 4567.

Example to add to the existing sketch (replace `readUltrasonicCm()` with that
sketch's sensor routine):

```cpp
#include "eyris_udp_distance_broadcast.h"

WiFiUDP distanceUdp;
uint32_t lastDistanceBroadcastMs = 0;

// In setup(), after WiFi is connected:
eyrisBeginDistanceBroadcast(distanceUdp);

// In loop():
if (uint32_t(millis() - lastDistanceBroadcastMs) >= 150) {
  lastDistanceBroadcastMs = millis();
  const int distanceCm = readUltrasonicCm();
  if (distanceCm > 0) {
    eyrisSendDistanceCentimeters(distanceUdp, distanceCm);
  }
}
```

The existing sketch's ultrasonic pin setup and Wi-Fi credentials are not in
this workspace, so retain those board-specific parts unchanged.
