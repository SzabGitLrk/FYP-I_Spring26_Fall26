# Zavira: A Smart Emergency Response Wearable for Women Using IoT Technology

Zavira is an IoT-based wearable safety device built to provide women with a fast, reliable, and offline-capable way to send emergency alerts. The system combines an ESP32-based wearable device with GPS and GSM technology, paired with a Flutter mobile application, so that help can be reached even in areas with weak or no internet connectivity.

## Why Zavira?

Existing safety devices and smartphone apps often rely on continuous internet access and manual activation, which makes them unreliable in semi-urban or rural areas, or in situations where the user is unable to operate their phone due to panic or physical restraint. Zavira addresses this by using GSM/SMS for communication instead of the internet, and by combining manual and automatic alert triggers so help can be summoned even without direct user interaction.

## Key Features

- **Real-time GPS-based SMS alerts** sent directly to pre-registered emergency contacts, without requiring internet access.
- **Manual panic button** with short press (cancel) and long press (immediate emergency trigger) logic.
- **Geofence-based automatic alerts** that detect when the user exits a predefined safe zone and start an alert sequence automatically.
- **Reverse timer mechanism** that gives the user a short window (e.g. 5 minutes) to cancel an alert before it is sent, reducing false alarms.
- **Secure GPS transmission** using AES-128 encryption and Base64 encoding, decrypted and decoded only within the mobile app for display on OpenStreetMap.
- **Companion mobile app** for managing emergency contacts, viewing alert history, configuring geofences, and monitoring device battery status.
- **Offline-first operation** for the wearable device, with the mobile app working both online and offline (map visualization requires internet).
- **Last known location fallback** when GPS signal is unavailable, with automatic retry every 30–60 seconds.

## System Overview

The wearable device is built around an ESP32 microcontroller that handles event-driven firmware logic, including panic button detection, geofence monitoring, reverse timer management, and GPS data encryption. When an alert is triggered, the device retrieves GPS coordinates (or the last known location), encrypts and encodes the data, and sends it via SMS through a GSM module to all registered emergency contacts. The mobile app receives and parses these alerts, decrypts the location data, logs the alert history, and displays the location on a map.

## Tech Stack

**Hardware**
- ESP32 microcontroller
- Neo-6M GPS module
- SIM800L GSM module
- Li-Po battery with charging module
- Custom PCB and 3D-printed wearable case

**Software**
- Arduino IDE (firmware development)
- Flutter 3.41 (mobile application)
- Firebase Cloud Firestore (real-time data storage and synchronization)
- OpenStreetMap (location visualization)
- AES-128 encryption with Base64 encoding (secure SMS data transmission)

## Project Structure

```
lib/
├── screens/
│   ├── alert_history.dart      # Displays past emergency alerts
│   ├── battery.dart            # Wearable device battery status
│   ├── contacts.dart           # Manage emergency contacts
│   ├── geofence.dart           # Configure safe zones
│   ├── home.dart               # Main dashboard
│   ├── login.dart              # User login
│   ├── signup.dart             # User registration
│   ├── sos_service.dart        # Core SOS/alert logic
│   ├── splash_screen.dart      # App launch screen
│   └── tracking.dart           # Live/last known location tracking
└── main.dart                   # App entry point
```

## Project Status

This repository contains the Zavira mobile application, developed as part of the Final Year Project (FYP-I). Core authentication (login/signup) and home screen functionality are implemented, with additional screens (alert history, contact management, geofence configuration, tracking, and battery status) planned for upcoming iterations.
