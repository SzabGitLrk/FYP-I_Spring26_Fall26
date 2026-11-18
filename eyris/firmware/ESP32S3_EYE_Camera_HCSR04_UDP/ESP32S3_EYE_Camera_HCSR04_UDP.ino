/*
  Standalone ESP32-S3-EYE camera + HC-SR04 + UDP distance sender.

  Board profile: Espressif ESP32-S3-EYE pin map from the Arduino-ESP32
  CameraWebServer example. Camera MJPEG: http://<board-ip>:81/stream
  Status endpoint: http://<board-ip>/status
  Distance packets: UDP unicast to the phone hotspot gateway and subnet broadcast on port 4567.

  GPIO 1 (TRIG) and GPIO 2 (ECHO) are not camera pins in this selected profile.
  HC-SR04 ECHO may output 5 V: use a voltage divider/level shifter to keep the
  ESP32-S3 input at 3.3 V or below. Replace Wi-Fi credentials before flashing.
  For a different ESP32-S3-CAM board, its camera pin map must be substituted.
*/

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include "esp_camera.h"
#include "esp_http_server.h"
#include "driver/gpio.h"

// ---------- EDIT THESE TWO VALUES before flashing ----------
// Use the exact phone hotspot name/password. Keep credentials on your PC;
// do not paste them into issue reports or commit them to source control.
static const char *HOTSPOT_SSID = "zaeem";
static const char *HOTSPOT_PASSWORD = "00000000";

// ---------- HC-SR04 pins requested ----------
static constexpr gpio_num_t TRIG_PIN = GPIO_NUM_1;
static constexpr gpio_num_t ECHO_PIN = GPIO_NUM_2;
static constexpr uint16_t APP_UDP_PORT = 4567;
static constexpr uint16_t UDP_LOCAL_PORT = 4568;
static constexpr uint32_t PING_INTERVAL_US = 200000;  // 200 ms
static constexpr uint32_t ECHO_TIMEOUT_US = 35000;

// ---------- ESP32-S3-EYE camera pin map ----------
static constexpr int CAM_PWDN = -1;
static constexpr int CAM_RESET = -1;
static constexpr int CAM_XCLK = 15;
static constexpr int CAM_SIOD = 4;
static constexpr int CAM_SIOC = 5;
static constexpr int CAM_Y2 = 11;
static constexpr int CAM_Y3 = 9;
static constexpr int CAM_Y4 = 8;
static constexpr int CAM_Y5 = 10;
static constexpr int CAM_Y6 = 12;
static constexpr int CAM_Y7 = 18;
static constexpr int CAM_Y8 = 17;
static constexpr int CAM_Y9 = 16;
static constexpr int CAM_VSYNC = 6;
static constexpr int CAM_HREF = 7;
static constexpr int CAM_PCLK = 13;

static WiFiUDP distanceUdp;
static httpd_handle_t cameraHttpd = nullptr;
static httpd_handle_t streamHttpd = nullptr;
static volatile int currentDistanceCm = 0;
static volatile uint32_t lastDistanceUpdatedAtMs = 0;

// Echo ISR captures pulse width; no pulseIn() blocking the Arduino loop.
static volatile uint32_t echoRiseUs = 0;
static volatile uint32_t echoWidthUs = 0;
static volatile bool echoReady = false;

static void IRAM_ATTR echoEdgeIsr() {
  const uint32_t now = micros();
  if (gpio_get_level(ECHO_PIN) != 0) {
    echoRiseUs = now;
  } else if (echoRiseUs != 0) {
    echoWidthUs = now - echoRiseUs;
    echoRiseUs = 0;
    echoReady = true;
  }
}

static IPAddress subnetBroadcastAddress() {
  const IPAddress local = WiFi.localIP();
  const IPAddress mask = WiFi.subnetMask();
  uint8_t octet[4];
  for (int i = 0; i < 4; ++i) {
    octet[i] = (local[i] & mask[i]) | static_cast<uint8_t>(~mask[i]);
  }
  return IPAddress(octet[0], octet[1], octet[2], octet[3]);
}

