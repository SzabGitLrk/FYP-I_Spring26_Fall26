import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';

class ContactsScreen extends StatefulWidget {
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  final Color mainColor = const Color(0xFF395058);
  final Color bgColor = const Color(0xFFF6F4F1);

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  //  ALARM SYSTEM
  final AudioPlayer player = AudioPlayer();
  bool isAlarmPlaying = false;

  //  ALARM START
  Future<void> startAlarm() async {
    if (!isAlarmPlaying) {
      isAlarmPlaying = true;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('alarm.mp3'));
    }
  }

  //ALARM STOP
  Future<void> stopAlarm() async {
    await player.stop();
    isAlarmPlaying = false;
    if (mounted) Navigator.pop(context);
  }

  //POPUP
  void showAlarmPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("🚨 Emergency Alert"),
          content: const Text("SMS sent & alarm is active"),
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

  Future<void> addContact() async {
    final name = nameController.text.trim();
    String phone = phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter name & phone")),
      );
      return;
    }

    phone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.startsWith('0')) {
      phone = phone.replaceFirst('0', '92');
    }

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("contacts")
        .add({
      "name": name,
      "phone": phone,
    });

    nameController.clear();
    phoneController.clear();
  }

  Future<Position> getLocation() async {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // SMS FUNCTION
  void smsContact(String phone, String receiverName) async {
    try {
      phone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
      if (phone.startsWith('0')) {
        phone = phone.replaceFirst('0', '92');
      }

      Position pos = await getLocation();

      double lat = pos.latitude;
      double lng = pos.longitude;

      String osmLink =
          "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng";

      String message =
          "🚨 EMERGENCY ALERT!\n\n"
          "📍 Latitude: $lat\n"
          "📍 Longitude: $lng\n\n"
          "🌍 View Location:\n$osmLink";

      Uri uri = Uri.parse(
        "sms:$phone?body=${Uri.encodeComponent(message)}",
      );

      await launchUrl(uri);

      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("alerts")
          .add({
        "type": "SMS",
        "receiverName": receiverName,
        "lat": lat,
        "lng": lng,
        "location": osmLink,
        "message": "📍 Latitude: $lat\n📍 Longitude: $lng\n\n",
        "time": Timestamp.now(),
      });

      //  ALARM START (NEW)
      await startAlarm();
      showAlarmPopup();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("SMS failed")),
      );
    }
  }

  Future<void> editContact(
      String docId,
      String currentName,
      String currentPhone,
      ) async {
    final nameCtrl = TextEditingController(text: currentName);
    final phoneCtrl = TextEditingController(text: currentPhone);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Edit Contact"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: "Phone"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection("users")
                  .doc(userId)
                  .collection("contacts")
                  .doc(docId)
                  .update({
                "name": nameCtrl.text.trim(),
                "phone": phoneCtrl.text.trim(),
              });

              Navigator.pop(dialogContext);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Future<void> deleteContact(String id) async {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("contacts")
        .doc(id)
        .delete();
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
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Emergency Contacts"),
      ),

      body: Column(
        children: [
          // FORM (UNCHANGED UI)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: "Name",
                    prefixIcon: Icon(Icons.person, color: mainColor),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: "Phone",
                    prefixIcon: Icon(Icons.phone, color: mainColor),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                    ),
                    onPressed: addContact,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Contact"),
                  ),
                ),
              ],
            ),
          ),

          // LIST
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .doc(userId)
                  .collection("contacts")
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(child: Text("No contacts added"));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index];

                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 5),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: mainColor,
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data["name"],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  data["phone"],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.call,
                                    color: Colors.green),
                                onPressed: () async {
                                  Uri uri =
                                  Uri.parse("tel:${data["phone"]}");
                                  await launchUrl(uri);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.message,
                                    color: Colors.blue),
                                onPressed: () => smsContact(
                                    data["phone"], data["name"]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Colors.orange),
                                onPressed: () => editContact(
                                  data.id,
                                  data["name"],
                                  data["phone"],
                                ),
                              ),
                              IconButton(
                                icon:
                                const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => deleteContact(data.id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}