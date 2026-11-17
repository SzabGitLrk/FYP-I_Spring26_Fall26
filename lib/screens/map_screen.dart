import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:university_point_locator/utils/geo_snapping.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/models/pickup_point.dart';
import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/models/bus.dart';
import 'package:university_point_locator/models/bus_location.dart';
import 'package:university_point_locator/services/supabase_service.dart';
import 'package:university_point_locator/services/notification_service.dart';
import 'package:university_point_locator/services/route_service.dart';
import 'package:university_point_locator/services/offline_cache.dart';
import 'package:university_point_locator/services/my_stop_store.dart';
import 'package:university_point_locator/navigation/route_follower.dart';
import 'package:university_point_locator/navigation/route_step.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';

class MapScreen extends StatefulWidget {
  final RouteModel route;
  final List<PickupPoint> pickupPoints;

  /// When set, the map opens centred on this stop (the student's saved "my
  /// stop") instead of framing the whole route.
  final int? initialFocusStopId;

  const MapScreen({
    super.key,
    required this.route,
    required this.pickupPoints,
    this.initialFocusStopId,
  });

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
  /// Consecutive restarts of a closed bus feed; a healthy tick resets it.
  int _busFeedRestarts = 0;
  /// Pending restart of a closed bus feed (see [_scheduleBusFeedRestart]).
  Timer? _busFeedRestart;

  /// Live GPS fix behind the blue "you are here" dot. Stays null until the
  /// first reading lands, and forever if location permission is denied.
  Position? _myPosition;
  StreamSubscription<Position>? _myPositionSubscription;

  // flutter_map layers take Lists; Google Maps took Sets.
  final List<Marker> _pickupMarkers = [];
  final List<Marker> _busMarkers = [];
  /// Route geometry used ONLY for map-matching bus markers (see
  /// [snapToRoute] / [_updateBusMarkers]). Kept separate from [_polylines]
  /// because navigation overwrites the drawn polyline with a
  /// user-position based route that is not the bus route.
  List<LatLng> _routePoints = [];
  /// Snap radius (metres) for that map-matching: within it the fix is on
  /// the route and drawn on the road; beyond it the fix is a genuine
  /// detour or a bad reading and is shown honestly where it actually is.
  static const double _busSnapDistance = 50.0;
  /// The route polyline currently drawn over the map.
  ///
  /// Reassigned as a *fresh list* (never mutated in place): flutter_map caches
  /// its projected/simplified polyline data per list instance, so handing the
  /// layer a new list is what guarantees it re-projects and repaints with road
  /// geometry instead of keeping the straight placeholder painted.
  List<Polyline> _polylines = [];

  List<Bus> _buses = [];
  List<BusLocation> _busLocations = [];

  /// Bumped whenever [_busLocations] changes. The stop-detail and All-Stops
  /// bottom sheets are their own navigator route and never see this screen's
  /// rebuilds; listening here keeps their ETAs live while open.
  final ValueNotifier<int> _busRevision = ValueNotifier<int>(0);
  final Map<int, bool> _notificationsEnabled = {};
  /// Last "bus approaching" alert per "stopId:busId", session-scoped: one
  /// alert per bus per stop per 10 minutes instead of one per GPS tick.
  static final Map<String, DateTime> _lastArrivalAlert = {};

  /// A bus row older than this is history, not live data. Single source of
  /// truth for every freshness check on this screen (feed, poll, ETA,
  /// alerts) - the value used to be re-typed at each call site.
  static const Duration _staleAfter = Duration(minutes: 5);

  /// Newest server-stamped fix seen this session. Freshness ages rows
  /// against THIS (server clock vs server clock) instead of DateTime.now():
  /// `bus_locations.timestamp` is written by the database, so comparing it
  /// to a device clock silently broke the map whenever the two disagreed -
  /// a phone minutes ahead had `now - 2 min` drop EVERY row (and the same
  /// cutoff filtered the realtime events out, so nothing could recover),
  /// while a phone minutes behind kept dead buses drawn live. Monotonic: a
  /// bad batch cannot rewind it.
  DateTime? _serverFixHorizon;

  /// Re-ages rows and polls over REST every 30 s: the realtime feed only
  /// emits on new inserts, so without a clock nothing ages out when quiet.
  Timer? _refreshTimer;

  /// Location-help dialog shown at most once per session.
  bool _locationHelpShown = false;

  /// Which distanceFilter the position stream currently runs with (walking
  /// 10 m normally, 0 while navigating - see _startMyLocationStream).
  int _positionFilter = 10;

  /// Throttle for fixes while navigating (the stream runs unfiltered during
  /// guidance, so raw fixes arrive about once a second).
  DateTime _lastNavFix = DateTime.fromMillisecondsSinceEpoch(0);

  /// 0 = maneuver far, 1 = within 80 m, 2 = within 25 m. Steps are spoken
  /// on entry AND at each bucket crossing, instead of exactly once.
  int _lastSpokenBucket = 0;

  /// Via-stop names this guidance passes, captured when the route is
  /// adopted (leg k ends at via k) - used to relabel intermediate
  /// "arrive" steps as "Passing `<stop>`".
  List<String> _navViaNames = const [];

  bool _isLoading = true;
  String? _error;
  /// When set, the map is showing the last cached bus fixes (data connection
  /// is down) and this holds the snapshot's write time - rendered as an
  /// "offline, last updated X ago" banner so stale data is never mistaken
  /// for live.
  DateTime? _offlineSnapshotAt;
  /// True while rendering cached (offline) data. Suppresses the staleness
  /// aging - which is built to HIDE old rows - so last-known positions stay
  /// on screen; cleared the moment a live tick or a successful poll lands.
  bool _offlineMode = false;
  bool _followBus = true;
  /// Bus the camera is pinned to once following starts, so alternating
  /// reports from two buses cannot teleport the camera between them.
  int? _followBusId;
  LatLng? _lastFollowPoint;
  DateTime _lastFollowMove = DateTime.fromMillisecondsSinceEpoch(0);
  String _etaInfo = '';

  /// Calibrated cruise speed (km/h) for this route, from its own historical
  /// moving fixes. null until loaded (or unavailable on a fresh route) -
  /// [_etaMinutes] then falls back to the fixed 20 km/h floor.
  double? _routeCruiseKmh;

  // ---- In-app turn-by-turn navigation ----
  /// Guidance is active: banner shown, camera follows the user, off-route
  /// detection and arrival are armed.
  bool _navigating = false;
  /// A route is being calculated (start or reroute) - drives the banner's
  /// "Calculating route.../Rerouting..." state.
  bool _navRouting = false;
  /// Voice guidance on/off (session only).
  bool _navVoice = true;
  RouteFollower? _follower;
  RouteProgress? _progress;
  /// Last announced step, so speech and haptics fire once per maneuver.
  int _spokenStepIndex = -1;
  /// Next stop the user is heading for; reroutes join the route after it
  /// instead of backtracking to a stop they already passed.
  int _navNextStopIndex = 0;
  PickupPoint? _navDestination;
  int _navDestinationIndex = 0;
  /// Bumped on start/cancel so an in-flight fetch cannot resurrect a
  /// navigation the user already ended.
  int _navSession = 0;
  DateTime? _lastRerouteAt;
  /// Position on the reroute backoff ladder: 0 waits 20 s, then 40, 80,
  /// 160, 300 s max - a dead network must not hammer the public routers
  /// once per GPS fix. Reset when a reroute succeeds.
  int _rerouteFailures = 0;
  /// Off-route episode latch: entered when the user crosses 45 m off the
  /// polyline, held until they are back under 30 m. Hysteresis so GPS
  /// hovering at the threshold cannot retrigger a reroute every fix.
  bool _offRouteEpisode = false;
  FlutterTts? _tts;
  Future<void>? _ttsInit;

  final LatLng _larkanaCenter = const LatLng(27.5580, 68.2120);