static bool sendUdpPacket(const IPAddress &target, const char *payload) {
  if (!distanceUdp.beginPacket(target, APP_UDP_PORT)) return false;
  distanceUdp.write(reinterpret_cast<const uint8_t *>(payload), strlen(payload));
  return distanceUdp.endPacket() == 1;
}

static void sendDistancePacket(uint32_t pulseWidthUs) {
  // HC-SR04 round-trip time: distance cm = echo microseconds / 58.
  const int centimeters = static_cast<int>((pulseWidthUs + 29U) / 58U);
  if (centimeters <= 0 || centimeters > 450) return;
  currentDistanceCm = centimeters;
  lastDistanceUpdatedAtMs = millis();

  char payload[64];
  // Flutter UDP parser consumes distanceMeters; HTTP accepts distanceCm.
  snprintf(payload, sizeof(payload),
           "{\"distanceCm\":%d,\"distanceMeters\":%.2f}",
           centimeters, centimeters / 100.0);

  // Send directly to phone hotspot gateway, plus subnet broadcast.
  const IPAddress gateway = WiFi.gatewayIP();
  const IPAddress broadcast = subnetBroadcastAddress();
  const bool unicastSent = sendUdpPacket(gateway, payload);
  const bool broadcastSent = sendUdpPacket(broadcast, payload);
  Serial.printf(">> LIVE DISTANCE: %d cm\n", centimeters);
  Serial.printf("UDP sent: %d cm; gateway %s:%u %s; broadcast %s:%u %s\n",
                centimeters, gateway.toString().c_str(), APP_UDP_PORT,
                unicastSent ? "OK" : "FAILED",
                broadcast.toString().c_str(), APP_UDP_PORT,
                broadcastSent ? "OK" : "FAILED");
}

// ---------- Camera HTTP handlers ----------
static esp_err_t statusHandler(httpd_req_t *request) {
  httpd_resp_set_type(request, "application/json");
  httpd_resp_set_hdr(request, "Access-Control-Allow-Origin", "*");
  const String body = String("{\"camera\":\"ok\",\"stream\":\"http://") +
                      WiFi.localIP().toString() + ":81/stream\"}";
  return httpd_resp_send(request, body.c_str(), body.length());
}

static esp_err_t distanceHandler(httpd_req_t *request) {
  const bool fresh = lastDistanceUpdatedAtMs != 0 &&
      static_cast<uint32_t>(millis() - lastDistanceUpdatedAtMs) <= 3500;
  const int centimeters = fresh ? currentDistanceCm : 0;
  const uint32_t ageMs = lastDistanceUpdatedAtMs == 0
      ? UINT32_MAX
      : static_cast<uint32_t>(millis() - lastDistanceUpdatedAtMs);
  char body[160];
  snprintf(body, sizeof(body),
           "{\"available\":%s,\"distance\":%d,\"distanceCm\":%d,\"distanceMeters\":%.2f,\"ageMs\":%lu}",
           fresh ? "true" : "false", centimeters, centimeters,
           centimeters / 100.0, static_cast<unsigned long>(ageMs));
  httpd_resp_set_type(request, "application/json");
  httpd_resp_set_hdr(request, "Cache-Control", "no-store");
  httpd_resp_set_hdr(request, "Access-Control-Allow-Origin", "*");
  Serial.printf("HTTP /distance response: %d cm\n", centimeters);
  return httpd_resp_send(request, body, HTTPD_RESP_USE_STRLEN);
}
static esp_err_t rootHandler(httpd_req_t *request) {
  httpd_resp_set_type(request, "text/plain");
  const String body = String("ESP32-S3-EYE ready. MJPEG: http://") +
                      WiFi.localIP().toString() + ":81/stream\n";
  return httpd_resp_send(request, body.c_str(), body.length());
}

