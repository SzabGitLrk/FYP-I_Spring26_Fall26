import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'home_screen.dart';

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  final Battery _battery = Battery();

  // Phone battery data (mutable)
  int _phoneBattery = 0;
  BatteryState _phoneState = BatteryState.unknown;

  // Glasses battery data (placeholder, will be updated via BLE/WiFi)
  // ignore: prefer_final_fields
  int _glassesBattery = 0;
  // ignore: prefer_final_fields
  bool _glassesConnected = true;

  // Estimated times (placeholders)
  // ignore: prefer_final_fields
  String _phoneEstimate = "4h 30m";
  // ignore: prefer_final_fields
  String _glassesEstimate = "2h 15m";

  @override
  void initState() {
    super.initState();
    _loadPhoneBattery();
    _listenPhoneBatteryChanges();
  }

  Future<void> _loadPhoneBattery() async {
    final level = await _battery.batteryLevel;
    final state = await _battery.batteryState;
    if (!mounted) return;
    setState(() {
      _phoneBattery = level;
      _phoneState = state;
    });
  }

  void _listenPhoneBatteryChanges() {
    _battery.onBatteryStateChanged.listen((state) {
      if (mounted) setState(() => _phoneState = state);
    });
  }

  String _getStatusText(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
        return "Charging";
      case BatteryState.discharging:
        return "Active";
      case BatteryState.full:
        return "Full";
      default:
        return "Unknown";
    }
  }

  /// This screen is embedded as a tab inside HomeScreen, so Navigator.pop
  /// has nothing to pop. Instead, find the HomeScreen state and switch back
  /// to tab 0 (Home).
  void _goBackToHome() {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    if (homeState != null) {
      homeState.changeTab(0);
    } else {
      // Fallback: try a normal pop if this screen was ever pushed standalone
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        title: const Text("Battery Status"),
        backgroundColor: const Color(0xFF0A0F1E),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _goBackToHome,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Smart Glasses Card
            _buildBatteryCard(
              title: "Smart Glasses",
              device: "ESP32-CAM Device",
              batteryLevel: _glassesBattery,
              estimatedTime: _glassesEstimate,
              status: _glassesConnected ? "Inactive" : "Disconnected",
              isGlasses: true,
            ),
            const SizedBox(height: 20),

            // Smartphone Card
            _buildBatteryCard(
              title: "Smartphone",
              device: "Android Device",
              batteryLevel: _phoneBattery,
              estimatedTime: _phoneEstimate,
              status: _getStatusText(_phoneState),
              isGlasses: false,
            ),

            // Bottom safe-area padding so last card never touches the nav bar
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryCard({
    required String title,
    required String device,
    required int batteryLevel,
    required String estimatedTime,
    required String status,
    required bool isGlasses,
  }) {
    final batteryColor = batteryLevel > 50
        ? Colors.green
        : (batteryLevel > 20 ? Colors.orange : Colors.red);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                isGlasses ? Icons.wifi : Icons.phone_android,
                color: Colors.blue,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Battery level pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: batteryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$batteryLevel%",
                  style: TextStyle(
                    color: batteryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Device name
          Text(
            device,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 12),

          // Large percentage
          Row(
            children: [
              Text(
                "$batteryLevel%",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.battery_full, color: batteryColor, size: 32),
            ],
          ),
          const SizedBox(height: 16),

          // Estimated time
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.grey, size: 18),
              const SizedBox(width: 8),
              const Text(
                "Estimated Time",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const Spacer(),
              Text(
                estimatedTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status
          Row(
            children: [
              Icon(
                isGlasses ? Icons.wifi_off : Icons.power_settings_new,
                color: Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                "Status",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: status == "Charging"
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: status == "Charging" ? Colors.green : Colors.blue,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}