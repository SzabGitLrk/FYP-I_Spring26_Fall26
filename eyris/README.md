# EYRIS

A navigation aid for visually impaired users. The Android app names what is in front of the camera, says
which side it is on and how far away, and speaks it aloud. The camera is either the phone's own or an
ESP32-S3-EYE board with an HC-SR04 distance sensor. Detection runs on the phone itself.

## Run it on an Android phone

You need:

- Flutter 3.41.9 (the version it is built and tested with). Flutter 3.50 and newer need Gradle 9.3.1 or
  newer, but the project uses Gradle 8.14, so the build fails with "Your project's Gradle version is lower
  than Flutter's minimum"
- Android Studio, which brings the Android SDK and Java
- An Android phone with USB debugging switched on, and its cable

`flutter doctor` should show no problem under "Flutter" and "Android toolchain".

Put the folder at a short path such as `D:\eyris_app`. Windows can fail on long paths during the Android
build.

1. Open a terminal in this folder.
2. `flutter pub get`
3. Plug in the phone. `flutter devices` must list it.
4. `flutter run --release`

The first build downloads Gradle and Android components, so it needs internet and takes several minutes.
Use release mode: detection is slow in debug mode.

To make an APK instead of running from the PC:

```
flutter build apk --release
```

The file is `build\app\outputs\flutter-apk\app-release.apk`. Copy it to the phone and install it. It is
large (about 420 MB) because the offline map and the four detection models are inside it.

To check the code without a phone, run `flutter test`. All 51 tests should pass.

## First start

1. On the login screen tap **Create Account**, fill in the four fields, then log in. The account is kept
   only on the phone; there is no server.
2. Allow the permissions the app asks for (camera, location, microphone, nearby devices).
3. Open the **Camera** tab. It shows "Cannot start camera ... ESP32 camera IP is not configured" until a
   camera is chosen. Tap the settings (gear) icon at the top:
   - **Phone camera:** switch on "Use phone camera". The IP box must still hold a valid address, so type
     `192.168.43.204` if there is no board. Tap Apply.
   - **ESP32 camera:** leave the switch off, type the board's IP address, tap Apply.

The app then lists what it sees ("Door straight ahead · about 2 meters") and speaks the nearest objects.

## ESP32 camera and distance sensor (optional)

The sketch is `firmware/ESP32S3_EYE_Camera_HCSR04_UDP/ESP32S3_EYE_Camera_HCSR04_UDP.ino`, for an
ESP32-S3-EYE board with an HC-SR04 on GPIO 1 (TRIG) and GPIO 2 (ECHO, through a voltage divider to 3.3 V).

1. In the sketch, set `HOTSPOT_SSID` and `HOTSPOT_PASSWORD` to the phone's hotspot.
2. Upload it with the Arduino IDE (ESP32 boards package).
3. Open the Serial Monitor at 115200 baud. It prints `Camera IP: ...` once the board has joined the hotspot.
4. Type that IP into the app's Camera settings. The phone and the board must be on the same hotspot.

More detail is in `ESP32-CAMERA.md`.

## What is where

| Folder | Contents |
|---|---|
| `lib/` | The app. Detection is in `lib/services/yolo_detection_service.dart`; which model reports which object, and from what confidence, is in `lib/services/detection_models.dart`. |
| `assets/models/` | The four detection models and their class lists. |
| `assets/maps/`, `assets/routes/` | Offline map of Pakistan and prepared routes. |
| `test/` | Tests, run with `flutter test`. |
| `firmware/`, `arduino/` | Code for the ESP32 board. |
| `training/` | Scripts that trained and measured the models. They need the photo sets on the development PC and are not needed to run the app. |

`CHANGES.md` lists what changed and how accurate detection measured on test photos.
