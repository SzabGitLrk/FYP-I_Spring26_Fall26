import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'login_screen.dart';
import 'map_screen.dart';
import 'camera_screen.dart';
import 'battery_screen.dart';
import 'alerts_screen.dart';
import 'connect_screen.dart';
import '../services/offline_place_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

// Public (no underscore) so tab screens like BatteryScreen can find this state
// via context.findAncestorStateOfType<HomeScreenState>() and call changeTab().
class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String currentLocation = "Tap to get location";

  // Voice command
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  // Used to convert GPS coords into a known place name
  final OfflinePlaceService _placeService = OfflinePlaceService();
  bool _placesLoaded = false;

  final List<Widget> _screens = [
    const HomeContent(),
    const MapScreen(),
    const CameraScreen(),
    const AlertsScreen(),
    const BatteryScreen(),
    const ConnectScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadPlacesForLookup();
  }

  Future<void> _loadPlacesForLookup() async {
    await _placeService.loadPlaces();
    if (mounted) setState(() => _placesLoaded = true);
  }

  Future<void> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => currentLocation = "Please enable GPS");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => currentLocation = "Location permission denied");
      return;
    }

    const settings = LocationSettings(accuracy: LocationAccuracy.high);
    final position =
        await Geolocator.getCurrentPosition(locationSettings: settings);
    if (!mounted) return;

    setState(() =>
        currentLocation = _formatLocation(position.latitude, position.longitude));
  }

  /// Resolves coordinates to a friendly name. Falls back to lat/lng.
  ///   - "Near <place>" if a known place is within 1 km
  ///   - "<origin_name> area" if an origin is within 50 km
  ///   - "lat, lng" as final fallback
  String _formatLocation(double lat, double lng) {
    if (!_placesLoaded) {
      return "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
    }

    OfflinePlace? closestPlace;
    double closestPlaceKm = double.infinity;
    for (final p in _placeService.allPlaces) {
      final d = _haversineKm(lat, lng, p.lat, p.lng);
      if (d < closestPlaceKm) {
        closestPlaceKm = d;
        closestPlace = p;
      }
    }
    if (closestPlace != null && closestPlaceKm <= 1.0) {
      return "Near ${closestPlace.name}";
    }

    final nearestOrigin = _placeService.nearestOrigin(lat, lng);
    if (nearestOrigin != null) {
      final d = _haversineKm(lat, lng, nearestOrigin.lat, nearestOrigin.lng);
      if (d <= 50.0) {
        return "${nearestOrigin.name} area";
      }
    }

    return "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void startVoiceCommand() async {
    bool available = await _speech.initialize();
    if (available) {
      _speech.listen(
        onResult: (result) {
          String command = result.recognizedWords.toLowerCase();

          if (command.contains("navigation") ||
              command.contains("navigate") ||
              command.contains("map")) {
            changeTab(1);
            _showMessage("Opening navigation");
          } else if (command.contains("camera")) {
            changeTab(2);
            _showMessage("Opening camera");
          } else if (command.contains("battery")) {
            changeTab(4);
            _showMessage("Opening battery status");
          } else if (command.contains("alerts") ||
              command.contains("history")) {
            changeTab(3);
            _showMessage("Opening alert history");
          } else if (command.contains("connect") ||
              command.contains("glasses")) {
            changeTab(5);
            _showMessage("Opening device connection");
          } else if (command.contains("home")) {
            changeTab(0);
            _showMessage("Going home");
          } else {
            _showMessage("Say Navigation, Camera, Battery, Alerts, or Connect");
          }
          setState(() => _isListening = false);
        },
        listenFor: const Duration(seconds: 3),
      );
      setState(() => _isListening = true);
    } else {
      _showMessage("Speech recognition not available");
    }
  }

  /// Public method so other tab screens can switch tabs.
  void changeTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF121A2F),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home, "Home", 0),
            _navItem(Icons.navigation, "Navigate", 1),
            _navItem(Icons.camera_alt, "Camera", 2),
            _navItem(Icons.notifications, "Alerts", 3),
            _navItem(Icons.battery_full, "Battery", 4),
            _navItem(Icons.wifi, "Connect", 5),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    return GestureDetector(
      onTap: () => changeTab(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _currentIndex == index ? Colors.blue : Colors.grey),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: _currentIndex == index ? Colors.blue : Colors.grey,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// Home Content with Voice Command Button
class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const CircleAvatar(
                radius: 40,
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.wifi, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 20),
              const Text(
                "EYRIS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),

              // Location Card
              GestureDetector(
                onTap: () => homeState?.getLocation(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2F),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Current Location",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              homeState?.currentLocation ??
                                  "Tap to get location",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Start Navigation Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: () => homeState?.changeTab(1),
                  child: const Text(
                    "Start Navigation",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // Voice Command Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: () => homeState?.startVoiceCommand(),
                  icon: Icon(
                    homeState?._isListening == true
                        ? Icons.mic
                        : Icons.mic_none,
                    color: Colors.white,
                  ),
                  label: Text(
                    homeState?._isListening == true
                        ? "Listening..."
                        : "Voice Command",
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}