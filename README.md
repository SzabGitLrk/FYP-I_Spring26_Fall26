# 🚌 University Point Locator - Larkana

**A Real-time Transport Tracking Mobile Application for Students**

[![Flutter](https://img.shields.io/badge/Flutter-3.24+-blue.svg)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-green.svg)](https://supabase.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 📱 Project Overview

University Point Locator is a mobile application designed to solve the critical problem faced by university students in Larkana who wait endlessly at roadside pickup points without knowing when their transport vehicle will arrive. The app provides real-time GPS tracking of university transport buses across multiple routes, allowing students to view live bus locations on an interactive map, receive accurate Estimated Time of Arrival (ETA) calculations, and get bus-approach alerts on the map while it is open.

## 🎯 Problem Statement

> *"Students in Larkana wait at roadside pickup points without knowing whether their transport vehicle is coming, how long it will take, or if it has already passed."*

### Impact:
- ❌ 30-60 minutes wasted daily per student
- ❌ Anxiety about being late for classes
- ❌ Missed vehicles due to uncertainty
- ❌ No safety mechanism during waiting periods

## ✨ Key Features

### 👨‍🎓 Student Features
- View The University of Larkana
- Select from 3 routes (PTS, Nae Dare → PTS, OPP Colony)
- View 8 pickup points with order numbers and landmarks
- Real-time bus tracking on OpenStreetMap (flutter_map)
- Color-coded markers (Green=First, Blue=Intermediate, Red=Last)
- Bus markers (Azure=Moving, Purple=Stopped) rotated to the bus heading
- ETA (Estimated Time of Arrival) calculation using Haversine formula
- Bus-approach alerts on the map (in-app while the map screen is open)
- SOS Emergency button with location sharing
- Favorite stops management (synced with your stop notifications)

### 👨‍✈️ Driver Features
- Driver dashboard with welcome card
- Route selection dropdown
- Start/End trip functionality
- Live GPS location sharing
- Real-time speed display
- Trip statistics (duration, distance, pickups)
- Trip history for drivers

### 👑 Admin Features
- Admin dashboard with statistics cards
- View total students, drivers, buses, active trips
- View and resolve SOS alerts
- Approve/Reject driver registrations
- View all buses list

### 🔐 Security Features
- Email/Password registration and login
- Role-based access (Student, Driver, Admin) resolved server-side from `profiles`
- Session persistence and secure logout
- Row Level Security (RLS) in database

## 🛠️ Technology Stack

| Component | Technology |
|-----------|------------|
| **Frontend** | Flutter (Dart) |
| **Backend** | Supabase (PostgreSQL) |
| **Maps** | flutter_map + OpenStreetMap (**no API key, no billing**) |
| **Notifications** | flutter_local_notifications (local only) |
| **Location** | Geolocator Plugin |
| **State Management** | setState + StreamBuilder |

## 📊 Database Schema

### Tables (13)
- universities (1 record)
- routes (3 records)
- pickup_points (8 records)
- buses (4 records)
- bus_locations (4 records)
- profiles (User profiles)
- sos_alerts (Emergency alerts)
- otp_verification (OTP codes)
- admin_settings (Admin configuration)
- stop_notifications (User preferences)
- user_devices (Device registration)
- trips (Driver history)
- bus_notifications (Notification logs)

## 📁 Project Structure

```
university_point_locator/
├── lib/
│   ├── main.dart
│   ├── config/
│   │   └── app_config.dart
│   ├── models/
│   │   ├── university.dart
│   │   ├── route_model.dart
│   │   ├── pickup_point.dart
│   │   ├── bus.dart
│   │   ├── bus_location.dart
│   │   └── profile.dart
│   ├── screens/
│   │   ├── login_screen.dart
│   │   ├── role_router.dart
│   │   ├── university_list_screen.dart
│   │   ├── routes_list_screen.dart
│   │   ├── pickup_points_screen.dart
│   │   ├── map_screen.dart
│   │   ├── admin/
│   │   │   └── admin_dashboard.dart
│   │   ├── driver/
│   │   │   ├── driver_dashboard.dart
│   │   │   └── trip_history.dart
│   │   └── student/
│   │       └── profile_screen.dart
│   ├── services/
│   │   ├── supabase_service.dart
│   │   ├── notification_service.dart
│   │   └── route_service.dart
│   ├── navigation/
│   │   ├── route_follower.dart
│   │   └── route_step.dart
│   ├── utils/
│   │   ├── app_theme.dart
│   │   └── helpers.dart
│   └── widgets/
│       ├── map_legend.dart
│       ├── bus_count_indicator.dart
│       ├── loading_error.dart
│       ├── info_row.dart
│       └── stat_card.dart
├── test/
│   ├── widget_test.dart
│   └── navigation_test.dart
├── assets/
│   └── icons/
├── android/
├── supabase_security_fix.sql
├── pubspec.yaml
└── README.md
```

## 🚀 Installation Guide

### Prerequisites
- Flutter SDK 3.24+
- Android Studio / VS Code
- Android SDK (min API 21)
- Supabase account

> **No maps API key or billing account is required.** Maps are rendered with
> `flutter_map` against OpenStreetMap's public tile servers, so there is no
> Google Cloud setup step. Note that OSM's
> [tile usage policy](https://operations.osmfoundation.org/policies/tiles/)
> applies: attribution is built in, and a dedicated tile host should be used
> before production-scale traffic.

### Clone Repository
```bash
git clone https://github.com/SzabGitLrk/FYP-I_Spring26_Fall26.git
cd FYP-I_Spring26_Fall26/university_point_locator
```

### Get Dependencies
```bash
flutter pub get
```

### Run the App
```bash
flutter run
```

### Build APK
```bash
flutter build apk --release
```

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Total Lines of Code** | 5,000+ |
| **Screens Developed** | 10 |
| **Database Tables** | 13 |
| **Universities Covered** | 1 |
| **Routes** | 3 |
| **Pickup Points** | 8 |
| **Buses** | 4 |
| **User Roles** | 3 |
| **External APIs Integrated** | 4 |

## 👥 Team Members

| Name | Registration No. |
|------|------------------|
| **Sanjay Kumar Wishwani** | 2212183 |
| **Shakeel Ahmed Bugti** | 2212185 |

## 👨‍🏫 Supervisor

**Dr. Mumtaz Hussain Mehar**

## 🎓 Institution

**Shaheed Zulfikar Ali Bhutto Institute of Science and Technology (SZABIST), Larkana**

## 📄 Documentation

- Project Proposal
- Research Proposal
- Software Requirements Specification (SRS)
- Software Design Specification (SDS)

## 📞 Contact

**Sanjay Kumar Wishwani:** sanjay1200x@gmail.com

## 📝 License

This project is for educational purposes as part of the Final Year Project at SZABIST Larkana.

---
**© 2026 University Point Locator | SZABIST Larkana | Final Year Project**
