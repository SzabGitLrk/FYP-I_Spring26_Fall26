//Live GPS, show movement on map,Speed, direction, accuracy show,Offline maps support
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class TrackingScreen extends StatefulWidget {
  final double? lat;
  final double? lng;

  const TrackingScreen({
    super.key,
    this.lat,
    this.lng,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  LatLng? currentLocation;

  double speed = 0.0;
  double heading = 0.0;
  double accuracy = 0.0;

  List<LatLng> path = [];

  late final MapController mapController;

  String currentAddress = "";

  final store = FMTCStore('zaviraStore');

  bool firstCenterDone = false;

  @override
  void initState() {
    super.initState();

    // 🔥 CACHE STORE CREATE
    setupStore();

    mapController = MapController();

    if (widget.lat != null && widget.lng != null) {
      currentLocation = LatLng(widget.lat!, widget.lng!);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapController.move(currentLocation!, 19);
      });

      getAddress(widget.lat!, widget.lng!);
    }

    startTracking();
  }

  // OFFLINE CACHE STORE
  Future<void> setupStore() async {
    await store.manage.create();
  }

  // ADDRESS
  Future<void> getAddress(double lat, double lng) async {
    try {
      List<Placemark> places =
      await placemarkFromCoordinates(lat, lng);

      Placemark place = places.first;

      setState(() {
        currentAddress = [
          place.thoroughfare,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.country,
        ].where((e) => e != null && e.trim().isNotEmpty).join(", ");
      });
    } catch (e) {
      debugPrint("Address Error: $e");
    }
  }

  // TRACKING
  void startTracking() async {
    bool serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) return;

    LocationPermission permission =
    await Geolocator.requestPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      if (position.accuracy > 30) return;

      LatLng newLoc =
      LatLng(position.latitude, position.longitude);

      setState(() {
        currentLocation = newLoc;

        speed = position.speed * 3.6;
        heading = position.heading;
        accuracy = position.accuracy;

        path.add(newLoc);
      });

      getAddress(position.latitude, position.longitude);

      // 🔥 ONLY FIRST TIME CENTER
      if (!firstCenterDone && currentLocation != null) {
        mapController.move(currentLocation!, 19);
        firstCenterDone = true;
      }
    });
  }

  // UI HELPERS
  Color getAccuracyColor() {
    if (accuracy <= 10) return Colors.green;
    if (accuracy <= 25) return Colors.orange;
    return Colors.red;
  }

  String getAccuracyText() {
    if (accuracy <= 10) return "High";
    if (accuracy <= 25) return "Medium";
    return "Low";
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF395058),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Tracking",
          style: TextStyle(color: Colors.white),
        ),
      ),

      body: currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: currentLocation!,
              initialZoom: 19,
              maxZoom: 22,
              minZoom: 3,
            ),
            children: [
              TileLayer(
                urlTemplate:
                "https://a.tile.openstreetmap.org/{z}/{x}/{y}.png",

                userAgentPackageName:
                'zavira_tracking_app',

                tileProvider: store.getTileProvider(
                  settings: FMTCTileProviderSettings(
                    behavior: CacheBehavior.cacheFirst,
                  ),
                ),

                maxNativeZoom: 19,
              ),

              PolylineLayer(
                polylines: [
                  Polyline(
                    points: path,
                    strokeWidth: 5,
                    color: Colors.blue,
                  ),
                ],
              ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: currentLocation!,
                    width: 80,
                    height: 80,
                    child: Transform.rotate(
                      angle: heading * pi / 180,
                      child: const Icon(
                        Icons.navigation,
                        size: 42,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          Positioned(
            top: 80,
            left: 20,
            child: infoBox(
              "Accuracy: ${accuracy.toStringAsFixed(1)}m (${getAccuracyText()})",
              getAccuracyColor(),
            ),
          ),

          Positioned(
            top: 150,
            left: 20,
            child: infoBox(
              "Lat: ${currentLocation!.latitude.toStringAsFixed(6)}\nLng: ${currentLocation!.longitude.toStringAsFixed(6)}",
              Colors.black87,
            ),
          ),

          Positioned(
            top: 230,
            left: 20,
            right: 20,
            child: infoBox(
              currentAddress.isEmpty
                  ? "Fetching address..."
                  : currentAddress,
              Colors.teal,
            ),
          ),

          Positioned(
            bottom: 40,
            left: 20,
            child: infoBox(
              "Speed: ${speed.toStringAsFixed(1)} km/h",
              Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget infoBox(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}