static esp_err_t streamHandler(httpd_req_t *request) {
  static const char *STREAM_TYPE =
      "multipart/x-mixed-replace;boundary=frame";
  static const char *BOUNDARY = "\r\n--frame\r\n";
  static const char *PART_HEADER =
      "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

  esp_err_t result = httpd_resp_set_type(request, STREAM_TYPE);
  if (result != ESP_OK) return result;
  httpd_resp_set_hdr(request, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(request, "Cache-Control", "no-store");

  char header[64];
  while (true) {
    camera_fb_t *frame = esp_camera_fb_get();
    if (frame == nullptr) {
      Serial.println("Camera frame capture failed");
      return ESP_FAIL;
    }

    const int headerLength = snprintf(header, sizeof(header), PART_HEADER,
                                      static_cast<unsigned int>(frame->len));
    result = httpd_resp_send_chunk(request, BOUNDARY, strlen(BOUNDARY));
    if (result == ESP_OK) {
      result = httpd_resp_send_chunk(request, header, headerLength);
    }
    if (result == ESP_OK) {
      result = httpd_resp_send_chunk(
          request, reinterpret_cast<const char *>(frame->buf), frame->len);
    }
    esp_camera_fb_return(frame);
    if (result != ESP_OK) break;  // client closed; let web server release it
  }
  return result;
}

static bool startCameraServers() {
  httpd_config_t cameraConfig = HTTPD_DEFAULT_CONFIG();
  cameraConfig.server_port = 80;
  cameraConfig.ctrl_port = 32768;
  cameraConfig.max_uri_handlers = 4;
  cameraConfig.stack_size = 8192;

  if (httpd_start(&cameraHttpd, &cameraConfig) != ESP_OK) {
    Serial.println("Could not start camera HTTP server on port 80");
    return false;
  }

  httpd_uri_t rootUri = {};
  rootUri.uri = "/";
  rootUri.method = HTTP_GET;
  rootUri.handler = rootHandler;
  httpd_register_uri_handler(cameraHttpd, &rootUri);

  httpd_uri_t statusUri = {};
  statusUri.uri = "/status";
  statusUri.method = HTTP_GET;
  statusUri.handler = statusHandler;
  httpd_register_uri_handler(cameraHttpd, &statusUri);
  httpd_uri_t distanceUri = {};
  distanceUri.uri = "/distance";
  distanceUri.method = HTTP_GET;
  distanceUri.handler = distanceHandler;
  if (httpd_register_uri_handler(cameraHttpd, &distanceUri) != ESP_OK) {
    Serial.println("Could not register HTTP GET /distance");
    return false;
  }
  Serial.println("HTTP GET /distance registered on port 80");

  httpd_config_t streamConfig = HTTPD_DEFAULT_CONFIG();
  streamConfig.server_port = 81;
  streamConfig.ctrl_port = 32769;
  streamConfig.max_uri_handlers = 2;
  streamConfig.stack_size = 8192;
  streamConfig.task_priority = tskIDLE_PRIORITY + 5;

  if (httpd_start(&streamHttpd, &streamConfig) != ESP_OK) {
    Serial.println("Could not start MJPEG stream server on port 81");
    return false;
  }

  httpd_uri_t streamUri = {};
  streamUri.uri = "/stream";
  streamUri.method = HTTP_GET;
  streamUri.handler = streamHandler;
  httpd_register_uri_handler(streamHttpd, &streamUri);
  return true;
}

static bool startCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = CAM_Y2;
  config.pin_d1 = CAM_Y3;
  config.pin_d2 = CAM_Y4;
  config.pin_d3 = CAM_Y5;
  config.pin_d4 = CAM_Y6;
  config.pin_d5 = CAM_Y7;
  config.pin_d6 = CAM_Y8;
  config.pin_d7 = CAM_Y9;
  config.pin_xclk = CAM_XCLK;
  config.pin_pclk = CAM_PCLK;
  config.pin_vsync = CAM_VSYNC;
  config.pin_href = CAM_HREF;
  config.pin_sccb_sda = CAM_SIOD;
  config.pin_sccb_scl = CAM_SIOC;
  config.pin_pwdn = CAM_PWDN;
  config.pin_reset = CAM_RESET;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 12;
  config.fb_count = psramFound() ? 2 : 1;
  config.grab_mode = psramFound() ? CAMERA_GRAB_LATEST : CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;

  const esp_err_t error = esp_camera_init(&config);
  if (error != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", error);
    return false;
  }
  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor != nullptr) sensor->set_vflip(sensor, 1);  // ESP32-S3-EYE mount
  return true;
}

