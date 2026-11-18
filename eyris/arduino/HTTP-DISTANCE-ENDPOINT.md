# ESP32 HTTP distance endpoint

`eyris_distance_http_endpoint.h` adds a `/distance` GET handler that returns
`{"distance":45}` with centimeters and disables response caching. The complete
ESP32 camera sketch is not present in this workspace, so the board-specific
sensor and CameraWebServer startup files cannot be edited here. For the standard
ESP32 CameraWebServer implementation:

1. Include this header in `app_httpd.cpp`, where the port 80
   `httpd_handle_t camera_httpd` is available.
2. Declare the measurement shared with the sketch, for example
   `extern volatile int eyrisDistanceCm;`.
3. After the port 80 server has started, register the handler with
   `eyrisRegisterDistanceHttpEndpoint(camera_httpd, &eyrisDistanceCm);`.
4. In the sketch's sensor loop, assign the latest centimeter reading to
   `eyrisDistanceCm`. Keep the UDP broadcaster active as well.

The existing sketch's Wi-Fi credentials, ultrasonic pins, and web server
handles were not supplied, so those are intentionally left to the existing
firmware project.