  @override
  void initState() {
    super.initState();
    _requestLocationPermissions();
    _setupPickupMarkers();
    _setupRoutePolyline();
    // The live subscription is started by _loadBusData() once the route's
    // bus list is known, so its events can be filtered from the first tick.
    _loadBusData();
    _setupNotificationHandler();
    // Re-age stale rows and poll over REST: realtime only speaks on new
    // inserts, and a dropped websocket must not freeze the map.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _ageOutStaleBuses();
      _pollBusLocations();
    });
  }

  @override
  void dispose() {
    _myPositionSubscription?.cancel();
    _busSubscription?.cancel();
    _busFeedRestart?.cancel();
    _refreshTimer?.cancel();
    // NotificationService is a singleton that outlives this screen; leaving
    // the callback registered would let a later notification tap call
    // _mapController.move() on an already-disposed controller.
    NotificationService().onNotificationOpened = null;
    // FlutterMap is our child, so it has already disposed itself by the time
    // this runs. We own the controller, so we must dispose it ourselves.
    _mapController.dispose();
    // Cut off any queued utterance when the screen goes away.
    unawaited(_tts?.stop());
    _busRevision.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    // Refused, either just now or on a previous run. Opening a stream that
    // can never deliver would only hold a dead subscription open, so leave
    // the map exactly as it renders today - no dot, everything else intact.
    // But DO explain why: a silent no-dot map reads as broken.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _offerLocationHelp();
      return;
    }
    _startMyLocationStream();
  }

  /// One dialog per session when GPS is refused: says what breaks (live bus
  /// positions, ETAs, turn-by-turn) and offers the system settings page.
  void _offerLocationHelp() {
    if (_locationHelpShown || !mounted) return;
    _locationHelpShown = true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('Location is off'),
          ],
        ),
        content: const Text(
          'Live bus positions, ETAs and turn-by-turn navigation need GPS. '
          'Allow location for this app to use them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              // Override the theme's full-width minimum (actions row).
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  /// Streams GPS fixes for the blue dot.
  ///
  /// Normally [distanceFilter] is 10 m so the marker is only rebuilt once
  /// the device has genuinely moved - not on every raw fix (a [setState]
  /// that would rebuild all marker layers while stationary). While
  /// navigating the stream restarts at distanceFilter 0: a student who
  /// stops walking must still produce fixes, or arrival and reroute can
  /// never re-evaluate. Processing is throttled in [_handlePosition].
  void _startMyLocationStream({int distanceFilter = 10}) {
    if (distanceFilter == _positionFilter &&
        _myPositionSubscription != null) {
      return;
    }
    _positionFilter = distanceFilter;
    final LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );

    unawaited(_myPositionSubscription?.cancel());
    late final StreamSubscription<Position> sub;
    sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _handlePosition,
      // Permission revoked mid-session, or GPS unavailable. The dot just
      // disappears; nothing else on the screen is affected.
      //
      // BOTH callbacks clear the reference (identity-guarded so a newer
      // stream is never nulled by an old one's death): the guard at the top
      // refuses to resubscribe while it sees a non-null subscription, so a
      // closed-but-stale one left navigation stuck at "Preparing
      // guidance..." forever after a single stream error.
      onError: (_) {
        if (identical(_myPositionSubscription, sub)) {
          _myPositionSubscription = null;
        }
      },
      onDone: () {
        if (identical(_myPositionSubscription, sub)) {
          _myPositionSubscription = null;
        }
      },
    );
    _myPositionSubscription = sub;
  }

  /// Single pipeline for every GPS fix: the blue dot first, then - while
  /// navigating - route progress, step announcements, camera follow, arrival
  /// and off-route detection.
  void _handlePosition(Position pos) {
    if (!mounted) return;
    final p = LatLng(pos.latitude, pos.longitude);

    if (!_navigating || _follower == null) {
      setState(() => _myPosition = pos);
      return;
    }

    // Guidance runs the stream at distanceFilter 0 (stationary students
    // still need fixes), so throttle processing to one every 2 s: GPS noise
    // would otherwise rebuild every marker layer ~1 Hz for no new facts.
    final now = DateTime.now();
    if (now.difference(_lastNavFix) < const Duration(seconds: 2)) return;
    _lastNavFix = now;

    final previousStep = _progress?.nextStepIndex;
    final progress = _follower!.update(
      p,
      speedMps: pos.speed > 0 ? pos.speed : null,
    );
    setState(() {
      _myPosition = pos;
      _progress = progress;

      // A stop we were heading for is now within 50 m: later reroutes start
      // from the next stop rather than re-routing back into this one.
      if (_navNextStopIndex < widget.pickupPoints.length &&
          _navNextStopIndex <= _navDestinationIndex) {
        final stop = widget.pickupPoints[_navNextStopIndex];
        if (distanceMeters(p, LatLng(stop.latitude, stop.longitude)) < 50) {
          _navNextStopIndex++;
        }
      }
    });

    // While guiding, the camera follows the user - not the bus.
    if (_mapReady) {
      _mapController.move(p, math.max(_mapController.camera.zoom, 16.0));
    }

    if (progress.arrived) {
      _endNavigation(arrived: true);
      return;
    }
    if (previousStep != null && previousStep != progress.nextStepIndex) {
      HapticFeedback.mediumImpact();
      _lastSpokenBucket = _maneuverBucket(progress.distanceToManeuver);
      _speakStep(progress.nextStepIndex);
    } else {
      // Re-announce the current maneuver at 80 m and again at 25 m: each
      // step used to be spoken exactly once - one late cue at driving speed
      // and no follow-up at all.
      final bucket = _maneuverBucket(progress.distanceToManeuver);
      if (bucket > _lastSpokenBucket) {
        _lastSpokenBucket = bucket;
        _spokenStepIndex = -1; // let the same step speak again
        _speakStep(progress.nextStepIndex);
      }
    }
    // Hysteresis: enter the off-route state past 45 m, leave it only under
    // 30 m, so a fix oscillating at the threshold cannot retrigger a reroute.
    // The 50 m remaining floor closes the old dead zone: with 120 m, a GPS
    // 60-90 m off the polyline near the destination neither rerouted
    // (remaining too small) nor arrived (still >30 m) - guidance hung on
    // "In 118 m - Turn left..." forever.
    if (progress.distanceOffRoute > (_offRouteEpisode ? 30.0 : 45.0) &&
        progress.remainingMeters > 50) {
      _offRouteEpisode = true;
      unawaited(_maybeReroute());
    } else if (progress.distanceOffRoute < 30.0) {
      _offRouteEpisode = false;
    }
  }

  /// 0 = too far to announce, 1 = within 80 m of the maneuver, 2 = within
  /// 25 m (spoken distance bands for the re-announce ladder).
  int _maneuverBucket(double distance) =>
      distance <= 25 ? 2 : (distance <= 80 ? 1 : 0);

  void _setupNotificationHandler() {
    NotificationService().onNotificationOpened = (data) {
      // dispose() clears this callback; the guard covers a tap that was
      // already in flight while the screen was being removed.
      if (!mounted) return;
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
      // Paint the straight stop-to-stop placeholder ONLY when nothing is on
      // screen (first load). After guidance ends - or a nav start fails -
      // the road geometry from before is still good: flashing the crude
      // line over it (or leaving it when the routers are down) was a
      // downgrade to a lie about the road.
      if (_polylines.isEmpty) {
        // Baseline geometry for bus map-matching: the stop-to-stop line,
        // upgraded to the real road geometry when it arrives below.
        _routePoints = [
          for (final p in widget.pickupPoints)
            LatLng(p.latitude, p.longitude),
        ];
        _polylines = [
          Polyline(
            points: widget.pickupPoints
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            color: Colors.blue,
            strokeWidth: 4,
            // Equivalent to Google's [dash(20), gap(10)]: alternating
            // dash/gap segment lengths in logical pixels. Not `const` because
            // StrokePattern.dashed asserts on `segments.length`, which cannot
            // be evaluated in a constant expression.
            pattern: StrokePattern.dashed(segments: const [20, 10]),
          ),
        ];
      }
    });

    // Upgrades the placeholder (or refreshes existing geometry) with the
    // real road route; RouteService caches identical requests, so a
    // start/cancel navigation cycle no longer costs four router calls.
    _fetchRoadGeometry();
  }

  /// Draws the full route with real road geometry.
  ///
  /// The straight stop-to-stop line appears instantly as a placeholder, then
  /// [RouteService] upgrades it to the driving route (OSRM, falling back to
  /// Valhalla). If every router fails, the straight line simply stays: the
  /// map remains usable, just less road-accurate.
  Future<void> _fetchRoadGeometry() async {
    final stops = widget.pickupPoints;
    if (stops.length < 2) return;

    final route = await RouteService().fetchRoute([
      for (final p in stops) LatLng(p.latitude, p.longitude),
    ]);
    // Navigation may have drawn its own (user-position based) route while
    // this was in flight - guidance wins over the full-route fetch.
    if (!mounted || route == null || _navigating) return;
    setState(() {
      // Real road geometry doubles as the map-matching line: bus markers
      // snap onto it (see _updateBusMarkers). Never touched by navigation,
      // whose guard above returns before this runs.
      _routePoints = List<LatLng>.of(route.points);
      _polylines = [
        Polyline(
          points: route.points,
          color: Colors.blue,
          strokeWidth: 4,
          pattern: StrokePattern.dashed(segments: const [20, 10]),
        ),
      ];
    });
    debugPrint(
      '[route] ${route.source} geometry applied: ${route.points.length} points',
    );
  }

  // -----------------------------------------------------------------------
  // In-app turn-by-turn navigation
  // -----------------------------------------------------------------------

  /// Starts guidance from the user's position to [destination].
  ///
  /// The route is requested with the user's current position as its first
  /// waypoint, so the polyline and the maneuver steps describe *their* path
  /// - not the abstract bus route.
  Future<void> _startNavigation(PickupPoint destination) async {
    if (_navRouting) {
      // Silently swallowing a second tap looked like a dead button.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still calculating your route...')),
      );
      return;
    }

    final pos = _myPosition;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turn on location (GPS) to start navigation'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final destinationIndex = widget.pickupPoints.indexOf(destination);
    if (destinationIndex < 0) return;

    // Join the bus route at a stop near the user, never past the
    // destination. The 15% tolerance means a LATER stop that is almost as
    // close wins: on a route that loops near itself, snapping to the
    // earlier pass dragged the student backwards and then forward again
    // over the same road.
    var nearest = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i <= destinationIndex; i++) {
      final stop = widget.pickupPoints[i];
      final distance = distanceMeters(
        LatLng(pos.latitude, pos.longitude),
        LatLng(stop.latitude, stop.longitude),
      );
      if (distance < nearestDistance * 1.15) {
        nearestDistance = distance;
        nearest = i;
      }
    }

    debugPrint(
      '[nav] start to ${destination.pointName} '
      '(idx $destinationIndex, join stop $nearest)',
    );

    final session = ++_navSession;
    setState(() {
      _navRouting = true;
      _navigating = false; // supersede any running guidance
      _follower = null;
      _progress = null;
      _navNextStopIndex = nearest;
      _navDestination = destination;
      _navDestinationIndex = destinationIndex;
      _spokenStepIndex = -1;
      _lastSpokenBucket = 0;
      _navViaNames = const [];
    });
    // Full fixes while calculating/guiding: a student who stops walking
    // must still produce position updates or arrival can never latch.
    _startMyLocationStream(distanceFilter: 0);

    final route = await RouteService().fetchRoute(
      _navWaypoints(LatLng(pos.latitude, pos.longitude)),
      // GPS-keyed: unique per fix. Never persist - it would evict the fixed
      // route geometries from the 16-entry disk cache (see fetchRoute).
      persistToDisk: false,
    );
    if (!mounted || session != _navSession) return;
    if (route == null) {
      setState(() => _navRouting = false);
      // Guidance never started: hand the stream back to the 10 m filter.
      _startMyLocationStream(distanceFilter: 10);
      // Whatever route was drawn before stays/returns; nothing was adopted.
      _setupRoutePolyline();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not calculate a route - check your connection'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _adoptNavRoute(route);
  }

  /// Waypoints for a (re)route: the user's position, then every stop from
  /// the next one ahead up to the chosen destination.
  List<LatLng> _navWaypoints(LatLng current) {
    final points = <LatLng>[current];
    if (widget.pickupPoints.isEmpty) return points;

    final last = math.min(
      _navDestinationIndex,
      widget.pickupPoints.length - 1,
    );
    for (var i = _navNextStopIndex; i <= last; i++) {
      final stop = widget.pickupPoints[i];
      points.add(LatLng(stop.latitude, stop.longitude));
    }
    if (points.length == 1) {
      // Degenerate (already past the destination): head to it directly.
      final stop = widget.pickupPoints[last];
      points.add(LatLng(stop.latitude, stop.longitude));
    }
    return points;
  }

  /// Installs a freshly fetched route as the active navigation state and
  /// announces the first maneuver.
  void _adoptNavRoute(RoadRoute route) {
    setState(() {
      _navRouting = false;
      _navigating = true;
      // A freshly installed polyline is the user's current reality: close
      // the off-route episode and reset the reroute backoff (this reroute
      // succeeded).
      _offRouteEpisode = false;
      _rerouteFailures = 0;
      _polylines = [
        Polyline(
          points: route.points,
          color: Colors.blue,
          strokeWidth: 4,
          pattern: StrokePattern.dashed(segments: const [20, 10]),
        ),
      ];
      _follower = RouteFollower(points: route.points, steps: route.steps);
      _progress = null;
      _spokenStepIndex = -1;
      _lastSpokenBucket = 0;
    });
    // Via-stop names for this guidance (leg k ends at via k), captured NOW:
    // _navNextStopIndex keeps advancing during the trip and must not shift
    // the arrive-step <-> stop-name mapping while speaking.
    _navViaNames = [
      for (var i = _navNextStopIndex;
          i <=
              math.min(
                _navDestinationIndex,
                widget.pickupPoints.length - 1,
              );
          i++)
        widget.pickupPoints[i].pointName,
    ];
    debugPrint(
      '[nav] route adopted (${route.source}: ${route.points.length} points, '
      '${route.steps.length} steps)',
    );

    final pos = _myPosition;
    if (pos == null) return;
    final progress = _follower!.update(LatLng(pos.latitude, pos.longitude));
    setState(() => _progress = progress);
    _lastSpokenBucket = _maneuverBucket(progress.distanceToManeuver);
    _speakStep(progress.nextStepIndex);
  }

  /// Recalculates once the user has strayed from the polyline - debounced
  /// with exponential backoff so GPS noise and dead networks cannot spin it
  /// into a loop against the public routers.
  Future<void> _maybeReroute() async {
    if (_navRouting || !_navigating) return;
    // Backoff ladder: 20 s, 40 s, 80 s, 160 s, then 5 minutes max.
    const backoff = [20, 40, 80, 160, 300];
    final delaySeconds = backoff[_rerouteFailures > 4 ? 4 : _rerouteFailures];
    if (_lastRerouteAt != null &&
        DateTime.now().difference(_lastRerouteAt!) <
            Duration(seconds: delaySeconds)) {
      return;
    }
    final pos = _myPosition;
    if (pos == null) return;

    _lastRerouteAt = DateTime.now();
    final session = _navSession;
    setState(() => _navRouting = true);
    debugPrint('[nav] off route - rerouting from the current position');

    final route = await RouteService().fetchRoute(
      _navWaypoints(LatLng(pos.latitude, pos.longitude)),
      // Same as _startNavigation: GPS-keyed, session-only cache.
      persistToDisk: false,
    );
    // Measure the debounce from when the ATTEMPT ENDED, not when it started:
    // OSRM+Valhalla can burn ~14 s in timeouts, which - timed from the start
    // - nearly exhausts the flat 20 s window and would retry almost instantly.
    _lastRerouteAt = DateTime.now();
    if (!mounted || session != _navSession) return;
    if (route == null) {
      _rerouteFailures = _rerouteFailures < 4 ? _rerouteFailures + 1 : 4;
      // Keep guiding on the old polyline; the banner stops saying rerouting.
      setState(() => _navRouting = false);
      return;
    }
    _rerouteFailures = 0;
    _adoptNavRoute(route);
  }

  /// Stops guidance. On [arrived] the destination is announced first.
  void _endNavigation({required bool arrived}) {
    ++_navSession; // invalidate any in-flight (re)route fetch
    final destination = _navDestination;
    final wasNavigating = _navigating;
    setState(() {
      _navigating = false;
      _navRouting = false;
      _follower = null;
      _progress = null;
      _navDestination = null;
      _spokenStepIndex = -1;
      _lastSpokenBucket = 0;
      _navViaNames = const [];
      _lastRerouteAt = null;
      _rerouteFailures = 0;
      _offRouteEpisode = false;
    });

    if (arrived) {
      _speakNow('You have arrived at ${destination?.pointName ?? 'your stop'}');
    } else {
      unawaited(_tts?.stop());
    }
    // The full-route line takes over again after guidance.
    if (wasNavigating) {
      _setupRoutePolyline();
    }
    // Back to the walking-distance filter now that nobody is guiding.
    // Cancellation must cover the ROUTING window too: the close button is
    // shown while "Calculating route…"/"Rerouting…" (when _navigating is
    // still false), and _startNavigation had already switched the stream to
    // distanceFilter: 0 - exiting there used to leave every raw GPS fix
    // (~1 Hz) rebuilding the marker layers for the rest of the session.
    if (wasNavigating || _positionFilter == 0) {
      _startMyLocationStream(distanceFilter: 10);
    }
  }

  /// Announces maneuver [index] once. Speech is async, hence unawaited -
  /// failures are logged inside [_speakNow] and never interrupt guidance.
  void _speakStep(int index) {
    final steps = _follower?.steps ?? const <RouteStep>[];
    if (index < 0 || index >= steps.length) return;
    if (index == _spokenStepIndex) return;
    _spokenStepIndex = index;
    if (!_navVoice) return;

    final distance = _progress?.distanceToManeuver ?? steps[index].distance;
    final prefix = distance >= 20
        ? 'In ${RouteStep.formatDistance(distance)}, '
        : '';
    // Intermediate arrive-steps are relabelled: OSRM voices "Arrive at your
    // stop" at the end of EVERY leg, wrong while merely passing a via stop.
    unawaited(_speakNow('$prefix${_stepInstruction(steps, index)}'));
  }

  /// Instruction for [index], with intermediate arrivals relabelled to
  /// "Passing `<stop>`". Only the LAST arrive step is the destination.
  String _stepInstruction(List<RouteStep> steps, int index) {
    if (index < 0 || index >= steps.length) return '';
    final step = steps[index];
    if (step.isArrival) {
      var lastArrival = -1;
      for (var i = 0; i < steps.length; i++) {
        if (steps[i].isArrival) lastArrival = i;
      }
      if (index < lastArrival) {
        var leg = 0;
        for (var i = 0; i < index; i++) {
          if (steps[i].isArrival) leg++;
        }
        final name = leg < _navViaNames.length
            ? _navViaNames[leg]
            : 'the next stop';
        return 'Passing $name';
      }
    }
    return step.instruction;
  }

  /// Speaks [text], replacing anything queued. Speech failures are logged,
  /// never fatal: guidance must work even without a TTS engine installed.
  Future<void> _speakNow(String text) async {
    if (!_navVoice) return;
    try {
      await _initTts();
      await _tts?.stop();
      await _tts?.speak(text);
    } catch (e) {
      debugPrint('[nav] speech failed: $e');
    }
  }

  Future<void> _initTts() => _ttsInit ??= _createTts();

  Future<void> _createTts() async {
    try {
      final tts = FlutterTts();
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.45);
      await tts.setVolume(1.0);
      _tts = tts;
    } catch (e) {
      debugPrint('[nav] TTS unavailable: $e');
      // Only cache this failure until the next utterance: pinning the failed
      // future forever meant one transient engine error silenced voice
      // guidance for the whole session. Deferred by a microtask so it cannot
      // race _initTts's own `??=` assignment to this future.
      scheduleMicrotask(() => _ttsInit = null);
    }
  }

  /// Banner icon for the maneuver the user is about to perform.
  IconData _navIconFor(RouteStep? step) {
    final key = step?.maneuver ?? '';
    if (key.startsWith('arrive')) return Icons.flag;
    if (key.contains('roundabout')) return Icons.roundabout_right;
    if (key.contains('uturn') || key.contains('reverse')) {
      return Icons.u_turn_left;
    }
    if (key.contains('fork') || key.contains('merge') || key.contains('ramp')) {
      return Icons.merge_type;
    }
    if (key.endsWith('left')) return Icons.turn_left;
    if (key.endsWith('right')) return Icons.turn_right;
    return Icons.straight;
  }

  /// The turn-by-turn card pinned to the top of the map.
  Widget _buildNavigationBanner() {
    final progress = _progress;
    final steps = _follower?.steps ?? const <RouteStep>[];
    // nextStepIndex can equal steps.length once the last maneuver is
    // passed - indexing blindly there was a latent RangeError.
    final nextStep = (progress != null &&
            progress.nextStepIndex >= 0 &&
            progress.nextStepIndex < steps.length)
        ? steps[progress.nextStepIndex]
        : null;

    final String headline;
    if (_navRouting) {
      headline = _navigating ? 'Rerouting…' : 'Calculating route…';
    } else if (progress == null) {
      headline = 'Preparing guidance…';
    } else if (progress.arrived) {
      headline = 'Arrived at ${_navDestination?.pointName ?? 'destination'}';
    } else if (progress.distanceToManeuver < 20) {
      headline = 'Now';
    } else {
      headline = 'In ${RouteStep.formatDistance(progress.distanceToManeuver)}';
    }

    final String detail;
    if (_navRouting) {
      detail = 'Following your GPS position';
    } else {
      detail = nextStep == null
          ? 'Follow the highlighted route'
          : _stepInstruction(steps, progress!.nextStepIndex);
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_navIconFor(nextStep), color: Colors.blue, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          headline,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_navRouting) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!_navRouting && progress != null)
                    Text(
                      'Remaining ${RouteStep.formatDistance(progress.remainingMeters)}'
                      ' to ${_navDestination?.pointName ?? 'your stop'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_navVoice ? Icons.volume_up : Icons.volume_off),
                  tooltip: _navVoice
                      ? 'Voice guidance on'
                      : 'Voice guidance off',
                  onPressed: () {
                    setState(() => _navVoice = !_navVoice);
                    if (!_navVoice) unawaited(_tts?.stop());
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'End navigation',
                  onPressed: () => _endNavigation(arrived: false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The device's own position rendered as a marker.
  ///
  /// Returns an empty list until the first fix arrives - or forever, when
  /// permission was denied - so a no-permission session looks exactly as it
  /// does today rather than rendering a broken marker at (0, 0).
  List<Marker> get _myLocationMarkers {
    final pos = _myPosition;
    if (pos == null) return const [];

    return [
      Marker(
        point: LatLng(pos.latitude, pos.longitude),
        width: 30,
        height: 30,
        // Soft accuracy halo with a white-ringed blue disc inside - the
        // conventional "you are here" treatment. Read-only, so no
        // GestureDetector: tapping it must not swallow taps meant for a stop
        // or bus underneath.
        // Screen-reader label: without it this dot is a silent decorative
        // box to TalkBack.
        child: Semantics(
          label: 'Your location',
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withValues(alpha: 0.18),
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Future<void> _loadBusData() async {
    try {
      // Stop-notification preferences are independent of the bus queries -
      // start them now, await later, instead of stacking another round-trip
      // after them. The error handler attaches immediately so a rejection
      // while the bus queries are still running cannot surface as an
      // unhandled async error; null keeps the toggles' current values.
      final preferencesFuture = widget.pickupPoints.isEmpty
          ? Future<Set<int>?>.value(null)
          : _service
                .getActiveStopNotifications(
                  widget.pickupPoints.map((p) => p.id).toList(),
                )
                .then<Set<int>?>((v) => v, onError: (_) => null);

      final buses = await _service.getBusesForRoute(widget.route.id);
      // Passes `buses` along: getBusLocationsForRoute would otherwise fetch
      // the exact same list again (two round-trips for identical data).
      final locations = await _service.getBusLocationsForRoute(
        widget.route.id,
        buses: buses,
      );
      // First server-stamped rows of the session: seed the fix horizon all
      // freshness checks age against (see _freshnessNow).
      _absorbFixHorizon(locations);

      // Calibrated cruise speed for ETA maths - best-effort, and null on a
      // fresh route keeps the fixed 20 km/h floor (see _etaMinutes).
      _routeCruiseKmh = await _service
          .getRouteCruiseSpeedKmh(widget.route.id)
          .then<double?>((v) => v, onError: (_) => null);

      // Re-read what is actually stored for this user instead of forcing every
      // toggle back to false on refresh: the old code left the subscriptions
      // alive on the server while the UI claimed they were off, so arrival
      // alerts silently stopped firing after a refresh.
      // null = the query failed; the toggles then keep their current values.
      final activeStopIds = widget.pickupPoints.isNotEmpty
          ? await preferencesFuture
          : null;

      if (!mounted) return;
      // Route filter + TTL applied HERE too (this path used to assign the
      // raw list): the poll and stream paths both collapse, and skipping it
      // showed >5-minute-old rows as live and inflated the "N active"
      // counter for up to 30 s after a load/refresh. `_buses` is set first
      // because _collapseBusRows filters by it.
      _buses = buses;
      final collapsed = _collapseBusRows(locations);
      setState(() {
        _busLocations = collapsed;
        _busRevision.value++;
        // A successful load is proof the feed path works again: reopen the
        // stream-restart budget. Previously only the stream listener reset
        // it, so three past failures stayed burned in for the whole session
        // and the auto-restart silently stopped firing.
        _busFeedRestarts = 0;
        _isLoading = false;
        // A successful reload must clear a previous failure, otherwise the
        // retry button could never bring the map back.
        _error = null;
        // ...and any offline state: we are back on live data.
        _offlineMode = false;
        _offlineSnapshotAt = null;

        if (activeStopIds != null) {
          for (final point in widget.pickupPoints) {
            _notificationsEnabled[point.id] = activeStopIds.contains(point.id);
          }
        }
      });

      // Refresh the offline snapshot (best-effort): the next dead-connection
      // open shows these positions instead of a blank map.
      unawaited(OfflineCache.instance.saveBusListSnapshot(widget.route.id, buses));
      unawaited(OfflineCache.instance.saveBusSnapshot(widget.route.id, locations));

      // Start (or restart) the live feed only now that `_buses` is known, so
      // events can be narrowed to this route's buses from the first tick.
      _subscribeToBusLocations();
      // Seed immediately: the stream's initial replay window (latest 500
      // rows PROJECT-wide) can be crowded out by other routes' inserts,
      // leaving this map blank until the next 30 s poll. The poll is
      // self-guarding and skips its setState when nothing changed.
      unawaited(_pollBusLocations());

      _updateBusMarkers();
      _updateETAInfo();
    } catch (e) {
      if (!mounted) return;
      // Raw PostgREST/SQL text never goes on screen (it leaks schema);
      // the retry button still brings the map back once.
      debugPrint('[map] bus data load failed: $e');
      // Fall back to the last cached bus list + positions: a dead data
      // connection still shows WHERE buses were (labelled offline) instead
      // of a blank error. The 30 s poll keeps trying and auto-recovers.
      final cachedBuses = await OfflineCache.instance.loadBusListSnapshot(
        widget.route.id,
      );
      final cachedLocations = await OfflineCache.instance.loadBusSnapshot(
        widget.route.id,
      );
      if (!mounted) return;
      if (cachedBuses != null &&
          cachedBuses.buses.isNotEmpty &&
          cachedLocations != null &&
          cachedLocations.locations.isNotEmpty) {
        setState(() {
          _buses = cachedBuses.buses;
          _busLocations = cachedLocations.locations;
          _offlineMode = true;
          _offlineSnapshotAt = cachedLocations.savedAt;
          _busRevision.value++;
          _isLoading = false;
          _error = null;
        });
        // Live feed may already be running from a prior successful load;
        // restart it against the cached bus list so recovery is automatic.
        _subscribeToBusLocations();
        _updateBusMarkers();
        _updateETAInfo();
        debugPrint(
          '[map] offline: showing ${cachedLocations.locations.length} cached '
          'bus fix(es) from ${cachedLocations.savedAt}',
        );
        return;
      }
      setState(() {
        _error =
            'Could not load live bus data. Check your connection and try again.';
        _isLoading = false;
      });
    }
  }

  void _subscribeToBusLocations() {
    // Restart cleanly when called again after a refresh.
    _busSubscription?.cancel();

    // Supabase's `.stream()` offers no `where` clause and `bus_locations` has
    // no route column, so the feed carries every bus in the project; the
    // filtering happens here. An empty bus list (still loading, or this route
    // really has no active buses) must show NOTHING - it used to fall back to
    // the unfiltered feed, painting other routes' buses onto this map.
    _busSubscription = _service.subscribeToBusLocations().listen(
      (locations) {
        if (!mounted) return;
        // Healthy tick: reopen the restart budget for future failures.
        _busFeedRestarts = 0;
        // Realtime rows are INSERTs happening now: the freshest skew sample
        // available. Absorbed before the log so the warning sees the
        // up-to-date horizon.
        _absorbFixHorizon(locations);
        _logClockSkew(locations);
        setState(() {
          // Newest row per bus, this route only, fresh only - see
          // _collapseBusRows; the raw stream is an append history.
          _busLocations = _collapseBusRows(locations);
          _busRevision.value++;
          // Live data is flowing again: leave offline (cached) mode.
          _offlineMode = false;
          _offlineSnapshotAt = null;
        });
        _updateBusMarkers();
        _updateETAInfo();
        _checkNotifications();
      },
      // channelError/timedOut (a dropped websocket): realtime_client
      // rejoins on reconnect and the stream reloads itself, so this is
      // informational - but without a handler the exception escaped as an
      // unhandled error after long idling.
      onError: (Object error) =>
          debugPrint('[map] bus feed error (resumes on reconnect): $error'),
      // `closed` is final: without a restart the map sits stale until a
      // manual refresh, so schedule a bounded resubscribe instead.
      onDone: _scheduleBusFeedRestart,
    );
  }

  /// Restarts a bus feed whose channel reported `onDone`, with a cap.
  ///
  /// A closed realtime channel never comes back by itself, but a server
  /// that keeps rejecting the join must not turn this into a resubscribe
  /// loop: at most three consecutive attempts, and any healthy tick
  /// resets the budget.
  void _scheduleBusFeedRestart() {
    if (!mounted) return;
    if (_busFeedRestarts >= 3) {
      // The rapid-retry budget is spent - cool down instead of giving up
      // forever: a student opening the map in a basement used to end up
      // with a dead feed until they found the refresh button.
      _busFeedRestart?.cancel();
      _busFeedRestart = Timer(const Duration(seconds: 60), () {
        if (!mounted) return;
        debugPrint('[map] bus feed cool-down over - resubscribing');
        _busFeedRestarts = 0;
        _subscribeToBusLocations();
      });
      debugPrint('[map] bus feed closed - restart budget spent, cool-down 60 s');
      return;
    }
    _busFeedRestart?.cancel();
    ++_busFeedRestarts;
    debugPrint(
      '[map] bus feed closed - restarting '
      '(attempt $_busFeedRestarts/3)',
    );
    _busFeedRestart = Timer(const Duration(seconds: 5), () {
      if (mounted) _subscribeToBusLocations();
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
        final Color markerColor =
            loc.speed > 2 ? Colors.cyan : Colors.deepPurple;

        // Map-match for display: raw GPS wanders off the drawn road line
        // (fields, alleys, tree cover), which reads to a student as "the
        // bus left the route" even when it is exactly where it should be.
        // The snap only ever moves the DRAWN marker - distances, ETAs and
        // arrival logic keep using the raw fix.
        final markerPoint = snapToRoute(
          LatLng(loc.latitude, loc.longitude),
          _routePoints,
          _busSnapDistance,
        );

        _busMarkers.add(
          Marker(
            point: markerPoint,
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

    // Follow the route's bus if enabled - but never while guiding, where the
    // camera belongs to the user, not the bus.
    if (_followBus && !_navigating && _busLocations.isNotEmpty && _mapReady) {
      BusLocation? target;
      if (_followBusId != null) {
        for (final loc in _busLocations) {
          if (loc.busId == _followBusId) {
            target = loc;
            break;
          }
        }
      }
      // Pinned bus stopped reporting (or nothing pinned yet): pick a new one
      // deterministically - not "whichever bus's report arrived most recently".
      target ??= _pickFollowTarget();
      _followBusId = target.busId;

      // Throttled: alternating updates from two buses, or a fix every few
      // seconds, used to teleport/fight the camera. Only a genuinely new
      // position moves it, at most twice a second.
      final point = snapToRoute(
        LatLng(target.latitude, target.longitude),
        _routePoints,
        _busSnapDistance,
      );
      final moved =
          _lastFollowPoint == null ||
          distanceMeters(point, _lastFollowPoint!) > 15;
      if (moved &&
          DateTime.now().difference(_lastFollowMove) >
              const Duration(milliseconds: 500)) {
        _lastFollowPoint = point;
        _lastFollowMove = DateTime.now();
        _mapController.move(
          point,
          _mapController.camera.zoom, // CameraUpdate.newLatLng kept the zoom
        );
      }
    }
  }

  /// Deterministic bus to follow: the one closest to the first pickup point
  /// (the bus students are waiting for), stable regardless of which bus
  /// reported last.
  BusLocation _pickFollowTarget() {
    if (widget.pickupPoints.isEmpty) return _busLocations.first;
    final stop = widget.pickupPoints.first;
    return _busLocations.reduce(
      (a, b) =>
          a.distanceTo(stop.latitude, stop.longitude) <
              b.distanceTo(stop.latitude, stop.longitude)
          ? a
          : b,
    );
  }

  /// Advance the fix horizon (monotonic) from a batch of server-stamped rows.
  void _absorbFixHorizon(Iterable<BusLocation> locations) {
    for (final loc in locations) {
      final horizon = _serverFixHorizon;
      if (horizon == null || loc.timestamp.isAfter(horizon)) {
        _serverFixHorizon = loc.timestamp;
      }
    }
  }

  /// Clock for freshness checks: server-relative while the newest fix is
  /// within 15 min of this device (both clocks roughly agree, so ages are
  /// exact); the device clock once they diverge further - the feed has been
  /// quiet that long (no new server timestamp to advance the horizon) or
  /// the device clock is broken. The fallback is logged by _logClockSkew.
  DateTime _freshnessNow() {
    final horizon = _serverFixHorizon;
    if (horizon == null) return DateTime.now();
    final drift = DateTime.now().difference(horizon);
    if (drift.abs() > const Duration(minutes: 15)) return DateTime.now();
    return horizon;
  }

  /// Collapse raw feed rows to what the map shows: this route's buses only,
  /// newest row per bus, nothing older than [_staleAfter].
  ///
  /// The realtime stream APPENDS every insert since subscribe, so without
  /// the per-bus collapse the map drew a trail of ghost markers down the
  /// road and the "N active" pill counted history instead of buses.
  List<BusLocation> _collapseBusRows(Iterable<BusLocation> locations) {
    // Absorbed first so the freshness clock below already sees this batch.
    _absorbFixHorizon(locations);
    final routeBusIds = _buses.map((b) => b.id).toSet();
    final newest = <int, BusLocation>{};
    final now = _freshnessNow();
    for (final loc in locations) {
      if (!routeBusIds.contains(loc.busId)) continue;
      if (now.difference(loc.timestamp) >= _staleAfter) continue;
      final prev = newest[loc.busId];
      if (prev == null || loc.timestamp.isAfter(prev.timestamp)) {
        newest[loc.busId] = loc;
      }
    }
    return newest.values.toList();
  }

  /// Fresh rows only (younger than [_staleAfter]).
  ///
  /// Offline (cached) rows are deliberately kept past the live window - the
  /// banner carries the staleness, exactly as in [_ageOutStaleBuses] - so
  /// the ETA card counts them instead of claiming "Waiting for live bus
  /// positions..." over a map whose pill and markers show buses.
  bool _isStale(DateTime time) =>
      !_offlineMode && _freshnessNow().difference(time) >= _staleAfter;

  /// ...but only while the snapshot itself is inside that window. A fix
  /// cached 12 hours ago must not compute "arrives in 4 min": the banner
  /// shows the age, yet the ETA text claimed live knowledge it does not
  /// have. Young snapshots (a just-dropped connection) keep the ETA card
  /// working - they are exactly as fresh as live data would be.
  bool get _offlineTooOld =>
      _offlineMode &&
      (_offlineSnapshotAt == null ||
          DateTime.now().difference(_offlineSnapshotAt!) >= _staleAfter);

  List<BusLocation> _freshBuses() =>
      _busLocations.where((loc) => !_isStale(loc.timestamp)).toList();

  /// The bus closest to [point] that is actually still serving it.
  ///
  /// Excludes stale rows (history, not live data) and buses whose next stop
  /// is already beyond [point] - a bus that left must not keep reporting a
  /// shrinking "arrives in 1 min" for a stop it will never reach again.
  /// [BusLocation.nextStopIndex] is 1-based; 0 = every stop on the route has
  /// been served.
  BusLocation? _closestServingBus(PickupPoint point) {
    final stopIndex = widget.pickupPoints.indexOf(point);
    if (stopIndex < 0) return null;
    BusLocation? best;
    var bestDistance = double.infinity;
    for (final loc in _busLocations) {
      if (_isStale(loc.timestamp)) continue;
      if (loc.nextStopIndex == 0 || loc.nextStopIndex > stopIndex + 1) {
        continue;
      }
      final distance = loc.distanceTo(point.latitude, point.longitude);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = loc;
      }
    }
    return best;
  }

  /// Freshest bus near [point] regardless of direction - drives the
  /// distance fallback when no serving bus exists.
  BusLocation? _closestFreshBus(PickupPoint point) {
    BusLocation? best;
    var bestDistance = double.infinity;
    for (final loc in _busLocations) {
      if (_isStale(loc.timestamp)) continue;
      final distance = loc.distanceTo(point.latitude, point.longitude);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = loc;
      }
    }
    return best;
  }

  /// ETA minutes for [bus] to [point]: straight-line distance x a 1.3
  /// road-circuity factor (streets are not straight lines) divided by an
  /// urban cruise floor of 20 km/h - a bus waiting at a red light must not
  /// inflate an 800 m ETA to 45 minutes. Ceiled: "0 min" stays reserved
  /// for a bus actually at the stop.
  int _etaMinutes(BusLocation bus, PickupPoint point) {
    final straightKm = bus.distanceTo(point.latitude, point.longitude);
    if (straightKm <= 0) return 0;
    // Cruise speed: the bus's own live speed, else the route's calibrated
    // historical average, else the fixed 20 km/h urban floor - a bus waiting
    // at a red light must not inflate an 800 m ETA to 45 minutes. Ceiled:
    // "0 min" stays reserved for a bus actually at the stop.
    final speedKmh = math.max(bus.speed, _routeCruiseKmh ?? 20.0);
    return ((straightKm * 1.3 / speedKmh) * 60).ceil();
  }

  /// Ages rows out when the feed goes quiet: realtime only emits on new
  /// inserts, so without a clock a bus that stopped reporting kept its last
  /// position - and its "4 min" ETA - on the map forever.
  void _ageOutStaleBuses() {
    if (!mounted || _busLocations.isEmpty) return;
    // Offline (cached) positions are deliberately shown past their normal
    // freshness window - the banner carries the staleness - so never age
    // them out. Cleared the instant live data returns.
    if (_offlineMode) return;
    final now = _freshnessNow();
    final fresh = _busLocations
        .where((loc) => now.difference(loc.timestamp) < _staleAfter)
        .toList();
    if (fresh.length == _busLocations.length) return;
    debugPrint(
      '[map] aged out ${_busLocations.length - fresh.length} stale bus row(s)',
    );
    setState(() {
      _busLocations = fresh;
      _busRevision.value++;
    });
    _updateBusMarkers();
    _updateETAInfo();
    _checkNotifications();
  }

  /// Low-rate REST poll every 30 s: a dropped websocket or a flaky campus
  /// network must not freeze the map - realtime is the optimization, this
  /// is the floor.
  Future<void> _pollBusLocations() async {
    if (!mounted || _buses.isEmpty || _isLoading || _error != null) return;
    try {
      final locations = await _service.getBusLocationsForRoute(
        widget.route.id,
        buses: _buses,
      );
      if (!mounted) return;
      final collapsed = _collapseBusRows(locations);
      final unchanged =
          collapsed.length == _busLocations.length &&
          collapsed.every(
            (loc) => _busLocations.any(
              (cur) =>
                  cur.busId == loc.busId && cur.timestamp == loc.timestamp,
            ),
          );
      if (unchanged) return;
      setState(() {
        _busLocations = collapsed;
        _busRevision.value++;
        // A successful poll means connectivity is back: leave offline mode.
        _offlineMode = false;
        _offlineSnapshotAt = null;
      });
      _updateBusMarkers();
      _updateETAInfo();
      _checkNotifications();
      debugPrint('[map] REST poll refreshed ${collapsed.length} bus row(s)');
    } catch (e) {
      debugPrint('[map] REST poll failed: $e');
    }
  }

  /// Warn when the device clock disagrees with the server by enough to
  /// matter. Freshness ages rows against the newest server fix (see
  /// [_freshnessNow]), so a few minutes of skew is harmless - but beyond
  /// the 15-minute regime threshold the fallback flips to the device
  /// clock, and that flip (or a clock badly wrong in either direction)
  /// must be visible in the log.
  void _logClockSkew(List<BusLocation> locations) {
    if (locations.isEmpty) return;
    DateTime newest = locations.first.timestamp;
    for (final loc in locations) {
      if (loc.timestamp.isAfter(newest)) newest = loc.timestamp;
    }
    // + = the newest server fix is ahead of the device = clock is BEHIND.
    final skew = newest.difference(DateTime.now());
    if (skew.abs() > const Duration(minutes: 5)) {
      debugPrint(
        '[map] WARNING device clock ${skew.isNegative ? "ahead of" : "behind"}'
        ' the server by ${skew.abs().inMinutes} min - freshness falls back '
        'to the device clock beyond 15 min',
      );
    }
  }

  void _updateETAInfo() {
    if (_busLocations.isEmpty || widget.pickupPoints.isEmpty) {
      _etaInfo = '';
      return;
    }

    if (_offlineTooOld) {
      _etaInfo = _offlineSnapshotAt == null
          ? 'Offline - live arrival times unavailable'
          : 'Offline - buses last seen ${_formatAge(_offlineSnapshotAt!)}';
      return;
    }

    if (_freshBuses().isEmpty) {
      _etaInfo = 'Waiting for live bus positions...';
      return;
    }

    final firstStop = widget.pickupPoints[0];
    final serving = _closestServingBus(firstStop);
    if (serving == null) {
      _etaInfo = 'No bus is heading to ${firstStop.pointName} right now';
      return;
    }

    final eta = _etaMinutes(serving, firstStop);
    if (eta == 0) {
      _etaInfo = 'Bus is at ${firstStop.pointName} now';
    } else {
      _etaInfo = 'First bus arrives at ${firstStop.pointName} in $eta min';
    }
  }

  String _getNextStopName(int nextStopIndex) {
    // 0 = the driver has served every stop on the route (the dashboard's
    // next-stop helper returns 0 at the end). "Unknown" read as a bug.
    if (nextStopIndex == 0) return 'End of route';
    if (nextStopIndex < 0 || nextStopIndex > widget.pickupPoints.length) {
      return 'Unknown';
    }
    return widget.pickupPoints[nextStopIndex - 1].pointName;
  }

  /// Compact "time ago" for the offline banner: "just now", "3 min ago",
  /// "2 h ago". Uses the device clock - the snapshot's save time is stamped
  /// on-device, so the two agree by construction.
  String _formatAge(DateTime savedAt) {
    final elapsed = DateTime.now().difference(savedAt);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    final hours = elapsed.inHours;
    if (hours < 24) return '$hours h ago';
    return '${elapsed.inDays} d ago';
  }

  void _checkNotifications() {
    final now = DateTime.now();
    // Prune: one entry per stop x bus over a long map session otherwise
    // grows without bound.
    _lastArrivalAlert.removeWhere(
      (_, t) => now.difference(t) > const Duration(minutes: 10),
    );
    for (final point in widget.pickupPoints) {
      if (_notificationsEnabled[point.id] != true) continue;

      // Only a bus actually heading here can trigger an approach alert -
      // a bus that just left the stop used to fire one too.
      final serving = _closestServingBus(point);
      if (serving == null) continue;
      // A fix older than [_staleAfter] must not produce an "arriving" alert
      // for a bus that parked (or stopped reporting) long ago. Server clock
      // (see _freshnessNow): a wrong device clock must neither mute nor
      // spam these either.
      if (_freshnessNow().difference(serving.timestamp) >= _staleAfter) {
        continue;
      }

      final distance = serving.distanceTo(point.latitude, point.longitude);
      final eta = _etaMinutes(serving, point);

      // Notify if bus is within 0.5 km and within 5 minutes out.
      if (distance >= 0.5 || eta > 5) continue;

      // One alert per stop+bus per 10 minutes. The old code flipped the
      // toggle off locally while the server subscription stayed armed - the
      // UI lied, and reopening the map re-armed the alert - and reused the
      // stop id as the notification id, so a second bus's alert replaced
      // the first one instead of stacking.
      final key = '${point.id}:${serving.busId}';
      final last = _lastArrivalAlert[key];
      if (last != null &&
          now.difference(last) < const Duration(minutes: 10)) {
        continue;
      }
      _lastArrivalAlert[key] = now;
      _showArrivalNotification(point, eta, serving);
    }
  }

  void _showArrivalNotification(PickupPoint point, int eta, BusLocation loc) {
    NotificationService().showBusArrivalNotification(
      stopName: point.pointName,
      etaMinutes: eta,
      stopId: point.id,
      routeId: widget.route.id,
      busId: loc.busId,
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
              // Override the theme's full-width minimum (actions row).
              minimumSize: const Size(0, 40),
            ),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSOSAlert() async {
    // Captured from the builder so the spinner can ALWAYS be dismissed -
    // even if MapScreen itself is gone (a bare Navigator.pop after `await`
    // would otherwise pop whatever route sits underneath, or leave a stuck
    // spinner over an emergency flow).
    BuildContext? loadingDialog;
    showDialog(
      context: context,
      barrierDismissible: false,
      // barrierDismissible only blocks taps: the Android back button pops
      // even "non-dismissible" dialogs, silently sending the dismiss calls
      // below to the map underneath. Block it explicitly.
      builder: (context) {
        loadingDialog = context;
        return const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
    void dismissLoading() {
      final ctx = loadingDialog;
      if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
    }

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
        dismissLoading();
        if (mounted) {
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

      dismissLoading();
      // Confirmation notification as well as the snackbar - this is what
      // showSOSNotification existed for; it had no call site at all.
      unawaited(NotificationService().showSOSNotification());
      if (!mounted) return;

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
      dismissLoading();
      // Raw exception text is for the log, not for a panicking user.
      debugPrint('[nav] SOS failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send SOS. Please try again or call '
                'emergency services directly.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Saves [point] as the student's regular "my stop" and arms its
  /// bus-approaching alert (reusing the existing [stop_notifications]
  /// pipeline), so the app can open straight to this route next time and
  /// notify while the map is open. Fires once per alert window, exactly like
  /// a manually-toggled "Notify Me".
  Future<void> _setMyStop(PickupPoint point) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await MyStopStore.instance.save(
      MyStop.fromPickup(
        universityId: widget.route.universityId,
        routeId: widget.route.id,
        routeName: widget.route.routeName,
        stop: point,
      ),
    );
    if (!saved) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save your stop. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Arm the approach alert too - but only if the OS will actually deliver
    // it (same gate as the Notify Me button).
    try {
      if (await NotificationService().ensurePermission()) {
        await _service.subscribeToStopNotifications(
          point.id,
          routeId: widget.route.id,
        );
        if (mounted) {
          setState(() => _notificationsEnabled[point.id] = true);
        }
      } else {
        debugPrint(
          '[map] notification permission denied - my-stop alert not armed',
        );
      }
    } catch (e) {
      debugPrint('[map] my-stop alert subscribe failed: $e');
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('⭐ ${point.pointName} set as your stop'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showStopDetails(PickupPoint point) {
    debugPrint(
      '[stop] details: ${point.pointName} '
      '(${point.latitude},${point.longitude})',
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // This sheet is its own route and never sees the map's rebuilds, so
        // it listens to the bus-feed revision directly: the ETA/distance
        // card keeps up with every position update while the sheet is open.
        return ValueListenableBuilder<int>(
          valueListenable: _busRevision,
          builder: (context, _, _) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
            // ETA comes from a bus that is actually still serving this
            // stop (fresh, not yet past it); [live] is the freshest bus
            // either way and drives the distance fallback.
            final eta = _calculateETA(point);
            final serving = _closestServingBus(point);
            final live = _closestFreshBus(point);
            final isNotifying = _notificationsEnabled[point.id] ?? false;

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

                    // ETA card. Shown whenever a FRESH bus exists; the copy
                    // degrades honestly (ETA -> passed -> distance) instead
                    // of vanishing when a bus stops in traffic, which used
                    // to blank the card completely.
                    if (live != null)
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
                                // Flexible: the "already passed" copy at
                                // fontSize 18 exceeds the sheet's content
                                // width on small phones inside a centered
                                // Row (RenderFlex overflow).
                                Flexible(
                                  child: Text(
                                    _offlineTooOld
                                        ? 'Offline - live arrival time '
                                            'unavailable'
                                        : eta == null
                                        ? 'The last bus has already passed this stop'
                                        : eta == 0
                                        ? 'Bus is at this stop now'
                                        : 'Bus arrives in $eta minutes',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Distance: ${(serving ?? live).distanceTo(point.latitude, point.longitude).toStringAsFixed(2)} km',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // NOTIFY ME BUTTON
                    ElevatedButton.icon(
                      onPressed: () async {
                        // Capture before the awaits: `context` here belongs to
                        // the modal bottom sheet, which the user CAN dismiss
                        // while the request is in flight, so the `mounted`
                        // check below (which guards the State, not this
                        // context) is not enough on its own.
                        final messenger = ScaffoldMessenger.of(context);

                        // Toggle while the sheet is definitely still alive, so
                        // nothing has to touch `setSheetState` after the await
                        // (that throws if the sheet was closed meanwhile).
                        setState(() {
                          _notificationsEnabled[point.id] = !isNotifying;
                        });
                        setSheetState(() {});

                        try {
                          if (!isNotifying) {
                            // Gate like profile_screen does: arming an alert
                            // the OS will never deliver leaves a persisted
                            // row and a green "you'll be notified" the
                            // student cannot trust.
                            if (!await NotificationService()
                                .ensurePermission()) {
                              debugPrint(
                                '[map] notification permission denied by the '
                                'OS - not subscribing to stop ${point.id}',
                              );
                              if (mounted) {
                                setState(() {
                                  _notificationsEnabled[point.id] = false;
                                });
                              }
                              if (context.mounted) {
                                setSheetState(() {});
                              }
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Notifications are blocked — enable them '
                                    'for this app in system settings.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            await _service.subscribeToStopNotifications(
                              point.id,
                              routeId: widget.route.id,
                            );
                          } else {
                            await _service.unsubscribeFromStopNotifications(
                              point.id,
                            );
                          }
                        } catch (e) {
                          // Undo the optimistic toggle - and repaint the open
                          // sheet: a modal sheet is its own route and does NOT
                          // rebuild from the parent's setState, so without this
                          // the button kept showing the failed state ("Notify
                          // On" for an alert that was never armed). The
                          // `context.mounted` guard covers the sheet having
                          // been dismissed mid-request - calling a dead
                          // builder's setSheetState asserts.
                          if (mounted) {
                            setState(() {
                              _notificationsEnabled[point.id] = isNotifying;
                            });
                          }
                          if (context.mounted) {
                            setSheetState(() {});
                          }
                          debugPrint('[map] stop notification toggle failed: $e');
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not update notifications. Please try again.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        messenger.showSnackBar(
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

                    // In-app turn-by-turn navigation to this stop.
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startNavigation(point);
                      },
                      icon: const Icon(Icons.navigation),
                      label: const Text('Navigate here'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Remember this as the student's regular stop: next open
                    // jumps straight here and the approach alert is armed.
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _setMyStop(point);
                      },
                      icon: const Icon(Icons.star_border),
                      label: const Text('Set as my stop'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
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
      },
    );
  }

  /// Opens the native share sheet with this bus's live location as a Google
  /// Maps link, so a student can send "Bus 12 is near the next stop" to a
  /// friend on WhatsApp / SMS / whatever they use.
  Future<void> _shareBusLocation(Bus bus, BusLocation location) async {
    final link =
        'https://www.google.com/maps?q=${location.latitude},${location.longitude}';
    final text =
        'Bus ${bus.busNumber} on ${widget.route.routeName} is near '
        '${_getNextStopName(location.nextStopIndex)}: $link';
    try {
      await Share.share(text);
    } catch (e) {
      debugPrint('[map] share failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the share sheet'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                _shareBusLocation(bus, location);
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
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
    // Aged against the server-stamped clock, same as every freshness check
    // (_freshnessNow): a device minutes off used to label a stale fix "Just
    // now" (or a fresh one "12 min ago") in the bus-details dialog.
    final diff = _freshnessNow().difference(time);
    if (diff.inSeconds < 30) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds} seconds ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hours ago';
  }

  int? _calculateETA(PickupPoint point) {
    // A bus that already passed this stop (or only stale rows) must not
    // produce an ETA; see _closestServingBus.
    final serving = _closestServingBus(point);
    if (serving == null) return null;
    return _etaMinutes(serving, point);
  }

  Future<void> _getDirections(PickupPoint point) async {
    // Turn-by-turn navigation is delegated to a real maps app. The origin is
    // pinned to the user's GPS position whenever it is known, so directions
    // to every stop start from where they actually stand; the destination is
    // always this stop's own coordinates.
    final pos = _myPosition;
    final origin = pos == null
        ? ''
        : '&origin=${pos.latitude},${pos.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '$origin'
      '&destination=${point.latitude},${point.longitude}'
      // Open straight into driving turn-by-turn, not a route overview.
      '&travelmode=driving&dir_action=navigate',
    );
    debugPrint('[dirs] ${point.pointName} -> $uri');

    try {
      // externalApplication keeps the user in a navigation app instead of
      // opening an in-app browser tab. This used to only `print()` the URL,
      // which meant the button did nothing at all on a phone.
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open a maps app on this device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[dirs] launch failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open directions - is a maps app installed?',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
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
    // Zero-area bounds (one stop, or every stop on the same coordinate)
    // make CameraFit.bounds compute scale = size/0 = Infinity: flutter_map
    // asserts in debug and TileLayer throws "Infinity is not finite" in
    // release, erroring the whole map body. Center on the stop instead.
    if (widget.pickupPoints.length < 2) {
      final p = widget.pickupPoints.first;
      _mapController.move(LatLng(p.latitude, p.longitude), 16);
      return;
    }

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

    // The <2 guard above misses two (or more) stops SAVED AT THE SAME
    // COORDINATE: bounds are then zero-area too, and CameraFit.bounds would
    // divide by zero all the same. Center with a fixed zoom there.
    if (minLat == maxLat && minLng == maxLng) {
      _mapController.move(LatLng(minLat, minLng), 16);
      return;
    }

    // Google's newLatLngBounds(bounds, 50) -> CameraFit with 50px padding.
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(50),
        // Never zoom past the tile server's max on a pathologically tight
        // bounds (all stops nearly coincident but not identical).
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Single-line + ellipsis: the SOS pill and three icon actions now
            // leave ~100-140 dp for the title on narrow phones, where a long
            // route name used to wrap to 2-3 lines and blow the 56 dp
            // toolbar height. Ellipsis keeps it inside its bounded width.
            Text(
              widget.route.routeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_buses.length} ${_buses.length == 1 ? 'bus' : 'buses'} • '
              '${widget.pickupPoints.length} '
              '${widget.pickupPoints.length == 1 ? 'stop' : 'stops'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Emergency SOS - pinned in the app bar so it is always visible
          // and never buried under the map controls at the bottom of the
          // screen (the old bottom-corner FAB was easy to miss in a hurry).
          TextButton.icon(
            onPressed: _triggerSOS,
            style: TextButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.sos, size: 18),
            label: const Text(
              'SOS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 2),
          // Follow bus toggle (kept visible: used often while tracking)
          IconButton(
            icon: Icon(_followBus ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: () {
              setState(() {
                _followBus = !_followBus;
              });
            },
            tooltip: _followBus ? 'Following bus' : 'Not following',
          ),
          // Refresh button (kept visible)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBusData,
            tooltip: 'Refresh',
          ),
          // Less-frequent map actions folded into one overflow menu so the
          // bar stays uncluttered (and the title keeps room) on narrow phones.
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'fit') {
                _zoomToFitAllStops();
              } else if (value == 'stops') {
                _showStopsList();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'fit',
                child: ListTile(
                  leading: Icon(Icons.zoom_out_map),
                  title: Text('Show all stops'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'stops',
                child: ListTile(
                  leading: Icon(Icons.list),
                  title: Text('Stops list'),
                  contentPadding: EdgeInsets.zero,
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('Error: $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    // The error view used to be a dead end: a bare message
                    // with no way back, and even the AppBar refresh left
                    // `_error` set (it is only cleared on success).
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _isLoading = true;
                        });
                        _loadBusData();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
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
                        // Frame THIS route's own stop bounds instead of a
                        // fixed zoom-13 view: each route opens showing its
                        // whole path (nothing cropped at the edge) and looks
                        // distinct from the others at first glance. A saved
                        // "my stop" overrides that to open on the stop the
                        // student actually waits at.
                        final focusId = widget.initialFocusStopId;
                        PickupPoint? focus;
                        if (focusId != null) {
                          focus = widget.pickupPoints
                              .where((p) => p.id == focusId)
                              .firstOrNull;
                        }
                        if (focus != null) {
                          _centerOnStop(focus);
                        } else {
                          _zoomToFitAllStops();
                        }
                      }
                    },
                    onPositionChanged: (camera, hasGesture) {
                      // A manual pan/pinch takes priority: keep-following
                      // would snap the map straight back on the next event.
                      if (hasGesture && _followBus) {
                        setState(() => _followBus = false);
                      }
                    },
                    // Heading icons are drawn in screen space; letting the
                    // map rotate would point them off by the camera angle.
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
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
                      markers: [
                        ..._pickupMarkers,
                        ..._busMarkers,
                        ..._myLocationMarkers,
                      ],
                    ),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                  ],
                ),

                // Turn-by-turn guidance card
                if (_navigating || _navRouting)
                  Positioned(
                    // Clear of the offline strip when both are showing.
                    top: _offlineMode ? 36 : 12,
                    left: 16,
                    right: 16,
                    child: _buildNavigationBanner(),
                  ),

                // Offline banner: an honest "stale, not live" label whenever
                // the map is rendering cached bus fixes instead of the feed.
                if (_offlineMode && _offlineSnapshotAt != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      color: Colors.orange.shade800,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cloud_off,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Offline - showing last position '
                                  '${_formatAge(_offlineSnapshotAt!)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Bus count indicator (drops below the banner while guiding,
                // or below the offline strip when showing cached fixes)
                Positioned(
                  // The guidance banner is ~120 dp tall (a column of two
                  // 48 dp icon buttons), so the old 96 put the pill straight
                  // over its lower half - covering the "End navigation"
                  // button on every navigating screen. Sit 4 dp under the
                  // banner's real bottom edge instead.
                  top: (_navigating || _navRouting)
                      ? ((_offlineMode ? 36 : 12) + 124)
                      : (_offlineMode ? 40 : 16),
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

                // ETA info card. The SOS button now lives in the app bar, so
                // this card can span the full width (left/right 16). The text
                // is capped at two lines so a long stop name cannot grow the
                // card over the legend at bottom:100.
                if (_etaInfo.isNotEmpty)
                  Positioned(
                    bottom: 20,
                    left: 16,
                    // Clear of the re-centre FAB (bottom 88..136, right 16):
                    // full-width here let a 2-line ETA card slide under the
                    // FAB, which then covered the text tail.
                    right: _myPosition != null ? 80 : 16,
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
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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

                // Re-centre on the blue dot. Without this the dot can sit
                // outside the viewport - the map opens framed on the first
                // stop, which is rarely where the user is standing. Disabled
                // (greyed, non-tappable) until a first fix arrives.
                if (_myPosition != null)
                  Positioned(
                    bottom: 88,
                    right: 16,
                    child: FloatingActionButton.small(
                      // Two FABs on one route need distinct hero tags or the
                      // navigator asserts on a duplicate hero.
                      heroTag: 'recenterOnMe',
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue,
                      // Icon-only FAB: the tooltip doubles as its
                      // accessibility label.
                      tooltip: 'Center on my location',
                      onPressed: () {
                        if (!_mapReady) return;
                        final pos = _myPosition!;
                        _mapController.move(
                          LatLng(pos.latitude, pos.longitude),
                          // Never zoom out to reach the dot.
                          math.max(_mapController.camera.zoom, 16.0),
                        );
                      },
                      child: const Icon(Icons.my_location),
                    ),
                  ),

                // Legend. 140 (not 100): a 2-line ETA card's top edge reaches
                // ~120 from the bottom, so the old position was grazed by the
                // card whenever the stop name wrapped.
                Positioned(
                  bottom: 140,
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
        // Own route, so listen to the bus-feed revision: every row's ETA
        // chip keeps up with position updates while the list stays open.
        return ValueListenableBuilder<int>(
          valueListenable: _busRevision,
          builder: (context, _, _) {
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
              Flexible(
                // Flexible rather than Expanded: the sheet grows with the stop
                // list but is capped at the container's 70% height (scrollable
                // beyond it). Expanded force-stretched it to the full 70% even
                // when only three stops were listed.
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
                              label: Text(eta == 0 ? 'Here' : '$eta min'),
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
      },
    );
  }
}