static void serviceUltrasonic() {
  static uint32_t lastPingUs = 0;
  static uint32_t triggerHighAtUs = 0;
  static uint32_t lastTriggerAtUs = 0;
  static bool triggerIsHigh = false;
  static bool waitingForEcho = false;
  const uint32_t now = micros();

  if (triggerIsHigh && static_cast<uint32_t>(now - triggerHighAtUs) >= 10) {
    digitalWrite(static_cast<uint8_t>(TRIG_PIN), LOW);
    triggerIsHigh = false;
    lastPingUs = now;
  }

  if (!triggerIsHigh &&
      static_cast<uint32_t>(now - lastPingUs) >= PING_INTERVAL_US) {
    noInterrupts();
    echoRiseUs = 0;
    echoReady = false;
    interrupts();
    digitalWrite(static_cast<uint8_t>(TRIG_PIN), HIGH);
    triggerHighAtUs = now;
    lastTriggerAtUs = now;
    waitingForEcho = true;
    triggerIsHigh = true;
  }

  bool haveEcho = false;
  bool noEcho = false;
  uint32_t widthUs = 0;
  noInterrupts();
  if (echoReady) {
    widthUs = echoWidthUs;
    echoReady = false;
    haveEcho = true;
    waitingForEcho = false;
  } else if (waitingForEcho &&
             static_cast<uint32_t>(now - lastTriggerAtUs) > ECHO_TIMEOUT_US) {
    echoRiseUs = 0;
    waitingForEcho = false;
    noEcho = true;
  }
  interrupts();

  if (haveEcho && widthUs <= ECHO_TIMEOUT_US) sendDistancePacket(widthUs);
  if (noEcho) Serial.println("Distance: unavailable (HC-SR04 echo timeout)");
}

void setup() {
  Serial.begin(115200);
  delay(100);

  pinMode(static_cast<uint8_t>(TRIG_PIN), OUTPUT);
  digitalWrite(static_cast<uint8_t>(TRIG_PIN), LOW);
  pinMode(static_cast<uint8_t>(ECHO_PIN), INPUT);
  attachInterrupt(digitalPinToInterrupt(static_cast<uint8_t>(ECHO_PIN)),
                  echoEdgeIsr, CHANGE);

  if (!startCamera()) {
    Serial.println("Camera failed; check board profile and PSRAM settings.");
    return;
  }

  if (strcmp(HOTSPOT_SSID, "EDIT_PHONE_HOTSPOT_NAME") == 0 ||
      strcmp(HOTSPOT_PASSWORD, "EDIT_PHONE_HOTSPOT_PASSWORD") == 0) {
    Serial.println("CONFIG ERROR: edit HOTSPOT_SSID and HOTSPOT_PASSWORD in this sketch before upload.");
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(HOTSPOT_SSID, HOTSPOT_PASSWORD);
  Serial.printf("Connecting to hotspot '%s'", HOTSPOT_SSID);
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print('.');
  }
  Serial.println();
  Serial.printf("Wi-Fi connected. Camera IP: %s\n",
                WiFi.localIP().toString().c_str());

  if (distanceUdp.begin(UDP_LOCAL_PORT) == 0) {
    Serial.println("UDP local socket init failed");
  }
  Serial.printf("Distance targets: hotspot gateway %s:%u and broadcast %s:%u\n",
                WiFi.gatewayIP().toString().c_str(), APP_UDP_PORT,
                subnetBroadcastAddress().toString().c_str(), APP_UDP_PORT);

  if (!startCameraServers()) {
    Serial.println("Camera HTTP server startup failed");
    return;
  }
  Serial.printf("MJPEG: http://%s:81/stream\n", WiFi.localIP().toString().c_str());
}

void loop() {
  serviceUltrasonic();
  // No pulseIn() and no loop delay: HTTP streaming tasks keep running.
  yield();
}
