import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'tracking.dart';

class AlertHistoryScreen extends StatelessWidget {
  final Color mainColor = const Color(0xFF395058);
  final Color bgColor = const Color(0xFFF6F4F1);

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: mainColor,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: const Text("Alert History"),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("alerts")
            .orderBy("time", descending: true)
            .snapshots(),

        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No alerts yet",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var doc = docs[index];
              var data = doc.data() as Map<String, dynamic>;

              DateTime time =
              (data["time"] as Timestamp).toDate();

              String formattedTime =
              DateFormat("dd MMM yyyy, hh:mm a").format(time);

              // SAFE receiverName
              String receiverName =
              data.containsKey("receiverName")
                  ? data["receiverName"].toString()
                  : "All_Contacts";

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // HEADER
                    Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.red),
                        const SizedBox(width: 8),

                        const Expanded(
                          child: Text(
                            "Emergency Alert",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),

                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection("users")
                                .doc(userId)
                                .collection("alerts")
                                .doc(doc.id)
                                .delete();

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Alert deleted")),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // RECEIVER NAME
                    Text(
                      "Sent to: $receiverName",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // MESSAGE
                    Text(
                      data["message"] ?? "",
                      style: const TextStyle(fontSize: 14),
                    ),

                    const SizedBox(height: 10),

                    // VIEW LOCATION (FIXED)
                    if (data["location"] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "View Location:",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 5),

                          GestureDetector(
                            onTap: () {
                              try {
                                String link = data["location"];
                                final uri = Uri.parse(link);

                                double lat = double.parse(
                                    uri.queryParameters["mlat"]!);
                                double lng = double.parse(
                                    uri.queryParameters["mlon"]!);

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TrackingScreen(
                                      lat: lat,
                                      lng: lng,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Location parsing failed"),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              data["location"],
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 10),

                    Text(
                      formattedTime,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}