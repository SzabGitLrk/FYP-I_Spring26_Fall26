import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GeofenceScreen extends StatefulWidget {
  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final Color mainColor = const Color(0xFF395058);
  final Color bgColor = const Color(0xFFF6F4F1);

  final MapController mapController = MapController();

  LatLng? currentLocation;
  LatLng? safeZoneCenter;

  double radius = 500;
  bool isInside = true;

  StreamSubscription<Position>? positionStream;

  //  AUDIO PLAYER
  final AudioPlayer player = AudioPlayer();
  bool alarmPlaying = false;

  //  OFFLINE MAP STORE
  final store = FMTCStore('zaviraStore');

  //  FIX FOR AUTO RECENTER
  bool firstCenterDone = false;

  @override
  void initState() {
    super.initState();

    //  CACHE STORE CREATE
    setupStore();

    initLocation();
    loadGeofence();
  }

  // OFFLINE CACHE STORE
  Future<void> setupStore() async {
    await store.manage.create();
  }

  // ---------------- LOCATION ----------------
  Future<void> initLocation() async {
    LocationPermission permission =
    await Geolocator.requestPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    currentLocation = LatLng(pos.latitude, pos.longitude);

    setState(() {});

    // ONLY FIRST TIME CENTER
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!firstCenterDone && currentLocation != null) {
        mapController.move(currentLocation!, 16);
        firstCenterDone = true;
      }
    });

    startTracking();
  }

  void startTracking() {
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position pos) {
      currentLocation = LatLng(pos.latitude, pos.longitude);

      checkGeofence();

      setState(() {});
    });
  }

  // SAFE ZONE
  void setSafeZone() {
    if (currentLocation == null) return;

    setState(() {
      safeZoneCenter = currentLocation;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Safe Zone Created")),
    );
  }

  // SAVE
  Future<void> saveGeofence() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    if (safeZoneCenter == null) return;

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("geofence")
        .doc("settings")
        .set({
      "lat": safeZoneCenter!.latitude,
      "lng": safeZoneCenter!.longitude,
      "radius": radius,
      "active": true,
    });
  }

  // LOAD
  Future<void> loadGeofence() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    var doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("geofence")
        .doc("settings")
        .get();

    if (doc.exists) {
      setState(() {
        safeZoneCenter = LatLng(doc["lat"], doc["lng"]);
        radius = (doc["radius"] ?? 500).toDouble();
      });
    }
  }

  // DELETE
  Future<void> deleteGeofence() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("geofence")
        .doc("settings")
        .delete();

    setState(() {
      safeZoneCenter = null;
      isInside = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Safe Zone Deleted")),
    );
  }

  //  GEOFENCE CHECK
  void checkGeofence() async {
    if (safeZoneCenter == null || currentLocation == null) return;

    double distance = Geolocator.distanceBetween(
      safeZoneCenter!.latitude,
      safeZoneCenter!.longitude,
      currentLocation!.latitude,
      currentLocation!.longitude,
    );

    bool inside = distance <= radius;

    if (inside != isInside) {
      isInside = inside;

      if (!inside) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text("🚨 Outside Safe Zone"),
          ),
        );

        // PLAY ALARM
        if (!alarmPlaying) {
          alarmPlaying = true;
          await player.play(AssetSource('alarm.mp3'));
        }

      } else {
        alarmPlaying = false;
        await player.stop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Back in Safe Zone"),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    positionStream?.cancel();
    player.dispose();
    super.dispose();
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: mainColor,
        centerTitle: true,
        title: const Text("Geofence Safety"),
      ),

      body: currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [

          // MAP
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(15),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: currentLocation!,
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                    "https://a.tile.openstreetmap.org/{z}/{x}/{y}.png",

                    userAgentPackageName:
                    "com.example.zavira",

                    // OFFLINE CACHE
                    tileProvider: store.getTileProvider(
                      settings: FMTCTileProviderSettings(
                        behavior: CacheBehavior.cacheFirst,
                      ),
                    ),

                    maxNativeZoom: 19,
                  ),

                  if (safeZoneCenter != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: safeZoneCenter!,
                          radius: radius,
                          useRadiusInMeter: true,
                          color: Colors.green.withOpacity(0.2),
                          borderColor: Colors.green,
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),

                  MarkerLayer(
                    markers: [
                      Marker(
                        point: currentLocation!,
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.location_on,
                          size: 45,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // UI CARD
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 15),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isInside
                        ? Colors.green.withOpacity(0.15)
                        : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isInside ? Icons.shield : Icons.warning,
                        color: isInside ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isInside
                            ? "Inside Safe Zone"
                            : "Outside Safe Zone",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isInside ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                Slider(
                  value: radius,
                  min: 10,
                  max: 2000,
                  divisions: 199,
                  activeColor: mainColor,
                  label: "${radius.toInt()}m",
                  onChanged: (value) {
                    setState(() {
                      radius = value;
                    });
                  },
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () {
                      setSafeZone();
                      saveGeofence();
                    },
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text("Set Safe Zone"),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: deleteGeofence,
                    icon: const Icon(Icons.delete),
                    label: const Text("Delete Safe Zone"),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),
        ],
      ),
    );
  }
}