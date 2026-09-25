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
import 'package:university_point_locator/services/notification_service.dart';

class MapScreen extends StatefulWidget {
  final RouteModel route;
  final List<PickupPoint> pickupPoints;

  const MapScreen({super.key, required this.route, required this.pickupPoints});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final SupabaseService _service = SupabaseService();

  /// Programmatic access to the map. Unlike Google Maps there is no
  /// `onMapCreated` callback, so the controller is created up-front and passed
  /// into [FlutterMap].
  final MapController _mapController = MapController();

  /// flutter_map throws if the controller is used before the widget has
  /// rendered at least once. [MapOptions.onMapReady] sets this flag, and every
  /// camera call is gated on it.
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
  String _etaInfo = '';

  final LatLng _larkanaCenter = const LatLng(27.5580, 68.2120);

  @override
  void initState() {
    super.initState();
    _requestLocationPermissions();
    _setupPickupMarkers();
    _setupRoutePolyline();
    _loadBusData();
    _subscribeToBusLocations();
    _setupNotificationHandler();
  }

  @override
  void dispose() {
    _busSubscription?.cancel();
    // FlutterMap is our child, so it has already disposed itself by the time
    // this runs. We own the controller, so we must dispose it ourselves.
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  void _setupNotificationHandler() {
    NotificationService().onNotificationOpened = (data) {
      final stopId = data['stop_id'];
      if (stopId != null) {
        final stop = widget.pickupPoints
            .where((p) => p.id == stopId)
            .firstOrNull;
        if (stop != null) {
          _centerOnStop(stop);
        }
      }
    };
  }

  void _setupPickupMarkers() {
    setState(() {
      for (var i = 0; i < widget.pickupPoints.length; i++) {
        final point = widget.pickupPoints[i];

        // Marker colour by stop position (mirrors the old Google hue values:
        // green = first, red = last, blue = middle).
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
            // flutter_map markers have no InfoWindow; tapping opens the same
            // detail sheet the old onTap did.
            child: GestureDetector(
              onTap: () => _showStopDetails(point),
              child: Tooltip(
                message: point.pointName,
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
          // Equivalent to Google's [dash(20), gap(10)]: alternating
          // dash/gap segment lengths in logical pixels. Not `const` because
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
      _updateETAInfo();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _subscribeToBusLocations() {
    _busSubscription = _service.subscribeToBusLocations(widget.route.id).listen(
      (locations) {
        if (mounted) {
          final routeBusIds = _buses.map((b) => b.id).toSet();
          setState(() {
            _busLocations = routeBusIds.isEmpty
                ? locations
                : locations
                      .where((loc) => routeBusIds.contains(loc.busId))
                      .toList();
          });
          _updateBusMarkers();
          _updateETAInfo();
          _checkNotifications();
        }
      },
    );
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
        final Color markerColor =
            loc.speed > 2 ? Colors.cyan : Colors.deepPurple;

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
                    'Speed: ${loc.speed.toStringAsFixed(0)} km/h • '
                    'Next stop: ${_getNextStopName(loc.nextStopIndex)}',
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

  void _updateETAInfo() {
    if (_busLocations.isEmpty || widget.pickupPoints.isEmpty) {
      _etaInfo = '';
      return;
    }

    // Get closest bus to first stop
    final firstStop = widget.pickupPoints[0];
    final closestBus = _busLocations.reduce(
      (a, b) =>
          a.distanceTo(firstStop.latitude, firstStop.longitude) <
              b.distanceTo(firstStop.latitude, firstStop.longitude)
          ? a
          : b,
    );

    final eta = closestBus.estimatedTimeTo(
      firstStop.latitude,
      firstStop.longitude,
    );

    if (eta != null) {
      _etaInfo = 'First bus arrives at ${firstStop.pointName} in $eta min';
    } else {
      _etaInfo = 'Tracking ${_busLocations.length} buses';
    }
  }

  String _getNextStopName(int nextStopIndex) {
    if (nextStopIndex <= 0 || nextStopIndex > widget.pickupPoints.length) {
      return 'Unknown';
    }
    return widget.pickupPoints[nextStopIndex - 1].pointName;
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
    NotificationService().showBusArrivalNotification(
      stopName: point.pointName,
      etaMinutes: eta,
      stopId: point.id,
      routeId: widget.route.id,
    );
  }

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
              // 🔴 FIX: Add constraints to prevent overflow
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                // 🔴 FIX: Make content scrollable
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

                    // Landmark
                    if (point.landmark != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.place, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            point.landmark!,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
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
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.blue,
                                ),
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
                              'Distance: ${closestBus.distanceTo(point.latitude, point.longitude).toStringAsFixed(2)} km',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // NOTIFY ME BUTTON
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (!isNotifying) {
                          await _service.subscribeToStopNotifications(
                            point.id,
                            widget.route.id,
                          );
                        } else {
                          await _service.unsubscribeFromStopNotifications(
                            point.id,
                          );
                        }

                        if (!mounted) return;
                        setState(() {
                          _notificationsEnabled[point.id] = !isNotifying;
                        });
                        setSheetState(() {});

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isNotifying
                                  ? '🔕 Notifications turned off'
                                  : '🔔 You\'ll be notified when bus approaches',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                        backgroundColor: isNotifying
                            ? Colors.green
                            : Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _getDirections(point);
                            },
                            icon: const Icon(Icons.directions),
                            label: const Text('Directions'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _centerOnStop(point);
                            },
                            icon: const Icon(Icons.center_focus_strong),
                            label: const Text('Center Map'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
          content: SingleChildScrollView(
            // 🔴 FIX: Make dialog content scrollable
            child: Column(
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
                _buildInfoRow(
                  Icons.flag,
                  'Next stop: ${_getNextStopName(location.nextStopIndex)}',
                ),
              ],
            ),
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

  void _getDirections(PickupPoint point) {
    // Open Google Maps for directions
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${point.latitude},${point.longitude}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening directions to ${point.pointName}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // In a real app, you'd use url_launcher to open the URL
    print('Directions URL: $url');
  }

  void _centerOnStop(PickupPoint point) {
    if (!_mapReady) return;
    _mapController.move(LatLng(point.latitude, point.longitude), 16);
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
          // Show stops list
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showStopsList,
            tooltip: 'Show all stops',
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
                        : _larkanaCenter,
                    initialZoom: 13,
                    // Enables _mapReady. The controller throws if used before
                    // the map has rendered at least once.
                    onMapReady: () {
                      if (mounted) {
                        setState(() => _mapReady = true);
                      }
                    },
                  ),
                  children: [
                    // OpenStreetMap: no API key, no billing account. OSM's tile
                    // usage policy requires an identifying User-Agent and
                    // visible attribution, both provided below.
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
                            color: _busLocations.any((b) => b.speed > 2)
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

                // ETA info card
                if (_etaInfo.isNotEmpty)
                  Positioned(
                    bottom: 20,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.access_time,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Live Tracking',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    _etaInfo,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // SOS FAB
                Positioned(
                  bottom: 20,
                  right: 16,
                  child: FloatingActionButton.extended(
                    onPressed: _triggerSOS,
                    icon: const Icon(Icons.sos, size: 24),
                    label: const Text('SOS'),
                    backgroundColor: Colors.red,
                    elevation: 6,
                  ),
                ),

                // Legend
                Positioned(
                  bottom: 100,
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

  void _showStopsList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 🔴 FIX: Add this
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'All Stops',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                // 🔴 FIX: Wrap ListView with Expanded
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.pickupPoints.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final point = widget.pickupPoints[index];
                    final isFirst = index == 0;
                    final isLast = index == widget.pickupPoints.length - 1;

                    // Calculate ETA for this stop
                    final eta = _calculateETA(point);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isFirst
                            ? Colors.green[100]
                            : isLast
                            ? Colors.red[100]
                            : Colors.blue[100],
                        child: Text(
                          '${point.orderIndex}',
                          style: TextStyle(
                            color: isFirst
                                ? Colors.green
                                : isLast
                                ? Colors.red
                                : Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(point.pointName),
                      subtitle: Text(
                        point.landmark ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: eta != null
                          ? Chip(
                              label: Text('$eta min'),
                              backgroundColor: Colors.blue[50],
                              labelStyle: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        _centerOnStop(point);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
