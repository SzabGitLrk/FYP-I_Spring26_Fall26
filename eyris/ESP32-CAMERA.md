# ESP32 camera integration

Open the existing Camera tab. It defaults to `http://10.105.21.204:81/stream`.
Use the settings icon in Camera or Device Connection to save a different IPv4
address when the hotspot assigns a new address. The app validates the IP and
expands it to `http://<IP>:81/stream`. The same saved address supplies the Connect screen's
CameraWebServer `/status` check on port 80. The phone and ESP32 must be on the
same reachable Wi-Fi/hotspot network.

The settings dialog also retains the original phone camera as an optional source.
The existing flash control works with the phone camera; it is disabled for the
ESP32 because an LED control is not guaranteed by the board/firmware configuration.

MJPEG frames are decoded in the existing preview, preserving their aspect ratio.
The existing YOLO detection, spoken alerts, alert history, and navigation remain
connected. Detection samples decoded frames rather than taking phone photos when
using the ESP32. A model failure is shown separately and does not hide the stream.

Use the Camera tab's tune icon for brightness, contrast and saturation controls
(`-1.0` to `+1.0`), plus Normal, Warm, Cool, Black & White, Sepia, Vintage,
and High Contrast filters. Apply saves the adjustments locally; Reset restores
normal values before applying. These adjustments alter the displayed preview,
without changing ESP32 firmware settings or the original frame supplied to YOLO.

Connections have eight-second HTTP-header and complete-frame timeouts, bounded
JPEG buffering, an error message, and manual Retry. No frames are queued for slow
decoders. The HTTP client and subscription close on disposal, app backgrounding,
route coverage, or opening settings. Returning resumes with the saved settings.

Android permits HTTP camera traffic and declares the CAMERA permission for the
retained phone-camera mode. No dependencies were added or upgraded.

## Files

- `lib/screens/camera_screen.dart`: preview, source selection, detection and lifecycle.
- `lib/screens/connect_screen.dart`: shared configured camera status endpoint.
- `lib/services/camera_settings.dart`: IPv4 validation and persistent settings.
- `lib/services/camera_adjustments.dart`: persistent visual adjustment state and color matrices.
- `lib/services/mjpeg_stream.dart`: cancellable HTTP stream and JPEG framing.
- `lib/services/camera_route_observer.dart`, `lib/main.dart`: route visibility.
- `lib/widgets/camera_settings_dialog.dart`: shared settings dialog.
- `lib/widgets/camera_adjustments_sheet.dart`: mobile adjustment controls.
- `lib/services/yolo_detection_service.dart`: model readiness and safe disposal.
- `android/app/src/main/AndroidManifest.xml`: Android network/camera configuration.
- `test/esp32_camera_test.dart`: parser, HTTP failures, timeouts, persistence,
  preview rendering, detection handoff, lifecycle and disposal tests.

## Validation

All nine Flutter tests passed, including the existing smoke test. The widget test
uses actual JPEG decoding and a simulated stream/detector; it does not validate
native TensorFlow inference on an Android device. Whole-project Flutter analysis
passed with only 16 existing informational `avoid_print` notices in
`scripts/generate_routes.dart`.

Evidence is in the workspace `build-cache/esp32-tests-final.log`,
`build-cache/esp32-analyze-final.log`, and `build-cache/esp32-android-build.log`.
The supplied camera IP and stream timed out from this computer and no Android
device was connected, so physical ESP32 playback remains to be checked on the
phone. No firmware changes or account changes were made.

Protocol reference: [Espressif CameraWebServer](https://github.com/espressif/arduino-esp32/blob/master/libraries/ESP32/examples/Camera/CameraWebServer/app_httpd.cpp).
Android reference: [Network security configuration](https://developer.android.com/privacy-and-security/security-config).
