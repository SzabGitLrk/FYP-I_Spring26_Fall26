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
          .order('name');

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
          .order('route_name');

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
          .order('order_index');

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

  Future<void> startTrip({
    required int busId,
    required String driverId,
    required int routeId,
  }) async {
    try {
      await _client.from('trips').insert({
        'bus_id': busId,
        'driver_id': driverId,
        'route_id': routeId,
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'active',
      });
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

  Future<void> subscribeToStopNotifications(
    int stopId,
    int routeId,
  ) async {
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
      final existing = await _client
          .from('stop_notifications')
          .update({
            'is_active': true,
            'route_id': routeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', uid)
          .eq('stop_id', stopId)
          .select('id');

      if (existing.isEmpty) {
        await _client.from('stop_notifications').insert({
          'user_id': uid,
          'stop_id': stopId,
          'route_id': routeId,
          'is_active': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      throw Exception('Failed to subscribe: $e');
    }
  }

  Future<void> unsubscribeFromStopNotifications(int stopId) async {
    final uid = _getUserId();
    if (uid == null) return;
    try {
      await _client
          .from('stop_notifications')
          .update({'is_active': false})
          .eq('user_id', uid)
          .eq('stop_id', stopId);
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
}
