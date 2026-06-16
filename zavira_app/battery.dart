import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';

class BatteryScreen extends StatefulWidget {
  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  final Battery _battery = Battery();

  int level = 0;
  BatteryState? state;

  Timer? timer;

  @override
  void initState() {
    super.initState();
    initBattery();

    timer = Timer.periodic(Duration(seconds: 5), (_) {
      updateBattery();
    });
  }

  void initBattery() {
    updateBattery();

    _battery.onBatteryStateChanged.listen((BatteryState s) {
      setState(() => state = s);
    });
  }

  Future<void> updateBattery() async {
    final l = await _battery.batteryLevel;
    setState(() => level = l);
  }

  String get health {
    if (level > 80) return "Excellent";
    if (level > 50) return "Good";
    if (level > 20) return "Fair";
    return "Poor";
  }

  String get estimate {
    if (level > 80) return "5–7 hrs";
    if (level > 50) return "3–5 hrs";
    if (level > 20) return "1–3 hrs";
    return "Critical";
  }

  Color get batteryColor {
    if (level > 60) return Colors.green;
    if (level > 25) return Colors.orange;
    return Colors.red;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6F4F1),

      appBar: AppBar(
        title: Text("Battery Monitor"),
        centerTitle: true,
        backgroundColor: Color(0xFF395058),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            SizedBox(height: 20),

            // MAIN CARD
            Container(
              padding: EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                  )
                ],
              ),
              child: Column(
                children: [

                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 140,
                        width: 140,
                        child: CircularProgressIndicator(
                          value: level / 100,
                          strokeWidth: 10,
                          color: batteryColor,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),

                      Column(
                        children: [
                          Icon(
                            state == BatteryState.charging
                                ? Icons.battery_charging_full
                                : Icons.battery_full,
                            size: 40,
                            color: batteryColor,
                          ),
                          SizedBox(height: 5),
                          Text(
                            "$level%",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  SizedBox(height: 15),

                  Text(
                    state == BatteryState.charging
                        ? "⚡ Charging"
                        : "Not Charging",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // INFO CARDS
            Row(
              children: [
                Expanded(
                  child: _card(
                    "Health",
                    health,
                    Icons.health_and_safety,
                    Colors.blue,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _card(
                    "Usage",
                    estimate,
                    Icons.timer,
                    Colors.purple,
                  ),
                ),
              ],
            ),

            SizedBox(height: 20),

            // ⚠ WARNING CARD
            if (level <= 20)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Battery is low! Please charge your device.",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}