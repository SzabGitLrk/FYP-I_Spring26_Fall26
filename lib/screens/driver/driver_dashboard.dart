import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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

  /// Ownership token for the tracking session; bumped by every start/stop so
  /// a coroutine suspended in [_startTracking] can tell it was superseded.
  int _trackSession = 0;

  /// Consecutive failed position inserts; after 5 the driver is warned that
  /// students may be seeing a frozen map.
  int _locationWriteFailures = 0;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    _checkLocationPermissions();
    // Register the foreground-service options before any trip can start
    // (post-frame so plugin channel setup cannot race the first build).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initForegroundTask());
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    // Leaving the dashboard mid-trip must not orphan the "Trip in progress"
    // notification (stopWithTask only covers swiping the app away).
    if (_isTracking) _stopForegroundService();
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

      // Fallback: if no buses assigned by name, show all active buses.
      // Never silent: the driver would otherwise start tracking a bus that
      // is not theirs and students would follow the wrong vehicle.
      var fallbackToAllBuses = false;
      if (driverBuses.isEmpty) {
        driverBuses = await _service.getAllActiveBuses();
        fallbackToAllBuses = driverBuses.isNotEmpty;
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

      if (!mounted) return;
      setState(() {
        _assignedRoutes = allRoutes;
        _isLoading = false;
      });
      if (fallbackToAllBuses) {
        _showErrorSnackBar(
          'No bus is assigned to your name - showing all active buses. '
          'Ask an administrator to assign you a bus before starting a trip.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Raw exception text stays in the log, not on the dashboard.
      debugPrint('[driver] route/bus load failed: $e');
      setState(() {
        _error =
            'Could not load your routes and buses. Check your connection and try again.';
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

  /// Registers the foreground-service options once per app launch.
  ///
  /// The service itself does no work: it raises the process priority so
  /// Android 12+ keeps delivering the GPS stream started in
  /// [_startTracking] while the screen is off. The stream stays in this
  /// isolate, so only start/stop calls around the trip are needed - no
  /// TaskHandler or port plumbing.
  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'driver_trip_tracking',
        channelName: 'Trip tracking',
        channelDescription:
            'Keeps sharing the bus position with students while a trip is '
            'running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // No TaskHandler events: the GPS stream runs in this isolate.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the `location`-typed foreground service (best-effort).
  ///
  /// Failure is logged, never surfaced as a trip error: tracking still works
  /// while the app is in the foreground - Android only throttles it once
  /// the screen goes off.
  Future<void> _startForegroundService() async {
    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 1101,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: 'Trip in progress',
        notificationText: 'Your bus position is being shared with students',
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[driver] foreground service start failed: ${result.error}');
      }
    } catch (e) {
      // Never let service bookkeeping fail a trip start.
      debugPrint('[driver] foreground service start skipped: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure) {
        debugPrint('[driver] foreground service stop failed: ${result.error}');
      }
    } catch (e) {
      // Not initialized (disposed before the first frame) or not Android.
      debugPrint('[driver] foreground service stop skipped: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
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
    // Re-entrancy guard: a second tap while the awaits below are still
    // running used to install a second GPS listener, double every position
    // insert and leave an orphaned "active" trip behind.
    if (_isTracking) return;
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

    // Ownership token: bumped by every start/stop, so this coroutine can tell
    // after each await whether it still owns the tracking session.
    final session = ++_trackSession;

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
      // ...and the previous trip's id: a start whose queries fail must not
      // leave End writing distance/time onto the old trip's row.
      _currentTripId = null;
    });

    int? tripId;
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
      tripId = tripResult?['id'] as int?;
    } catch (_) {
      // Trip recording is non-critical for live tracking - but never claim
      // success for a write that failed: without a trip row, End Trip has
      // nothing to close and the drive vanishes from trip history.
      if (mounted && session == _trackSession) {
        _showErrorSnackBar(
          'Trip recording is unavailable - live tracking is on, but this '
          'drive will not appear in trip history.',
        );
      }
    }

    // The driver ended (or restarted) tracking while this trip row was
    // still being created: if this start owns a row nobody else knows
    // about, close it now - otherwise it hangs "active" forever.
    if (!mounted || session != _trackSession) {
      if (tripId != null && tripId != _currentTripId) {
        try {
          await _service.endTrip(tripId, _totalDistance);
        } catch (_) {
          // Session was superseded; nothing more can be done here.
        }
      }
      return;
    }
    _currentTripId = tripId;

    // Stops for arrival detection and the "Next stop" readout. Best-effort:
    // if this fails the trip still tracks - it just reports no pickups and no
    // next stop (both default to 0 = unknown), which beats dropping the fix.
    try {
      _tripStops = await _service.getPickupPointsForRoute(_selectedRoute!.id);
    } catch (_) {
      _tripStops = [];
    }

    if (!mounted || session != _trackSession) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    // Defensive: whatever listener a superseded session left behind must be
    // gone before this one starts (two streams would double every insert).
    await _positionSubscription?.cancel();
    if (!mounted || session != _trackSession) return;
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
                .then<void>((_) {
                  // A good write clears the failure streak.
                  _locationWriteFailures = 0;
                })
                // Fire-and-forget by design: awaiting would stall the GPS
                // stream, and an unhandled rejection would surface as an
                // async error on every dropped fix. The next tick retries -
                // but never silently: after 5 straight failures the driver
                // is told their position is not reaching the students' maps.
                .catchError((Object e) {
                  _locationWriteFailures++;
                  debugPrint('[driver] bus location insert failed: $e');
                  if (_locationWriteFailures >= 5 && mounted) {
                    _locationWriteFailures = 0;
                    _showErrorSnackBar(
                      'Live tracking failing - students may not see your '
                      'position. Check connection and GPS.',
                    );
                  }
                });
          },
          onError: (error) {
            // Raw Geolocator internals stay in the log; the driver gets
            // actionable copy. Deliberately does NOT promise auto-resume:
            // some location errors kill the stream, and recovery is the
            // driver's stop/start, not the app's.
            debugPrint('[driver] location stream error: $error');
            if (mounted) {
              _showErrorSnackBar(
                'GPS error - check that location is enabled and that the '
                'app has permission, then restart tracking.',
              );
            }
          },
        );

    // Keep the process alive after the screen turns off, otherwise Android
    // 12+ pauses the GPS stream minutes into every real trip and students
    // see a frozen bus.
    await _startForegroundService();
    if (!mounted || session != _trackSession) {
      // Superseded while the service was starting. A newer tracking session
      // already owns the running service (its start request resolves to
      // "already started") - only tear down when nothing is tracking, or
      // the "Trip in progress" notification would outlive the trip.
      if (!_isTracking) await _stopForegroundService();
      return;
    }
    _showSuccessSnackBar('Trip started successfully!');
  }

  void _stopTracking() async {
    // Invalidate any _startTracking still awaiting inside its queries: it
    // must not install a GPS listener (or resurrect this trip) afterwards.
    ++_trackSession;
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
    await _stopForegroundService();

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

    // Only the FIRST unvisited stop can be reached. The old scan took the
    // globally nearest stop, so a service road passing stop #7 while stops
    // #1-#6 were still pending marked #7 visited and reported the wrong
    // "Next stop" to students.
    var firstUnvisited = _tripStops.length;
    for (var i = 0; i < _tripStops.length; i++) {
      if (!_countedStopIds.contains(_tripStops[i].id)) {
        firstUnvisited = i;
        break;
      }
    }
    if (firstUnvisited >= _tripStops.length) return 0; // every stop visited

    const arrivalRadiusMeters = 50.0;
    final stop = _tripStops[firstUnvisited];
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      stop.latitude,
      stop.longitude,
    );

    if (distance <= arrivalRadiusMeters &&
        _countedStopIds.add(stop.id) &&
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
                  // barrierDismissible only blocks taps - Android back still
                  // pops the dialog, which would send the follow-up
                  // `navigator.pop` below to the route underneath it.
                  builder: (_) => const PopScope(
                    canPop: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
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
                // Was a dead branch (a bare "// Navigate to profile").
                // The route is registered in main.dart and ProfileScreen
                // reads the role from the database, so it works for drivers.
                Navigator.pushNamed(context, '/profile');
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
