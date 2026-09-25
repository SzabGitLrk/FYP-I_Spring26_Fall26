import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/models/pickup_point.dart';

import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/models/bus.dart';
import 'package:university_point_locator/models/bus_location.dart';
import 'package:university_point_locator/services/supabase_service.dart';

class BusTrackingScreen extends StatefulWidget {
  final RouteModel route;
  final List<PickupPoint> pickupPoints;

  const BusTrackingScreen({
    super.key,
    required this.route,
    required this.pickupPoints,
  });

  @override
  State<BusTrackingScreen> createState() => _BusTrackingScreenState();
}

class _BusTrackingScreenState extends State<BusTrackingScreen> {
  final SupabaseService _service = SupabaseService();

  /// Created up-front and passed to [FlutterMap] (flutter_map has no
  /// `onMapCreated`).
  final MapController _mapController = MapController();

  /// Set by [MapOptions.onMapReady]. The controller throws if any camera call
  /// happens before the map has rendered at least once.
  bool _mapReady = false;

  StreamSubscription? _busSubscription;

  // flutter_map layers take Lists; Google Maps took Sets.
  final List<Marker> _pickupMarkers = [];
  final List<Marker> _busMarkers = [];
  final List<Polyline> _polylines = [];

  List<Bus> _buses = [];
  List<BusLocation> _busLocations = [];
  final Map<int, bool> _notificationsEnabled = {};

  bool _isLoading = true;
  String? _error;
  bool _followBus = true;

  @override
  void initState() {
    super.initState();
    _setupPickupMarkers();
    _setupRoutePolyline();
    _loadBusData();
    _subscribeToBusLocations();
  }

  @override
  void dispose() {
    _busSubscription?.cancel();
    // We own the controller; FlutterMap (our child) has already disposed.
    _mapController.dispose();
    super.dispose();
  }

  void _setupPickupMarkers() {
    setState(() {
      for (var i = 0; i < widget.pickupPoints.length; i++) {
        final point = widget.pickupPoints[i];

        // Marker colour by stop position (mirrors the old Google hues:
        // green = first, red = last, blue = intermediate).
        final Color markerColor;
        if (i == 0) {
          markerColor = Colors.green;
        } else if (i == widget.pickupPoints.length - 1) {
          markerColor = Colors.red;
        } else {
          markerColor = Colors.blue;
        }

        _pickupMarkers.add(
          Marker(
            point: LatLng(point.latitude, point.longitude),
            width: 36,
            height: 36,
            // No InfoWindow in flutter_map; tapping still opens the detail
            // sheet, and Tooltip preserves the hover/press label.
            child: GestureDetector(
              onTap: () {
                setState(() {});
                _showStopDetails(point);
              },
              child: Tooltip(
                message:
                    '${point.pointName} • Stop #${point.orderIndex}',
                child: Icon(Icons.location_on, color: markerColor, size: 36),
              ),
            ),
          ),
        );
      }
    });
  }

  void _setupRoutePolyline() {
    if (widget.pickupPoints.length < 2) return;

    setState(() {
      _polylines.add(
        Polyline(
          points: widget.pickupPoints
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: Colors.blue,
          strokeWidth: 4,
          // Equivalent to Google's [dash(20), gap(10)]. Not `const` because
          // StrokePattern.dashed asserts on `segments.length`, which cannot be
          // evaluated in a constant expression.
          pattern: StrokePattern.dashed(segments: const [20, 10]),
        ),
      );
    });
  }

