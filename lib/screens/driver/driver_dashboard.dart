import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/services/supabase_service.dart';
import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/models/bus.dart';
import 'package:university_point_locator/models/pickup_point.dart';
import 'package:geolocator/geolocator.dart';
import 'package:university_point_locator/services/notification_service.dart';

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
  /// Last SOS sent this session - a coarse 30 s cooldown so a bouncing bus
  /// cannot stack duplicate alerts the admin must resolve one by one.
  DateTime? _lastSosAt;
  RouteModel? _selectedRoute;
  bool _isLoading = true;
  String? _error;
  StreamSubscription<Position>? _positionSubscription;

  /// The bus the driver explicitly confirmed (via the picker) this session.
  /// Never guessed from a list - see [_busForRoute].
  Bus? _selectedBus;

  /// True when no bus row carries this driver's name, so every bus shown is
  /// a pool the driver must pick from, not an assignment.
  bool _noAssignedBus = false;

  /// Guards the await on the bus-picker dialog so a second tap on
  /// "Start Trip" cannot open a second picker on top of it.
  bool _isStartingTrip = false;

  /// Periodic heartbeat that re-sends the last known fix while the GPS
  /// stream is quiet (parked bus) - see [_startLocationHeartbeat].
  Timer? _locationHeartbeatTimer;
  DateTime? _lastLocationSentAt;

  /// Last trustworthy bearing ([Position.heading] jitters while slow, which
  /// used to spin the bus icon in place).
  double _lastGoodHeading = 0;

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

  /// Subset of [_countedStopIds] that was passed WITHOUT the bus arriving
  /// (bypassed on the way to a later stop) - skipped stops are never counted
  /// as pickups.
  final Set<int> _skippedStopIds = {};

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
    _locationHeartbeatTimer?.cancel();
    // Leaving the dashboard mid-trip must not orphan the "Trip in progress"
    // notification (stopWithTask only covers swiping the app away).
    if (_isTracking) _stopForegroundService();
    // dispose() cannot await: close the trip row fire-and-forget so signing
    // out or navigating away does not leave the trip "active" forever.
    // (If End Trip already ran, `_currentTripId` is null and this is a no-op;
    // a duplicate close would be an idempotent UPDATE anyway.)
    final tripId = _currentTripId;
    if (tripId != null) {
      unawaited(
        _service.endTrip(tripId, _totalDistance).catchError((Object e) {
          debugPrint('[driver] dispose-time endTrip failed: $e');
        }),
      );
    }
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

      // No buses matched the driver's name: keep the pool of active buses so
      // the driver can still be ASKED which bus they are driving (see the
      // picker in _startTracking) - but never auto-assign one of them to a
      // trip: the bus table matches on a free-text name, and silently
      // picking `.first` here used to record the wrong bus_id and teleport
      // the students' marker onto another vehicle.
      _noAssignedBus = driverBuses.isEmpty;
      if (driverBuses.isEmpty) {
        driverBuses = await _service.getAllActiveBuses();
      }

      _availableBuses = driverBuses;

      // A stale selection must not survive a reload: if the previously
      // selected route was deleted (or this retry reloaded a changed list),
      // it would pre-fill buses and stops for a route that no longer exists.
      final previouslySelected = _selectedRoute;
      if (previouslySelected != null &&
          !allRoutes.any((r) => r.id == previouslySelected.id)) {
        debugPrint(
          '[driver] selected route ${previouslySelected.id} no longer '
          'exists - clearing selection',
        );
        _selectedRoute = null;
      }

      // Pre-select route if driver has only one bus with a route
      if (_selectedRoute == null && _availableBuses.length == 1) {
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
      // Close trips orphaned by a crash or a failed End Trip. Fire-and-
      // forget: housekeeping must never delay or fail the dashboard load,
      // and the driver's own UPDATE policy scopes it to their own rows.
      unawaited(_reapStaleTrips());
      if (_noAssignedBus) {
        _showErrorSnackBar(
          'No bus is assigned to your name - you will be asked to pick the '
          'bus you are driving. Ask an administrator to assign you a bus.',
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

  /// Closes orphaned "active" trips for the signed-in driver.
  ///
  /// A crash mid-trip, a lost connection during End Trip, or a failed trip
  /// insert used to leave the row "active" forever, which distorts trip
  /// history. Anything still active 12 hours after it started cannot be a
  /// real drive. Only the values this app writes for `trips.status` are
  /// used (`active`/`completed` - the column is plain TEXT, see
  /// supabase_final.sql), and the schema is not altered. Distance stays as
  /// it is: the real figure is unknown, so none is invented.
  Future<void> _reapStaleTrips() async {
    final driverId = user?.id;
    if (driverId == null || driverId.isEmpty) return;
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 12))
          .toIso8601String();
      final stale = await Supabase.instance.client
          .from('trips')
          .select('id, start_time')
          .eq('driver_id', driverId)
          .eq('status', 'active')
          .lt('start_time', cutoff)
          .order('start_time', ascending: true);

      for (final row in stale as List) {
        final tripId = row['id'] as int;
        await Supabase.instance.client
            .from('trips')
            .update({
              'status': 'completed',
              // Close at start: stamping "now" would fake a 12-hour drive,
              // and the real end time/distance are genuinely unknown.
              'end_time': row['start_time'] ?? cutoff,
            })
            .eq('id', tripId);
      }
      if (stale.isNotEmpty) {
        debugPrint('[driver] reaped ${stale.length} stale trip(s)');
      }
    } catch (e) {
      // Housekeeping only - never block or fail the dashboard load.
      debugPrint('[driver] stale-trip reap failed: $e');
    }
  }

  Future<void> _checkLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      debugPrint('[driver] location permission unavailable: $permission');
      // Post-frame: initState runs before the first build, and a dialog
      // raised there races the Navigator's first layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showLocationPermissionDialog(permission);
      });
    }
  }

  /// Explains WHY the driver needs location (students cannot follow a bus
  /// the app cannot locate) and, when access is permanently blocked, offers
  /// a shortcut to the app settings page. A silent failure here used to let
  /// trips run with no GPS at all while the dashboard looked normal.
  void _showLocationPermissionDialog(LocationPermission permission) {
    final permanentlyDenied = permission == LocationPermission.deniedForever;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Location permission needed'),
        content: Text(
          permanentlyDenied
              ? 'Students can only follow your bus if the app can share its '
                  'location. Location access is blocked for this app. Open '
                  'your phone Settings > Apps > University Point Locator > '
                  'Permissions > Location and allow it, then start your trip.'
              : 'Students can only follow your bus if the app can share its '
                  'location. Please allow location access when prompted - '
                  'without it, tracking will not work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
          if (permanentlyDenied)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // Fire-and-forget: opens the OS app-settings page.
                Geolocator.openAppSettings().catchError((Object e) {
                  debugPrint('[driver] openAppSettings failed: $e');
                  return false;
                });
              },
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
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

  /// The bus to drive: a previously confirmed session choice (still valid
  /// for this route), or the single bus assigned to the driver's name.
  ///
  /// `null` means the driver must be asked - the app never falls back to
  /// `.first`: with two drivers on one route, guessing wrote the wrong
  /// `bus_id` onto the trip and teleported the students' marker between
  /// vehicles.
  Bus? _busForRoute(List<Bus> routeBuses) {
    final remembered = _selectedBus;
    if (remembered != null && routeBuses.any((b) => b.id == remembered.id)) {
      return remembered;
    }
    // Auto-select only in the unambiguous, driver-owned case: exactly one
    // bus assigned to their name on this route. An unassigned pool is never
    // auto-picked, even when it happens to hold a single bus.
    if (!_noAssignedBus && routeBuses.length == 1) {
      _selectedBus = routeBuses.first;
      return _selectedBus;
    }
    return null;
  }

  /// Asks the driver which of [buses] they are actually driving.
  Future<Bus?> _askDriverToPickBus(List<Bus> buses) {
    return showDialog<Bus>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Which bus are you driving?'),
          children: [
            if (_noAssignedBus)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'No bus is assigned to you - select the bus you are driving.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ),
            for (final bus in buses)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, bus),
                child: Text(bus.busNumber),
              ),
          ],
        );
      },
    );
  }

  Future<void> _startTracking() async {
    // Re-entrancy guard: a second tap while the awaits below are still
    // running used to install a second GPS listener, double every position
    // insert and leave an orphaned "active" trip behind. [_isStartingTrip]
    // additionally covers the await on the bus-picker dialog below.
    if (_isTracking || _isStartingTrip) return;
    final route = _selectedRoute;
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a route first'), backgroundColor: Colors.red),
      );
      return;
    }

    final routeBuses = _availableBuses
        .where((b) => b.routeId == route.id)
        .toList();
    if (routeBuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No active bus is on this route yet - ask an administrator to assign one.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Resolve the bus: an existing/auto choice, otherwise an explicit pick.
    final Bus bus;
    final candidate = _busForRoute(routeBuses);
    if (candidate != null) {
      bus = candidate;
    } else {
      _isStartingTrip = true;
      Bus? picked;
      try {
        picked = await _askDriverToPickBus(routeBuses);
      } finally {
        _isStartingTrip = false;
      }
      if (!mounted || picked == null) return; // dialog dismissed - no trip
      bus = picked;
      // Remembered for the rest of this session (validated per route above).
      _selectedBus = picked;
    }

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
      _skippedStopIds.clear();
      // ...and the previous trip's bearing/send bookkeeping.
      _lastGoodHeading = 0;
      _lastLocationSentAt = null;
      // ...and the previous trip's id: a start whose queries fail must not
      // leave End writing distance/time onto the old trip's row.
      _currentTripId = null;
    });

    int? tripId;
    try {
      // The INSERT returns the id the database assigned: this is the ONLY
      // trustworthy trip identity. (Re-querying "my latest active trip"
      // afterwards could lose the race, or match an orphaned row with a
      // NULL start_time that sorts first under the DESC default - writing
      // the drive's distance onto the wrong trip.)
      tripId = await _service.startTrip(
        busId: bus.id,
        driverId: user?.id ?? '',
        routeId: route.id,
      );
    } catch (e) {
      // Raw exception stays in the log; the driver gets actionable copy.
      // Trip recording is non-critical for live tracking - but never claim
      // success for a write that failed: without a trip row, End Trip has
      // nothing to close and the drive vanishes from trip history.
      debugPrint('[driver] trip insert failed: $e');
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
        } catch (e) {
          // Session was superseded; nothing more can be done here.
          debugPrint('[driver] superseded-session endTrip failed: $e');
        }
      }
      return;
    }
    _currentTripId = tripId;

    // Stops for arrival detection and the "Next stop" readout. Best-effort:
    // if this fails the trip still tracks - it just reports no pickups and no
    // next stop (both default to 0 = unknown), which beats dropping the fix.
    try {
      _tripStops = await _service.getPickupPointsForRoute(route.id);
    } catch (_) {
      _tripStops = [];
    }

    if (!mounted || session != _trackSession) return;

    // 10 m of movement still gets its own callback; a PARKED bus gets none
    // at all, so the stationary heartbeat below keeps re-sending the last
    // fix and students don't see the marker go stale exactly when the bus
    // is waiting at a stop.
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

            _sendBusLocation(bus, position, nextStopIndex);
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

    // The stream alone goes silent while the bus is parked; the heartbeat
    // pushes the last known fix every ~20 s so the marker (and the map's
    // 2-minute freshness window) stays alive at a stop.
    _startLocationHeartbeat(bus);

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

  /// Pushes one GPS fix to the students' maps.
  ///
  /// Shared by the GPS stream callback and the stationary heartbeat so the
  /// km/h conversion, the heading rule and the failure-streak warning can
  /// never drift apart between the two paths.
  void _sendBusLocation(Bus bus, Position position, int nextStopIndex) {
    // Degrees clockwise from north: the same convention the bus marker's
    // rotation uses. `Position.heading` is only trustworthy while moving -
    // at low speed the GPS bearing jitters and the bus icon spins in place -
    // so a good bearing is captured once the bus is properly moving (>1.5
    // m/s) and the last good value is forwarded at a standstill.
    if (position.heading.isFinite &&
        position.heading >= 0 &&
        position.heading <= 360 &&
        position.speed > 1.5) {
      _lastGoodHeading = position.heading;
    }

    _lastLocationSentAt = DateTime.now();
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
          heading: _lastGoodHeading,
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
  }

  /// Re-sends the last known fix whenever the GPS stream goes quiet, so a
  /// parked bus keeps reporting "bus is here" instead of freezing a stale
  /// marker (Android delivers no callback at all below the 10 m
  /// `distanceFilter`). Started with the trip, cancelled on stop/dispose,
  /// and never inserts without an active tracking session.
  void _startLocationHeartbeat(Bus bus) {
    _locationHeartbeatTimer?.cancel();
    _locationHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) {
      if (!mounted || !_isTracking) return;
      final position = _currentPosition;
      // No fix yet - nothing honest to send.
      if (position == null) return;
      // A row that just went out is still fresh; don't double-write.
      final lastSent = _lastLocationSentAt;
      if (lastSent != null &&
          DateTime.now().difference(lastSent) < const Duration(seconds: 15)) {
        return;
      }
      _sendBusLocation(bus, position, _updateStopProgress(position));
    });
  }

  Future<void> _stopTracking() async {
    // Invalidate any _startTracking still awaiting inside its queries: it
    // must not install a GPS listener (or resurrect this trip) afterwards.
    ++_trackSession;
    _locationHeartbeatTimer?.cancel();
    _locationHeartbeatTimer = null;
    var tripSaved = false;
    if (_currentTripId != null) {
      try {
        await _service.endTrip(_currentTripId!, _totalDistance);
        tripSaved = true;
      } catch (e) {
        // Silently swallowing this lost the trip's end time and distance
        // with no trace at all — the driver was told "Trip ended!" while
        // nothing was written. Raw exception stays in the log.
        debugPrint('[driver] end trip write failed: $e');
      }
    }
    // Guarded: the await above can outlive this screen (driver navigated
    // away mid-save) - setState on a defunct State would throw.
    if (mounted) setState(() => _isTracking = false);
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _currentTripId = null;
    await _stopForegroundService();

    if (!mounted) return;
    if (!tripSaved) {
      // Honest failure instead of a fake success: without a closed trip
      // row there is no recorded duration/distance to report.
      _showErrorSnackBar(
        'Drive was not recorded - check your connection and try again.',
      );
      return;
    }
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
  ///
  /// Bypassed stops are handled too: reaching a LATER stop marks the pending
  /// ones before it as skipped (never counted as pickups) and jumps the
  /// first-unvisited marker forward, instead of freezing the whole trip on
  /// the first stop the bus never reached.
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

    // Skip-ahead: if the bus reached a LATER stop while earlier ones were
    // still pending (bypassed stop, detour, driver forgot), those stops
    // will never be reached - without this jump the readout froze at the
    // first unvisited stop ("Next stop: #2" for the rest of the trip) and
    // the pickup counter stayed at 0. Bypassed stops are marked visited-
    // but-skipped: added to [_countedStopIds] so they can never later be
    // counted as a pickup, and tracked in [_skippedStopIds] for clarity.
    for (var j = firstUnvisited + 1; j < _tripStops.length; j++) {
      final laterStop = _tripStops[j];
      final laterDistance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        laterStop.latitude,
        laterStop.longitude,
      );
      if (laterDistance > arrivalRadiusMeters) continue;
      for (var k = firstUnvisited; k < j; k++) {
        _countedStopIds.add(_tripStops[k].id);
        _skippedStopIds.add(_tripStops[k].id);
      }
      debugPrint(
        '[driver] stop ${laterStop.pointName} reached while '
        '${j - firstUnvisited} earlier stop(s) were still pending - '
        '${_skippedStopIds.length} skipped so far',
      );
      firstUnvisited = j;
      break;
    }

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

  /// Confirmation for the driver-side emergency button (parity with the
  /// student map's SOS): nothing is sent until the driver taps SEND SOS.
  void _confirmDriverSOS() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sos, color: Colors.red),
            SizedBox(width: 8),
            Text('EMERGENCY SOS'),
          ],
        ),
        content: const Text(
          'Send an SOS to the admin with this bus\'s current GPS location?\n\n'
          'Use it for a breakdown, accident or safety emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(_sendDriverSOS());
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

  /// Sends the driver's SOS: bus number + best GPS fix into `sos_alerts`,
  /// the exact table the admin dashboard subscribes to live, so a bus
  /// problem reaches dispatch without a phone call.
  Future<void> _sendDriverSOS() async {
    // Captured before the first await: the messenger is app-level and
    // outlives any route, so the snackbars below are safe after the await.
    final messenger = ScaffoldMessenger.of(context);
    final last = _lastSosAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('An SOS was just sent - the admin already has it.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Best available fix: live stream (or the heartbeat's cached fix),
    // then the OS's cached position, then one fresh reading. The stream
    // yields nothing while parked at distanceFilter 10 and before a trip
    // it has never run - relying on it alone would fail exactly when a
    // stationary bus breaks down.
    Position? position;
    try {
      position = _currentPosition ?? _lastPosition;
      position ??= await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      // Detail stays in the log; the honest fallback message is below.
      debugPrint('[driver] SOS position fetch failed: $e');
    }
    if (position == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Location is unavailable - an SOS must carry the bus position. '
            'Enable location for this app and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final account = user;
    if (account == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to send SOS'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // sos_alerts has no message column: the bus number rides along in
    // user_name so the admin sees WHICH bus has the problem, not just a
    // person and a pin.
    final name = account.userMetadata?['name'] ?? 'Driver';
    final busNumber = _selectedBus?.busNumber;
    final userName = (busNumber == null || busNumber.isEmpty)
        ? name
        : 'Bus $busNumber - $name';
    try {
      await _service.sendSOSAlert(
        userId: account.id,
        userName: userName,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _lastSosAt = DateTime.now();
      unawaited(NotificationService().showSOSNotification());
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.sos, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SOS sent - the admin has this bus\'s live location.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('[driver] SOS failed: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not send SOS. Check your connection and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                  // Raw exception stays in the log; the driver gets copy
                  // they can act on.
                  debugPrint('[driver] sign-out failed: $e');
                  navigator.pop(); // dismiss the loading dialog
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not log out. Check your connection and try again.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // RoleRouter rebuilds to the login screen on sign-out, but the
                // loading dialog is a *separate route* on the Navigator -
                // without this pop it would spin forever over the login
                // screen. popUntil(isFirst) then clears anything else the
                // signed-out session pushed (history, profile), so no
                // signed-out screen stays reachable via Back.
                navigator.pop(); // dismiss the loading dialog
                navigator.popUntil((route) => route.isFirst);
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
          // Emergency SOS - same pipeline as the student SOS (sos_alerts ->
          // the live admin dashboard), carrying the bus number and a GPS fix.
          IconButton(
            icon: const Icon(Icons.sos),
            onPressed: _confirmDriverSOS,
            tooltip: 'Send emergency SOS',
          ),
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
