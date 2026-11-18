#pragma once

#include "esp_camera.h"

// Call once after esp_camera_init() succeeds in the ESP32 camera sketch.
// QVGA keeps MJPEG frames small; ESP32 camera quality uses lower values for
// better image quality, so 20 is a moderate JPEG quality setting.
inline bool eyrisApplyCameraDefaults() {
  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor == nullptr) return false;

  const int frameSizeResult = sensor->set_framesize(sensor, FRAMESIZE_QVGA);
  const int qualityResult = sensor->set_quality(sensor, 20);
  return frameSizeResult == 0 && qualityResult == 0;
}
