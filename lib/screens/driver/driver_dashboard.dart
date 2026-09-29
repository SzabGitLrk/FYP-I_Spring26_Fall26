import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/services/supabase_service.dart';
import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/models/bus.dart';
import 'package:university_point_locator/models/pickup_point.dart';
import 'package:geolocator/geolocator.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final SupabaseService _service = SupabaseService();
  final user = Supabase.instance.client.auth.currentUser;

  List<RouteModel> _assignedRoutes = [];
  List<Bus> _availableBuses = [];
  bool _isTracking = false;
  Position? _currentPosition;
  RouteModel? _selectedRoute;
  bool _isLoading = true;
  String? _error;
  StreamSubscription<Position>? _positionSubscription;

  // Stats tracking
  DateTime? _tripStartTime;
  double _totalDistance = 0.0;
  int _pickupCount = 0;
  Position? _lastPosition;
  int? _currentTripId;

  /// Stops of the route being driven, loaded once per trip. Feeds arrival
  /// detection (`_pickupCount`) and the `next_stop_index` students see as
  /// "Next stop" on the map.
  List<PickupPoint> _tripStops = [];

  /// Stops already visited on this trip, so each one is counted exactly once.
  final Set<int> _countedStopIds = {};

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    _checkLocationPermissions();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverData() async {
    setState(() => _isLoading = true);

    try {
      final driverName = user?.userMetadata?['name'] ?? '';

      // Load all routes
      final universities = await _service.getUniversities();
      List<RouteModel> allRoutes = [];
      for (var uni in universities) {
        final routes = await _service.getRoutesForUniversity(uni.id);
        allRoutes.addAll(routes);
      }

      // Load buses assigned to this driver by driver_name
      List<Bus> driverBuses = await _service.getBusesForDriver(driverName);

      // Fallback: if no buses assigned by name, show all active buses
      if (driverBuses.isEmpty) {
        driverBuses = await _service.getAllActiveBuses();
      }

      _availableBuses = driverBuses;

      // Pre-select route if driver has only one bus with a route
      if (_availableBuses.length == 1) {
        final busRouteId = _availableBuses.first.routeId;
        final matchingRoute = allRoutes.where((r) => r.id == busRouteId);
        if (matchingRoute.isNotEmpty) {
          _selectedRoute = matchingRoute.first;
        }
      }

      setState(() {
        _assignedRoutes = allRoutes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _startTracking() async {
    if (_selectedRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a route first'), backgroundColor: Colors.red),
      );
      return;
    }

    final routeBuses = _availableBuses
        .where((b) => b.routeId == _selectedRoute!.id)
        .toList();
    if (routeBuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bus available for this route'), backgroundColor: Colors.red),
      );
      return;
    }

    final bus = routeBuses.first;

    setState(() {
      _isTracking = true;
      _tripStartTime = DateTime.now();
      _totalDistance = 0.0;
      _pickupCount = 0;
      _lastPosition = null;
      // Drop the previous trip's last fix, otherwise the Live Tracking card
      // shows the OLD trip's coordinates until the first new fix arrives.
      _currentPosition = null;
      // ...and the previous trip's stop progress.
      _tripStops = [];
      _countedStopIds.clear();
    });

    try {
      await _service.startTrip(
        busId: bus.id,
        driverId: user?.id ?? '',
        routeId: _selectedRoute!.id,
      );
      final tripResult = await Supabase.instance.client
          .from('trips')
          .select('id')
          .eq('driver_id', user?.id ?? '')
          .eq('status', 'active')
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();
      _currentTripId = tripResult?['id'] as int?;
    } catch (_) {
      // Trip recording is non-critical
    }

    // Stops for arrival detection and the "Next stop" readout. Best-effort:
    // if this fails the trip still tracks - it just reports no pickups and no
    // next stop (both default to 0 = unknown), which beats dropping the fix.
    try {
      _tripStops = await _service.getPickupPointsForRoute(_selectedRoute!.id);
    } catch (_) {
      _tripStops = [];
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (!_isTracking) return;

            if (_lastPosition != null) {
              double distance = Geolocator.distanceBetween(
                _lastPosition!.latitude,
                _lastPosition!.longitude,
                position.latitude,
                position.longitude,
              );
              _totalDistance += distance / 1000;
            }

            setState(() {
              _currentPosition = position;
              _lastPosition = position;
            });

            final nextStopIndex = _updateStopProgress(position);

            _service
                .updateBusLocation(
                  busId: bus.id,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  // `Position.speed` is metres per second; everything reading
                  // this column - the "km/h" labels, the map's moving/stopped
                  // thresholds, `estimatedTimeTo`'s ETA maths - expects km/h,
                  // so it is converted once at the source instead of being
                  // 3.6x wrong at every consumer.
                  speed: position.speed.isFinite && position.speed > 0
                      ? position.speed * 3.6
                      : 0,
                  // Degrees clockwise from north: the same convention the bus
                  // marker's rotation uses. Unknown bearings arrive as a
                  // negative or NaN value and would point the icon sideways.
                  heading: position.heading.isFinite && position.heading > 0
                      ? position.heading
                      : 0,
                  nextStopIndex: nextStopIndex,
                )
                // Fire-and-forget by design: awaiting would stall the GPS
                // stream, and an unhandled rejection would surface as an
                // async error on every dropped fix. The next tick retries.
                .catchError((Object _) {});
          },
          onError: (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Location error: $error'), backgroundColor: Colors.red),
              );
            }
          },
        );

    _showSuccessSnackBar('Trip started successfully!');
  }

  void _stopTracking() async {
    if (_currentTripId != null) {
      try {
        await _service.endTrip(_currentTripId!, _totalDistance);
      } catch (e) {
        // Silently swallowing this lost the trip's end time and distance
        // with no trace at all — the driver was told "Trip ended!" while
        // nothing was written.
        _showErrorSnackBar('Trip ended, but saving it failed: $e');
      }
    }
    setState(() => _isTracking = false);
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _currentTripId = null;

    if (_tripStartTime != null) {
      final duration = DateTime.now().difference(_tripStartTime!);
      _showSuccessSnackBar(
        'Trip ended! Duration: ${duration.inMinutes} min, Distance: ${_totalDistance.toStringAsFixed(1)} km',
      );
    }
  }

  /// Records stop arrivals and works out which stop comes next.
  ///
  /// Returns the 1-based index of the first stop not yet reached (0 = every
  /// stop visited, or no stops loaded), which is the numbering
  /// `map_screen._getNextStopName` decodes back into a stop name.
  ///
  /// The counter used to bump on any fix with `speed < 1` - i.e. it counted
  /// red lights rather than pickups, capped at 10 - and `next_stop_index` was
  /// never sent at all, so students always saw "Next stop: Unknown".
  int _updateStopProgress(Position position) {
    if (_tripStops.isEmpty) return 0;

    const arrivalRadiusMeters = 50.0;
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _tripStops.length; i++) {
      final stop = _tripStops[i];
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    if (nearestDistance <= arrivalRadiusMeters &&
        _countedStopIds.add(_tripStops[nearestIndex].id) &&
        mounted) {
      setState(() => _pickupCount++);
    }

    for (var i = 0; i < _tripStops.length; i++) {
      if (!_countedStopIds.contains(_tripStops[i].id)) return i + 1;
    }
    return 0;
  }

  Future<void> _showLogoutDialog() async {
    return showDialog(
      context: context,
      // Named `dialogContext` instead of `context` on purpose: the State's own
      // `context` must stay visible below, because the dialog's context is
      // deactivated the moment the dialog pops and must not be used again
      // after the `await`.
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Capture stable references first — both outlive the dialog
                // and the await below, unlike the dialog's own context.
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                navigator.pop(); // Close confirm dialog

                // Show loading. Deliberately NOT awaited: this future only
                // completes when the dialog is popped, which happens below.
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                try {
                  await _service.signOut();
                } catch (e) {
                  navigator.pop(); // dismiss the loading dialog
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error logging out: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // RoleRouter rebuilds to the login screen on sign-out, but the
                // loading dialog is a *separate route* on the Navigator —
                // without this pop it would spin forever over the login screen.
                navigator.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    return '$hours:$minutes hrs';
  }

  @override
  Widget build(BuildContext context) {
    final userName = user?.userMetadata?['name'] ?? 'Driver';
    final userEmail = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // Trip History button
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.pushNamed(context, '/history');
            },
            tooltip: 'Trip History',
          ),
          // Logout button with confirmation
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                _showLogoutDialog();
              } else if (value == 'profile') {
                // Navigate to profile
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDriverData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: Colors.green[100],
                            child: Text(
                              (userName.isNotEmpty ? userName[0].toUpperCase() : 'D'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, $userName!',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userEmail,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Driver',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Route Selection
                  const Text(
                    'Select Your Route',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child:                       DropdownButtonFormField<RouteModel>(
                        initialValue: _selectedRoute,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Choose a route',
                          prefixIcon: Icon(Icons.route, color: Colors.green),
                        ),
                        isExpanded: true,
                        items: _assignedRoutes.map((route) {
                          return DropdownMenuItem(
                            value: route,
                            child: Text(
                              route.routeName,
                              style: const TextStyle(fontSize: 16),
                            ),
                          );
                        }).toList(),
                        onChanged: _isTracking
                            ? null
                            : (value) {
                                setState(() => _selectedRoute = value);
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tracking Controls
                  if (!_isTracking) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: _selectedRoute == null
                            ? null
                            : _startTracking,
                        icon: const Icon(Icons.play_arrow, size: 24),
                        label: const Text(
                          'Start Trip',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Live Tracking Card
                    Card(
                      color: Colors.green[50],
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Live Tracking Active',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            if (_currentPosition != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoChip(
                                      Icons.speed,
                                      // Position.speed is m/s; the label says
                                      // km/h, so convert it here too.
                                      '${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                                      Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildInfoChip(
                                      Icons.timer,
                                      _formatDuration(
                                        DateTime.now().difference(
                                          _tripStartTime!,
                                        ),
                                      ),
                                      Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 20),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _stopTracking,
                                icon: const Icon(Icons.stop, size: 24),
                                label: const Text(
                                  'End Trip',
                                  style: TextStyle(fontSize: 18),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Today's Stats
                  if (_isTracking) ...[
                    const Text(
                      'Today\'s Stats',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              Icons.timer,
                              _formatDuration(
                                DateTime.now().difference(_tripStartTime!),
                              ),
                              'Trip Time',
                            ),
                            _buildStatItem(
                              Icons.route,
                              '${_totalDistance.toStringAsFixed(1)} km',
                              'Distance',
                            ),
                            _buildStatItem(
                              Icons.people,
                              '$_pickupCount',
                              'Pickups',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Quick tips card
                  if (!_isTracking) ...[
                    const SizedBox(height: 20),
                    Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Select a route and tap "Start Trip" to begin tracking your bus location. Students will be able to see your real-time position.',
                                style: TextStyle(color: Colors.blue[800]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.green, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