  Future<void> _loadBusData() async {
    try {
      final buses = await _service.getBusesForRoute(widget.route.id);
      final locations = await _service.getBusLocationsForRoute(widget.route.id);

      if (!mounted) return;
      setState(() {
        _buses = buses;
        _busLocations = locations;
        _isLoading = false;

        for (var point in widget.pickupPoints) {
          _notificationsEnabled[point.id] = false;
        }
      });

      _updateBusMarkers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _subscribeToBusLocations() {
    _busSubscription = _service.subscribeToBusLocations(widget.route.id).listen((locations) {
      if (mounted) {
        final routeBusIds = _buses.map((b) => b.id).toSet();
        setState(() {
          _busLocations = routeBusIds.isEmpty
              ? locations
              : locations.where((loc) => routeBusIds.contains(loc.busId)).toList();
        });
        _updateBusMarkers();
        _checkNotifications();
      }
    });
  }

  void _updateBusMarkers() {
    setState(() {
      _busMarkers.clear();

      for (var i = 0; i < _busLocations.length; i++) {
        final loc = _busLocations[i];
        final bus = _buses.firstWhere(
          (b) => b.id == loc.busId,
          orElse: () => Bus(
            id: 0,
            routeId: 0,
            busNumber: 'Unknown',
            driverName: null,
            driverPhone: null,
            capacity: 0,
            status: 'unknown',
            createdAt: DateTime.now(),
          ),
        );

        // Custom bus marker with colour based on speed (mirrors the old Google
        // hues: azure when moving, violet when stopped).
        final Color markerColor = loc.isMoving
            ? Colors.cyan
            : Colors.deepPurple;

        _busMarkers.add(
          Marker(
            point: LatLng(loc.latitude, loc.longitude),
            width: 40,
            height: 40,
            // flutter_map has no `rotation:` field — rotate the icon ourselves.
            child: GestureDetector(
              onTap: () => _showBusDetails(bus, loc),
              child: Tooltip(
                message:
                    'Bus ${bus.busNumber}\n'
                    '${loc.statusText} • '
                    'Speed: ${loc.speed.toStringAsFixed(0)} km/h',
                child: Transform.rotate(
                  angle: loc.heading * math.pi / 180,
                  child: Icon(
                    Icons.directions_bus,
                    color: markerColor,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    });

    // Follow first bus if enabled
    if (_followBus && _busLocations.isNotEmpty && _mapReady) {
      _mapController.move(
        LatLng(_busLocations[0].latitude, _busLocations[0].longitude),
        _mapController.camera.zoom, // CameraUpdate.newLatLng kept the zoom
      );
    }
  }

  void _checkNotifications() {
    for (var loc in _busLocations) {
      for (var point in widget.pickupPoints) {
        if (_notificationsEnabled[point.id] == true) {
          final distance = loc.distanceTo(point.latitude, point.longitude);
          final eta = loc.estimatedTimeTo(point.latitude, point.longitude);

          // Notify if bus is within 0.5 km and ETA less than 5 minutes
          if (distance < 0.5 && eta != null && eta < 5) {
            _showArrivalNotification(point, eta, loc);

            // Turn off notification after showing
            setState(() {
              _notificationsEnabled[point.id] = false;
            });
          }
        }
      }
    }
  }

  void _showArrivalNotification(PickupPoint point, int eta, BusLocation loc) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🚌 Bus approaching ${point.pointName}!',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text('Arriving in approximately $eta minutes'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            _centerOnStop(point);
          },
        ),
      ),
    );
  }

  // ==========================================
  // 🆘 SOS BUTTON METHODS - NEW FEATURE
  // ==========================================

  Future<void> _triggerSOS() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sos, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('EMERGENCY SOS'),
          ],
        ),
        content: const Text(
          'Are you sure you want to send an SOS alert?\n\n'
          'Your current location will be shared with emergency contacts and admin.\n\n'
          '⚠️ Only use this in real emergencies!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _sendSOSAlert();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSOSAlert() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in to send SOS'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final userName = user.userMetadata?['name'] ?? 'Student';

      await _service.sendSOSAlert(
        userId: user.id,
        userName: userName,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.sos, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('SOS Alert Sent! Help is on the way.')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send SOS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showStopDetails(PickupPoint point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Calculate ETA using closest bus
            final eta = _calculateETA(point);
            final isNotifying = _notificationsEnabled[point.id] ?? false;

            // Find closest bus for this stop
            BusLocation? closestBus;
            if (_busLocations.isNotEmpty) {
              closestBus = _busLocations.reduce(
                (a, b) =>
                    a.distanceTo(point.latitude, point.longitude) <
                        b.distanceTo(point.latitude, point.longitude)
                    ? a
                    : b,
              );
            }

            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stop number badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Stop #${point.orderIndex}',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Stop name
                  Text(
                    point.pointName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Landmark and address
                  if (point.landmark != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_city,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          point.landmark!,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                  if (point.address != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      point.address!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ETA card
                  if (eta != null && closestBus != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.access_time, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'Bus arrives in $eta minutes',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Current distance: ${closestBus.distanceTo(point.latitude, point.longitude).toStringAsFixed(1)} km',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Notify button
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _notificationsEnabled[point.id] = !isNotifying;
                      });
                      setSheetState(() {});

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isNotifying
                                ? '🔕 Notifications turned off'
                                : '🔔 We\'ll alert you when bus is near',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          duration: const Duration(seconds: 2),
                          backgroundColor: isNotifying
                              ? Colors.grey
                              : Colors.green,
                        ),
                      );
                    },
                    icon: Icon(
                      isNotifying
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                    ),
                    label: Text(isNotifying ? 'Notify On' : 'Notify Me'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isNotifying ? Colors.green : Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // View on map button
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _centerOnStop(point);
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('View on Map'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showBusDetails(Bus bus, BusLocation location) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.directions_bus, color: Colors.blue),
              const SizedBox(width: 8),
              Text('Bus ${bus.busNumber}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                Icons.person,
                'Driver: ${bus.driverName ?? 'Not assigned'}',
              ),
              _buildInfoRow(
                Icons.speed,
                'Speed: ${location.speed.toStringAsFixed(1)} km/h',
              ),
              _buildInfoRow(Icons.info, 'Status: ${location.statusText}'),
              _buildInfoRow(
                Icons.timer,
                'Last update: ${_timeAgo(location.timestamp)}',
              ),
              if (bus.driverPhone != null)
                _buildInfoRow(Icons.phone, 'Contact: ${bus.driverPhone}'),
              const Divider(height: 24),
              _buildInfoRow(
                Icons.location_on,
                'Lat: ${location.latitude.toStringAsFixed(4)}',
              ),
              _buildInfoRow(
                Icons.location_on,
                'Lng: ${location.longitude.toStringAsFixed(4)}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _centerOnLocation(location.latitude, location.longitude);
              },
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Center Map'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 30) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds} seconds ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hours ago';
  }

  int? _calculateETA(PickupPoint point) {
    if (_busLocations.isEmpty) return null;

    // Use closest bus for ETA
    final closestBus = _busLocations.reduce(
      (a, b) =>
          a.distanceTo(point.latitude, point.longitude) <
              b.distanceTo(point.latitude, point.longitude)
          ? a
          : b,
    );

    return closestBus.estimatedTimeTo(point.latitude, point.longitude);
  }

  void _centerOnStop(PickupPoint point) {
    if (_mapReady) {
      _mapController.move(LatLng(point.latitude, point.longitude), 16);
    }
    setState(() {});
  }

  void _centerOnLocation(double lat, double lng) {
    if (!_mapReady) return;
    _mapController.move(LatLng(lat, lng), 16);
  }

  void _zoomToFitAllStops() {
    if (widget.pickupPoints.isEmpty) return;
    if (!_mapReady) return;

    double minLat = widget.pickupPoints
        .map((p) => p.latitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLat = widget.pickupPoints
        .map((p) => p.latitude)
        .reduce((a, b) => a > b ? a : b);
    double minLng = widget.pickupPoints
        .map((p) => p.longitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLng = widget.pickupPoints
        .map((p) => p.longitude)
        .reduce((a, b) => a > b ? a : b);

    // Google's newLatLngBounds(bounds, 50) -> CameraFit with 50px padding.
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.route.routeName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_buses.length} buses • ${widget.pickupPoints.length} stops',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Zoom to fit all stops
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _zoomToFitAllStops,
            tooltip: 'Show all stops',
          ),
          // Follow bus toggle
          IconButton(
            icon: Icon(_followBus ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: () {
              setState(() {
                _followBus = !_followBus;
              });
            },
            tooltip: _followBus ? 'Following bus' : 'Not following',
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBusData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.pickupPoints.isNotEmpty
                        ? LatLng(
                            widget.pickupPoints[0].latitude,
                            widget.pickupPoints[0].longitude,
                          )
                        : const LatLng(27.5580, 68.2120),
                    initialZoom: 13,
                    // Gates every camera call via _mapReady.
                    onMapReady: () {
                      if (mounted) {
                        setState(() => _mapReady = true);
                      }
                    },
                  ),
                  children: [
                    // OpenStreetMap — no API key, no billing. OSM's tile usage
                    // policy requires an identifying User-Agent plus visible
                    // attribution, both provided here.
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.university_point_locator',
                    ),
                    PolylineLayer(polylines: _polylines),
                    MarkerLayer(
                      markers: [..._pickupMarkers, ..._busMarkers],
                    ),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                  ],
                ),

                // Bus count indicator
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _busLocations.any((b) => b.isMoving)
                                ? Colors.green
                                : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_busLocations.length} active',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                // Legend
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLegendItem('First stop', Colors.green),
                        _buildLegendItem('Intermediate', Colors.blue),
                        _buildLegendItem('Last stop', Colors.red),
                        _buildLegendItem('Moving bus', Colors.cyan),
                        _buildLegendItem('Stopped bus', Colors.purple),
                      ],
                    ),
                  ),
                ),

                // 🆘 SOS FLOATING ACTION BUTTON
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.extended(
                    onPressed: _triggerSOS,
                    icon: const Icon(Icons.sos, size: 28),
                    label: const Text('SOS', style: TextStyle(fontSize: 16)),
                    backgroundColor: Colors.red,
                    elevation: 6,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
