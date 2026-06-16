import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';

final AudioPlayer player = AudioPlayer();
bool isAlarmPlaying = false;

Future<void> sendSOS() async {
  try {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    // GET LOCATION
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    double lat = pos.latitude;
    double lng = pos.longitude;

    String osmLink =
        "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng";

    //  GET CONTACTS
    final snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("contacts")
        .get();

    if (snapshot.docs.isEmpty) {
      print("No contacts found");
      return;
    }

    List<String> names = [];

    for (var doc in snapshot.docs) {
      String phone = doc["phone"].toString();
      String name = doc["name"].toString();

      phone = phone.replaceAll(RegExp(r'[^0-9+]'), '');

      if (phone.startsWith('0')) {
        phone = phone.replaceFirst('0', '92');
      }

      names.add(name);

      String message =
          "🚨 EMERGENCY ALERT!\n\n"
          "📍 Location:\n$osmLink\n\n"
          "Please help immediately!";

      final smsUri = Uri.parse(
        "sms:$phone?body=${Uri.encodeComponent(message)}",
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      }
    }

    //  SAVE ALERT HISTORY
    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("alerts")
        .add({
      "type": "SOS",
      "message": "Emergency SOS Sent",
      "location": osmLink,
      "receiverNames": names,
      "time": Timestamp.now(),
    });

    //  PLAY ALARM (IMPORTANT PART)
    if (!isAlarmPlaying) {
      isAlarmPlaying = true;

      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('alarm.mp3'));
    }

    print("SOS Sent Successfully");
  } catch (e) {
    print("SOS Error: $e");
  }
}