import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

import 'alert_history.dart';
import 'contacts.dart';
import 'geofence.dart';
import 'battery.dart';
import 'login.dart';
import 'tracking.dart';

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Color mainColor = const Color(0xFF395058);
  final Color bgColor = const Color(0xFFF6F4F1);

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  // 🔊 ALARM SYSTEM
  final AudioPlayer player = AudioPlayer();
  bool isAlarmPlaying = false;

  // 📍 LOCATION
  Future<Map<String, dynamic>> getLocationData() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    double lat = position.latitude;
    double lng = position.longitude;

    return {
      "lat": lat,
      "lng": lng,
      "link":
      "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng"
    };
  }

  // 🚨 START ALARM
  Future<void> startAlarm() async {
    if (!isAlarmPlaying) {
      isAlarmPlaying = true;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('alarm.mp3'));
    }
  }

  //  STOP ALARM
  Future<void> stopAlarm() async {
    await player.stop();
    isAlarmPlaying = false;
    if (mounted) Navigator.pop(context);
  }

  //  POPUP
  void showAlarmPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("🚨 Emergency Alarm"),
          content: const Text("Alarm is running..."),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: stopAlarm,
              child: const Text("STOP"),
            )
          ],
        );
      },
    );
  }

  //  SAVE ALERT
  Future<void> saveAlert({
    required String type,
    required String message,
    required String location,
    required List<String> receiverNames,
  }) async {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("alerts")
        .add({
      "type": type,
      "message": message,
      "location": location,
      "receiverNames": receiverNames,
      "time": Timestamp.now(),
    });
  }

  //  SOS FUNCTION (UPDATED ONLY LOGIC)
  void sendSOS(BuildContext context) async {
    try {
      var loc = await getLocationData();

      var snapshot = await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("contacts")
          .get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No emergency contacts found")),
        );
        return;
      }

      List<String> numbers = [];
      List<String> names = [];

      for (var doc in snapshot.docs) {
        String phone = doc["phone"].toString();
        String name = doc["name"].toString();

        phone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
        if (phone.startsWith('0')) {
          phone = phone.replaceFirst('0', '92');
        }

        numbers.add(phone);
        names.add(name);
      }

      String message =
          "🚨 EMERGENCY!\n\n"
          "📍 Latitude: ${loc["lat"]}\n"
          "📍 Longitude: ${loc["lng"]}\n\n"
          "🌍 ${loc["link"]}";

      Uri smsUri = Uri.parse(
        "sms:${numbers.join(",")}?body=${Uri.encodeComponent(message)}",
      );

      await launchUrl(smsUri);

      await saveAlert(
        type: "SOS",
        message:
        "📍 Latitude: ${loc["lat"]}\n📍 Longitude: ${loc["lng"]}\n",
        location: loc["link"],
        receiverNames: names,
      );

      // 🔊 ALARM START
      await startAlarm();
      showAlarmPopup();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("SOS sent")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("SOS failed")),
      );
    }
  }

  //  CALL
  void makeCall(BuildContext context) async {
    var snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("contacts")
        .get();

    if (snapshot.docs.isEmpty) return;

    String phone = snapshot.docs.first["phone"];

    await launchUrl(Uri.parse("tel:$phone"));
  }

  //  SHARE
  void shareLocation(BuildContext context) async {
    var loc = await getLocationData();

    var snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("contacts")
        .get();

    List<String> numbers =
    snapshot.docs.map((e) => e["phone"].toString()).toList();

    Uri smsUri = Uri.parse(
      "sms:${numbers.join(",")}?body=${Uri.encodeComponent(loc["link"])}",
    );

    await launchUrl(smsUri);
  }

  //  LOGOUT
  void logoutUser(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false,
    );
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: mainColor,
        title: const Text("Zavira Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logoutUser(context),
          )
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red,
        icon: const Icon(Icons.warning, color: Colors.white),
        label: const Text(
          "SOS",
          style: TextStyle(color: Colors.white),
        ),
        onPressed: () => sendSOS(context),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomButton(Icons.call, "Call", () => makeCall(context)),
            _bottomButton(Icons.message, "SMS", () => sendSOS(context)),
            _bottomButton(Icons.share, "Share", () => shareLocation(context)),
          ],
        ),
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            _deviceCard(),

            _featureCard(
              context,
              icon: Icons.location_on,
              title: "Live Tracking",
              subtitle: "Real-time GPS location",
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TrackingScreen()),
              ),
            ),

            _featureCard(
              context,
              icon: Icons.shield,
              title: "Alert History",
              subtitle: "Emergency logs",
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AlertHistoryScreen()),
              ),
            ),

            _featureCard(
              context,
              icon: Icons.battery_full,
              title: "Battery",
              subtitle: "Device status",
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BatteryScreen()),
              ),
            ),

            _featureCard(
              context,
              icon: Icons.location_city,
              title: "Geofence",
              subtitle: "Safe zones",
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GeofenceScreen()),
              ),
            ),

            _featureCard(
              context,
              icon: Icons.contacts,
              title: "Contacts",
              subtitle: "Emergency numbers",
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ContactsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          Icon(Icons.watch, color: Color(0xFF395058)),
          SizedBox(width: 10),
          Text("Device Disconnected"),
        ],
      ),
    );
  }

  Widget _featureCard(BuildContext context,
      {required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF395058),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 40),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _bottomButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: mainColor),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}