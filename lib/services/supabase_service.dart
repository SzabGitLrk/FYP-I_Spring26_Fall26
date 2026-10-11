import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/university.dart';
import '../models/route_model.dart';
import '../models/pickup_point.dart';
import '../models/bus.dart';
import '../models/bus_location.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<University>> getUniversities() async {
    try {
      final response = await _client
          .from('universities')
          .select()
          // supabase-dart's .order() defaults to DESCENDING (unlike the JS
          // client); every intentional A-Z / visit-order sort must say so.
          // This bit us: pickup points came back last-stop-first, which
          // inverted the map's first/last markers, the waypoint order sent
          // to the routers, and the driver's next_stop_index decoding.
          .order('name', ascending: true);

      return (response as List)
          .map((item) => University.fromJson(item))
          .toList();
    } catch (e) {
      throw Exception('Failed to load universities: $e');
    }
  }

  Future<List<RouteModel>> getRoutesForUniversity(int universityId) async {
    try {
      final response = await _client
          .from('routes')
          .select()
          .eq('university_id', universityId)
          .order('route_name', ascending: true);

      return (response as List)
          .map((item) => RouteModel.fromJson(item))
          .toList();
    } catch (e) {
      throw Exception('Failed to load routes: $e');
    }
  }

  Future<List<PickupPoint>> getPickupPointsForRoute(int routeId) async {
    try {
      final response = await _client
          .from('pickup_points')
          .select()
          .eq('route_id', routeId)
          // Visit order: stop 1 (first) .. stop N (last) - see the note in
          // getUniversities for the DESC default that broke this.
          .order('order_index', ascending: true);

      return (response as List)
          .map((item) => PickupPoint.fromJson(item))
          .toList();
    } catch (e) {
      throw Exception('Failed to load pickup points: $e');
    }
  }

  Future<List<Bus>> getBusesForRoute(int routeId) async {
    try {
      final response = await _client
          .from('buses')
          .select()
          .eq('route_id', routeId)
          .eq('status', 'active');

      return (response as List).map((item) => Bus.fromJson(item)).toList();
    } catch (e) {
      throw Exception('Failed to load buses: $e');
    }
  }

  Future<List<Bus>> getBusesForDriver(String driverName) async {
    try {
      final response = await _client
          .from('buses')
          .select()
          .eq('driver_name', driverName)
          .eq('status', 'active');

      return (response as List).map((item) => Bus.fromJson(item)).toList();
    } catch (e) {
      throw Exception('Failed to load buses for driver: $e');
    }
  }

  Future<List<Bus>> getAllActiveBuses() async {
    try {
      final response = await _client
          .from('buses')
          .select()
          .eq('status', 'active');

      return (response as List).map((item) => Bus.fromJson(item)).toList();
    } catch (e) {
      throw Exception('Failed to load buses: $e');
    }
  }

  /// Inserts a new trip row and returns the id the database assigned it.
  ///
  /// The id comes straight off the INSERT result - never from re-querying
  /// "my latest active trip" afterwards: a re-query can lose the race, and
  /// an orphaned older row with a NULL `start_time` sorts first under the
  /// DESC default, so End Trip would write the distance onto the WRONG
  /// trip. With the inserted id, a driver has exactly one row to close.
  Future<int> startTrip({
    required int busId,
    required String driverId,
    required int routeId,
  }) async {
    try {
      final row = await _client
          .from('trips')
          .insert({
            'bus_id': busId,
            'driver_id': driverId,
            'route_id': routeId,
            'start_time': DateTime.now().toUtc().toIso8601String(),
            'status': 'active',
          })
          .select('id')
          .single();
      return row['id'] as int;
    } catch (e) {
      throw Exception('Failed to start trip: $e');
    }
  }

  Future<void> endTrip(int tripId, double distanceKm) async {
    try {
      await _client
          .from('trips')
          .update({
            'end_time': DateTime.now().toUtc().toIso8601String(),
            'distance_km': distanceKm,
            'status': 'completed',
          })
          .eq('id', tripId);
    } catch (e) {
      throw Exception('Failed to end trip: $e');
    }
  }

  Future<void> updateBusLocation({
    required int busId,
    required double latitude,
    required double longitude,
    required double speed,
    double heading = 0.0,
    int nextStopIndex = 0,
  }) async {
    try {
      await _client.from('bus_locations').insert({
        'bus_id': busId,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'heading': heading,
        'next_stop_index': nextStopIndex,
      });
    } catch (e) {
      throw Exception('Failed to update bus location: $e');
    }
  }

  Future<List<BusLocation>> getBusLocationsForRoute(
    int routeId, {
    List<Bus>? buses,
  }) async {
    try {
      // Optional passthrough: callers that already loaded the route's buses
      // (map_screen) skip a second identical round-trip.
      final busList = buses ?? await getBusesForRoute(routeId);
      if (busList.isEmpty) return [];

      final busIds = busList.map((b) => b.id).toList();

      // Newest first, capped: `bus_locations` is an append-only log that grows
      // by one row per GPS tick of every trip ever driven. An unbounded fetch
      // would download that whole history on every map open; the 500 most
      // recent rows always cover one fix per bus.
      //
      // Ghost-bus guard on top: without an age floor, "newest row per bus"
      // for a bus that stopped reporting yesterday IS yesterday's last fix,
      // drawn live with a plausible ETA. Only the last 2 minutes count.
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 2))
          .toIso8601String();
      final response = await _client
          .from('bus_locations')
          .select()
          .inFilter('bus_id', busIds)
          .gte('timestamp', cutoff)
          .order('timestamp', ascending: false)
          .limit(500);

      final Map<int, dynamic> latestLocations = {};
      for (var loc in (response as List)) {
        final busId = loc['bus_id'] as int?;
        // Orphan row: `bus_locations.bus_id` is a nullable FK, and a row with
        // no bus has nowhere to be drawn — skip it instead of throwing.
        if (busId == null) continue;
        if (!latestLocations.containsKey(busId)) {
          latestLocations[busId] = loc;
        }
      }

      return latestLocations.values
          .map((item) => BusLocation.fromJson(item))
          .toList();
    } catch (e) {
      throw Exception('Failed to load bus locations: $e');
    }
  }

  /// Live feed of bus positions across the whole project.
  ///
  /// Supabase's `.stream()` supports `where`/`order`/`limit` but no join, and
  /// `bus_locations` carries no `route_id` column to filter on, so events
  /// still arrive for every bus. Callers MUST narrow them to their own buses
  /// (`map_screen.dart` does this against the route's bus list); the `limit`
  /// at least keeps the replayed history bounded instead of re-downloading
  /// the table's entire append-only past on every subscribe.
  ///
  /// The same 2-minute age floor as [getBusLocationsForRoute] applies: the
  /// cutoff is fixed at subscribe time (the screen's lifetime is short), and
  /// consumers re-check age before acting on a row, so an old fix can neither
  /// replay on first subscribe nor produce a phantom alert later.
  Stream<List<BusLocation>> subscribeToBusLocations() {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 2))
        .toIso8601String();
    return _client
        .from('bus_locations')
        .stream(primaryKey: ['id'])
        .gte('timestamp', cutoff)
        .order('timestamp', ascending: false)
        .limit(500)
        .map((maps) {
          return maps.map((map) => BusLocation.fromJson(map)).toList();
        });
  }

  String? _getUserId() {
    final user = _client.auth.currentUser;
    return user?.id;
  }

  /// Toggles the stop alert on for the signed-in user.
  ///
  /// [routeId] is optional: when supplied it is stored/filtered on, when
  /// omitted the write leaves `route_id` untouched (the column is nullable)
  /// so existing call sites keep their exact behavior.
  Future<void> subscribeToStopNotifications(
    int stopId, {
    int? routeId,
  }) async {
    final uid = _getUserId();
    if (uid == null) return;
    try {
      // Update first, insert only when no row exists yet - deliberately NOT
      // an `upsert()`. Without knowing whether `stop_notifications` carries a
      // UNIQUE (user_id, stop_id) constraint, upsert misbehaves on one of the
      // two possible schemas: with the constraint it falls back to the serial
      // primary key as its conflict target, so re-subscribing throws a unique
      // violation; without it, every cycle stacks another duplicate row.
      // This order needs only the INSERT and UPDATE policies the feature
      // already proves exist (subscribing and unsubscribing both work).
      final update = <String, dynamic>{
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (routeId != null) update['route_id'] = routeId;

      final existing = await _client
          .from('stop_notifications')
          .update(update)
          .eq('user_id', uid)
          .eq('stop_id', stopId)
          .select('id');

      if (existing.isEmpty) {
        final insert = <String, dynamic>{
          'user_id': uid,
          'stop_id': stopId,
          'is_active': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        if (routeId != null) insert['route_id'] = routeId;
        await _client.from('stop_notifications').insert(insert);
      }
    } catch (e) {
      throw Exception('Failed to subscribe: $e');
    }
  }

  /// Turns the stop alert off for the signed-in user.
  ///
  /// Optional [routeId] narrows the write to that route's row; omitted, it
  /// deactivates the stop for the user across routes - the original behavior.
  Future<void> unsubscribeFromStopNotifications(
    int stopId, {
    int? routeId,
  }) async {
    final uid = _getUserId();
    if (uid == null) return;
    try {
      final builder = _client
          .from('stop_notifications')
          .update({'is_active': false})
          .eq('user_id', uid)
          .eq('stop_id', stopId);
      if (routeId != null) {
        await builder.eq('route_id', routeId);
      } else {
        await builder;
      }
    } catch (e) {
      throw Exception('Failed to unsubscribe: $e');
    }
  }

  /// Which of [stopIds] the signed-in user currently has an active
  /// subscription for - one query instead of one per stop.
  ///
  /// List-based on purpose: `unsubscribe` only flips `is_active` to false and
  /// never deletes the row, so on schemas without a unique constraint the
  /// table can hold more than one row per (user, stop), and `.maybeSingle()`
  /// would throw on exactly those users. Callers decide how important the
  /// answer is - the map treats a failure as "keep the current toggle state".
  Future<Set<int>> getActiveStopNotifications(List<int> stopIds) async {
    final uid = _getUserId();
    if (uid == null || stopIds.isEmpty) return const {};

    try {
      final response = await _client
          .from('stop_notifications')
          .select('stop_id')
          .eq('user_id', uid)
          .eq('is_active', true)
          .inFilter('stop_id', stopIds);

      return (response as List)
          .map((row) => (row['stop_id'] as num).toInt())
          .toSet();
    } catch (e) {
      throw Exception('Failed to load notification preferences: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendSOSAlert({
    required String userId,
    required String userName,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client.from('sos_alerts').insert({
        'user_id': userId,
        'user_name': userName,
        'latitude': latitude,
        'longitude': longitude,
        'status': 'active',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Reports a driver-side bus problem (Fuel Empty / Bus Fault) into the
  /// `bus_issues` table the admin dashboard subscribes to live.
  ///
  /// [issueType] must be one of the two CHECK values on the column:
  /// `fuel_empty` or `bus_fault`. `created_at` is deliberately NOT sent:
  /// the column default is the SERVER's clock, so the "reported at" time
  /// dispatch sees cannot drift with a wrong device clock.
  Future<void> reportBusIssue({
    required String userId,
    required String driverName,
    required int? busId,
    required String busNumber,
    required String issueType,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client.from('bus_issues').insert({
        'user_id': userId,
        'driver_name': driverName,
        'bus_id': busId,
        'bus_number': busNumber,
        'issue_type': issueType,
        'latitude': latitude,
        'longitude': longitude,
        'status': 'active',
      });
    } catch (e) {
      throw Exception('Failed to report bus issue: $e');
    }
  }
}
