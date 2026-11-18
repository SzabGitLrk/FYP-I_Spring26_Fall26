#pragma once

#include <WiFi.h>
#include <WiFiUdp.h>
#include <stdio.h>
#include <string.h>

constexpr uint16_t EYRIS_DISTANCE_UDP_PORT = 4567;

// Call once after Wi-Fi connects. The port is the local sender port; the app
// listens on UDP destination port 4567.
inline bool eyrisBeginDistanceBroadcast(WiFiUDP &udp) {
  return udp.begin(4568) == 1;
}

inline bool eyrisSendDistanceCentimeters(WiFiUDP &udp, int centimeters) {
  if (WiFi.status() != WL_CONNECTED || centimeters <= 0) return false;

  char payload[12];
  snprintf(payload, sizeof(payload), "%d", centimeters);

  const IPAddress subnetBroadcast = WiFi.broadcastIP();
  const IPAddress globalBroadcast(255, 255, 255, 255);
  bool subnetSent = false;
  bool globalSent = false;

  if (udp.beginPacket(subnetBroadcast, EYRIS_DISTANCE_UDP_PORT) == 1) {
    udp.write(reinterpret_cast<const uint8_t *>(payload), strlen(payload));
    subnetSent = udp.endPacket() == 1;
  }
  if (globalBroadcast != subnetBroadcast &&
      udp.beginPacket(globalBroadcast, EYRIS_DISTANCE_UDP_PORT) == 1) {
    udp.write(reinterpret_cast<const uint8_t *>(payload), strlen(payload));
    globalSent = udp.endPacket() == 1;
  } else if (globalBroadcast == subnetBroadcast) {
    globalSent = subnetSent;
  }
  return subnetSent || globalSent;
}
