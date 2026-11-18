import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../theme/app_theme.dart';
import '../theme/app_widgets.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'camera_screen.dart';
import 'alerts_screen.dart';
import 'connect_screen.dart';
import '../services/offline_place_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  // The camera starts the first time its tab is opened (so the camera
  // hardware never starts before the user asks for it) and then stays alive.
  bool _cameraOpened = false;
  String currentLocation = "Tap to get location";

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool isListening = false;

  final OfflinePlaceService _placeService = OfflinePlaceService();
  bool _placesLoaded = false;

  // Key to reach the AlertsScreen state and reload it when its tab opens.
  final GlobalKey<AlertsScreenState> _alertsKey =
      GlobalKey<AlertsScreenState>();

  // Built fresh in build() so HomeContent rebuilds when state changes
  // (e.g. currentLocation updating). Do NOT cache as a const field.

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
    if (!mounted) return;
    setState(() => currentLocation = "Getting location...");

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
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (!mounted) return;
      setState(() => currentLocation = "Location permission denied");
      return;
    }

    try {
      const settings = LocationSettings(accuracy: LocationAccuracy.high);
      final position =
          await Geolocator.getCurrentPosition(locationSettings: settings);
      if (!mounted) return;
      setState(() => currentLocation =
          _formatLocation(position.latitude, position.longitude));
    } catch (e) {
      if (!mounted) return;
      setState(() => currentLocation = "Could not get location. Try again.");
    }
  }

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text("Log out", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to log out?",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel",
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Log out",
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
          } else if (command.contains("alerts") ||
              command.contains("history")) {
            changeTab(3);
            _showMessage("Opening alert history");
          } else if (command.contains("connect") ||
              command.contains("glasses")) {
            changeTab(4);
            _showMessage("Opening device connection");
          } else if (command.contains("home")) {
            changeTab(0);
            _showMessage("Going home");
          } else {
            _showMessage("Say Navigation, Camera, Alerts, or Connect");
          }
          setState(() => isListening = false);
        },
        listenFor: const Duration(seconds: 3),
      );
      setState(() => isListening = true);
    } else {
      _showMessage("Speech recognition not available");
    }
  }

  void changeTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 2) _cameraOpened = true;
    });
    // Reload alerts each time the Alerts tab (index 3) is opened,
    // so newly-saved alerts from the camera appear immediately.
    if (index == 3) {
      _alertsKey.currentState?.reload();
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Navigation and the camera are separate pages, but both stay alive in
    // this IndexedStack: route directions keep being spoken while the camera
    // page is open, and the camera keeps watching for obstacles while the
    // map page is open. (Their voices share one speaker, see SpeechHub.)
    final screens = [
      HomeContent(
        currentLocation: currentLocation,
        isListening: isListening,
      ),
      const MapScreen(),
      _cameraOpened ? const CameraScreen() : const SizedBox.shrink(),
      AlertsScreen(key: _alertsKey),
      const ConnectScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home_rounded, "Home", 0),
              _navItem(Icons.navigation_rounded, "Navigate", 1),
              _navItem(Icons.camera_alt_rounded, "Camera", 2),
              _navItem(Icons.notifications_rounded, "Alerts", 3),
              _navItem(Icons.wifi_rounded, "Connect", 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => changeTab(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primary : AppColors.textMuted,
              size: selected ? 26 : 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textMuted,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Home tab content ----------------

class HomeContent extends StatelessWidget {
  final String currentLocation;
  final bool isListening;

  const HomeContent({
    super.key,
    required this.currentLocation,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Welcome to", style: AppText.bodySecondary),
                    Text("EYRIS", style: AppText.display),
                  ],
                ),
                IconButton(
                  onPressed: () => homeState?.logout(),
                  icon: const Icon(Icons.logout_rounded,
                      color: AppColors.textSecondary),
                  tooltip: "Log out",
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            const Center(child: EyrisLogo(size: 150, emblemOnly: true)),
            const SizedBox(height: AppSpacing.sm),
            const Center(
              child: Text("AI Navigation Assistant",
                  style: AppText.bodySecondary),
            ),
            const SizedBox(height: AppSpacing.xl),

            AppCard(
              onTap: () => homeState?.getLocation(),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: AppDecorations.pill(AppColors.primary),
                    child: const Icon(Icons.location_on_rounded,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Current Location", style: AppText.label),
                        const SizedBox(height: 4),
                        Text(
                          currentLocation,
                          style: AppText.body,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.refresh_rounded,
                      color: AppColors.textMuted, size: 20),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            AppPrimaryButton(
              label: "Start Navigation",
              icon: Icons.navigation_rounded,
              onPressed: () => homeState?.changeTab(1),
            ),
            const SizedBox(height: AppSpacing.md),

            AppSecondaryButton(
              label: isListening ? "Listening..." : "Voice Command",
              icon: isListening
                  ? Icons.mic_rounded
                  : Icons.mic_none_rounded,
              color: AppColors.accent,
              onPressed: () => homeState?.startVoiceCommand(),
            ),
            const SizedBox(height: AppSpacing.xl),

            const AppSectionHeader(title: "Quick Access"),
            const SizedBox(height: AppSpacing.sm),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 2.1,
              children: [
                _quickTile(homeState, Icons.camera_alt_rounded, "Camera",
                    AppColors.info, 2),
                _quickTile(homeState, Icons.notifications_rounded, "Alerts",
                    AppColors.warning, 3),
                _quickTile(homeState, Icons.wifi_rounded, "Connect",
                    AppColors.accent, 4),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _quickTile(HomeScreenState? state, IconData icon, String label,
      Color color, int tabIndex) {
    return AppCard(
      onTap: () => state?.changeTab(tabIndex),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: AppDecorations.pill(color),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppText.subheading,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
