# EYRIS — AI Navigation System for Visually Impaired

EYRIS is an offline-first navigation app designed for visually impaired users in Sindh, Pakistan. It combines pre-computed map routing, voice guidance, GPS tracking, and on-device AI obstacle detection (YOLOv8) to help users navigate independently.

## Features

- 🗺️ **Offline map tiles** — Karachi and Larkana coverage, no internet needed
- 🧭 **Pre-computed routing** — real road-following routes between known places
- 🎤 **Voice search** — say a place name, fuzzy match finds it
- 🔊 **Turn-by-turn voice guidance** — TTS announces every step
- 👋 **Manual + automatic step modes** — toggle for testing or hands-free use
- ⚠️ **Stationary alert** — warns if user hasn't moved in 5 minutes
- 📜 **Alert history** — saved log of all alerts
- 🤖 **YOLOv8 obstacle detection** — on-device camera analysis
- 🔋 **Device status** — phone + smart glasses battery monitoring
- 🚶 🚴 🚗 **Transport modes** — walking, biking, driving ETAs

---

## Prerequisites

- **Flutter SDK** 3.5 or higher
- **Android Studio** with Android SDK (API 21 minimum)
- **Java 21+** (Temurin recommended) — for the route generation script
- **Dart SDK** (comes with Flutter)
- Android device or emulator

Verify your setup:

```
flutter doctor
```

---

## Setup Instructions

### 1. Clone the repo

```
git clone https://github.com/SzabGitLrk/FYP-I_Spring26_Fall26.git
cd FYP-I_Spring26_Fall26
git checkout eyris
cd eyris
```

### 2. Install Flutter dependencies

```
flutter pub get
```

### 3. Download the map tiles

The offline map file is hosted on Google Drive (too large for GitHub).

📁 **Download:** [Pakistan Map Tiles (.mbtiles)](https://drive.google.com/file/d/1Xg8wiaCEhXsLEQHWRbuM6iHJ2i6FnfPf/view?usp=drive_link)

- Extract the zip
- Place `pakistan.mbtiles` at:
  ```
  eyris/assets/maps/pakistan.mbtiles
  ```

### 4. Get the pre-computed routes

You have two options:

**Option A — Download (faster)**

📁 **Download:** [Pre-computed Routes (zip)](https://drive.google.com/file/d/1KfATUX4774zWrXmc83Aat-fwqOebG0jO/view?usp=drive_link)

- Extract the zip
- Place all `.json` files at:
  ```
  eyris/assets/routes/
  ```

**Option B — Generate (requires internet, ~15 min)**

```
dart pub get
dart run scripts/generate_routes.dart
```

The script reads `assets/places.json`, calls OSRM's free routing API for each origin–destination pair, and saves routes to `assets/routes/`. Skips routes that already exist, so safe to re-run.

### 5. Run the app

Connect an Android device (with USB debugging enabled) or start an emulator. Then:

```
flutter run
```

First build takes 5–15 minutes (Gradle downloads dependencies).

---

## Project Structure

```
eyris/
├── android/                 # Android platform config
├── assets/
│   ├── maps/                # Offline map tiles (downloaded separately)
│   ├── models/              # YOLOv8 model + labels
│   ├── routes/              # Pre-computed route JSONs
│   └── places.json          # Origins + destinations + city landmarks
├── lib/
│   ├── main.dart            # App entry point
│   ├── models/              # Data models
│   ├── services/            # Place lookup, routing, alerts, etc.
│   └── screens/             # UI screens
├── scripts/
│   └── generate_routes.dart # OSRM route pre-computation script
├── pubspec.yaml             # Flutter dependencies
└── README.md
```

---

## How It Works

### Offline routing

Real navigation apps run a routing engine on-device — that's complex. EYRIS uses a simpler **multi-anchor pre-computation** approach:

1. We define ~10 "origins" — university, hospital, market, station, mosque in each anchor city (Larkana, Karachi)
2. We define ~130 destinations across Sindh
3. Before shipping, the script calls OSRM to compute the actual road route between every (origin, destination) pair
4. At runtime, the app loads the appropriate pre-computed route — fully offline

This trades flexibility (routes only from fixed origins) for true offline operation and instant load times.

### Map tiles

The app uses OpenStreetMap raster tiles in **MBTiles** format. Downloaded with **MOBAC** (Mobile Atlas Creator), merged with sqlite3, then bundled.

### Voice search

Speech-to-text often misrecognizes Urdu/local place names. The `OfflinePlaceService.findBestMatch()` method uses:

- Token-overlap matching (Jaccard-like)
- Character similarity (Levenshtein distance, normalized)
- City-preference boost (matches places near user's selected origin)

So "Karachi Sadar" finds **Karachi Saddar**, "Mazar Quaid" finds **Mazar-e-Quaid**.

---

## Known Limitations

- Routes are pre-computed from **fixed origins only**, not from the user's exact current location
- Map tile coverage limited to **Karachi + Larkana** city areas (route lines pass through blank space for inter-city travel)
- Voice input requires internet on most Android phones (speech-to-text is cloud-based by default)
- Bundled tile file is ~200 MB; downloaded separately to avoid GitHub size limits

## Future Work

- Native GraphHopper integration for true on-device any-to-any routing
- Vector tiles + MapLibre for crisper rendering and smaller file size
- BLE/WiFi pairing with custom smart glasses hardware (ESP32-CAM)
- Multilingual voice (English + Urdu + Sindhi)

---

## Team

- Project type: Final Year Project
- Repository: [FYP-I_Spring26_Fall26](https://github.com/SzabGitLrk/FYP-I_Spring26_Fall26) (branch: `eyris`)

## License

For academic use. Built on:

- [OpenStreetMap](https://openstreetmap.org) data (ODbL)
- [OSRM](http://project-osrm.org/) routing engine
- [Flutter](https://flutter.dev) framework
- [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics) object detection
