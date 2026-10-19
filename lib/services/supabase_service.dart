import 'package:flutter/foundation.dart';
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
          .eq('status', 'active')
          .order('bus_number', ascending: true);

      return (response as List).map((item) => Bus.fromJson(item)).toList();
    } catch (e) {
      throw Exception('Failed to load buses: $e');
    }
  }

  /// Active buses assigned to ANY of [driverNames].
  ///
  /// The driver passes both name sources - the signup `user_metadata` name
  /// and the canonical `profiles.name`. An admin assigns by profiles.name,
  /// so a driver whose metadata drifted (a dashboard edit, a rename synced
  /// to only one side) would otherwise read as "no bus is assigned to your
  /// name" even though the row exists.
  Future<List<Bus>> getBusesForDriver(List<String> driverNames) async {
    final names = driverNames.where((n) => n.isNotEmpty).toSet().toList();
    if (names.isEmpty) return [];
    try {
      final response = await _client
          .from('buses')
          .select()
          .inFilter('driver_name', names)
          .eq('status', 'active')
          .order('bus_number', ascending: true);

      return (response as List).map((item) => Bus.fromJson(item)).toList();
    } catch (e) {
      throw Exception('Failed to load buses for driver: $e');
    }
  }

  /// The signed-in user's `profiles.name` - best effort, `null` on any
  /// failure (offline, profile row not created yet). It is only ever an
  /// EXTRA bus-assignment match key, so it must never fail the load.
  Future<String?> getMyProfileName() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row =
          await _client.from('profiles').select('name').eq('id', uid).maybeSingle();
      final name = row?['name'];
      return name is String && name.isNotEmpty ? name : null;
    } catch (e) {
      debugPrint('[driver] profile-name fallback failed: $e');
      return null;
    }
  }

  Future<List<Bus>> getAllActiveBuses() async {
    try {
      final response = await _client
          .from('buses')
          .select()
          .eq('status', 'active')
          .order('bus_number', ascending: true);

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
      // Row-verified: PostgREST answers 204 for a write that affected ZERO
      // rows, and "Trips update" RLS (auth.uid() = driver_id) filters the
      // row out when the session is already gone - that silent no-op used
      // to report success while the trip stayed "active" with no distance.
      // Callers now see the failure and can retry (or the 12-hour reap
      // closes the row later).
      final updated = await _client
          .from('trips')
          .update({
            'end_time': DateTime.now().toUtc().toIso8601String(),
            'distance_km': distanceKm,
            'status': 'completed',
          })
          .eq('id', tripId)
          .select('id');
      if (updated.isEmpty) {
        throw StateError('end trip affected no rows');
      }
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
      // No age floor HERE on purpose: `timestamp` is stamped by the SERVER,
      // and a device-clock cutoff silently emptied the map whenever the
      // phone's clock ran minutes ahead. Freshness is owned by map_screen,
      // which ages rows against the newest server fix seen - one clock, no
      // skew (ghost-bus protection lives there too, in _freshnessNow /
      // _ageOutStaleBuses).
      final response = await _client
          .from('bus_locations')
          .select()
          .inFilter('bus_id', busIds)
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
  /// No age filter here either - on a `.stream()` the same predicate is
  /// ALSO passed to the realtime channel as a server-side filter, so a
  /// device-clock cutoff didn't just empty the first replay: it dropped
  /// every live event while the clock was wrong. Consumers age rows on the
  /// server clock instead (map_screen's fix horizon, see _freshnessNow).
  Stream<List<BusLocation>> subscribeToBusLocations() {
    return _client
        .from('bus_locations')
        .stream(primaryKey: ['id'])
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
  /// Serializes stop-notification writes for the same (user, stop, route).
  ///
  /// `stop_notifications` has no UNIQUE (user_id, stop_id) constraint, so two
  /// concurrent writes (double-tap, map + profile toggling at once) can both
  /// observe "no row exists" and both insert - stacking duplicates. Chaining
  /// them in-process closes that window; [unsubscribeFromStopNotifications]
  /// shares the key so an on/off race also serializes.
  static final Map<String, Future<void>> _notifWriteChains = {};

  Future<T> _serializedNotifWrite<T>(
    String key,
    Future<T> Function() action,
  ) {
    final previous = _notifWriteChains[key] ?? Future<void>.value();
    final run = previous.then((_) => action());
    final tail = run.then((_) {}, onError: (_) {});
    _notifWriteChains[key] = tail;
    return run.whenComplete(() {
      // Drop the entry once this run is the tail, so the map stays bounded.
      if (identical(_notifWriteChains[key], tail)) {
        _notifWriteChains.remove(key);
      }
    });
  }

  /// so existing call sites keep their exact behavior.
  Future<void> subscribeToStopNotifications(
    int stopId, {
    int? routeId,
  }) async {
    final uid = _getUserId();
    // Honest failure instead of a silent no-op: callers show "enabled" over
    // the return value, and a signed-out write that does nothing must not
    // claim otherwise. Both callers surface this through their catch blocks.
    if (uid == null) throw StateError('Not signed in');
    try {
      // Update first, insert only when no row exists yet - deliberately NOT
      // an `upsert()`. Without knowing whether `stop_notifications` carries a
      // UNIQUE (user_id, stop_id) constraint, upsert misbehaves on one of the
      // two possible schemas: with the constraint it falls back to the serial
      // primary key as its conflict target, so re-subscribing throws a unique
      // violation; without it, every cycle stacks another duplicate row.
      // This order needs only the INSERT and UPDATE policies the feature
      // already proves exist (subscribing and unsubscribing both work).
      await _serializedNotifWrite('$uid:$stopId:${routeId ?? -1}', () async {
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
          try {
            await _client.from('stop_notifications').insert(insert);
          } catch (e) {
            // A UNIQUE (user_id, stop_id) row can land between our update and
            // this insert (second device, or a future constrained schema).
            // The desired end state - one active row - is then already true,
            // so flip it on instead of surfacing an error over a toggle that
            // actually succeeded.
            final retry = <String, dynamic>{
              'is_active': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            };
            if (routeId != null) retry['route_id'] = routeId;
            final recovered = await _client
                .from('stop_notifications')
                .update(retry)
                .eq('user_id', uid)
                .eq('stop_id', stopId)
                .select('id');
            if (recovered.isEmpty) {
              // Not a conflict after all - surface the original failure.
              rethrow;
            }
          }
        }
      });
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
    if (uid == null) throw StateError('Not signed in');
    try {
      await _serializedNotifWrite('$uid:$stopId:${routeId ?? -1}', () async {
        final builder = _client
            .from('stop_notifications')
            .update({'is_active': false})
            .eq('user_id', uid)
            .eq('stop_id', stopId);
        // PostgREST answers 204 for a zero-row write (RLS filter, expired
        // session, row already gone) - verifying the affected ids keeps the
        // service's contract that a "turned off" report means the server
        // really changed, so the UI's "🔕 Notifications turned off" cannot
        // lie while a row stays is_active = true.
        final rows = routeId != null
            ? await builder.eq('route_id', routeId).select('id')
            : await builder.select('id');
        if ((rows as List).isEmpty) {
          throw StateError('no subscription row to turn off');
        }
      });
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
          .map((row) => (row['stop_id'] as num?)?.toInt())
          .whereType<int>()
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

  /// Historical cruise speed for [routeId]: the average `speed` (km/h) of
  /// this route's buses while genuinely moving, from the most recent fixes.
  ///
  /// Calibrates ETA instead of a fixed 20 km/h floor - a route whose buses
  /// really average 30 km/h gets tighter ETAs than one through congested
  /// streets. Returns null when there is not enough moving-sample history
  /// yet (a fresh route), so callers keep the fixed floor: calibration only
  /// ever improves on the heuristic, never makes it worse. The average is
  /// clamped to a sane urban band so one bad batch cannot mint a 1-minute
  /// ETA.
  Future<double?> getRouteCruiseSpeedKmh(int routeId) async {
    try {
      final busList = await getBusesForRoute(routeId);
      if (busList.isEmpty) return null;
      final busIds = busList.map((b) => b.id).toList();

      final response = await _client
          .from('bus_locations')
          .select('speed')
          .inFilter('bus_id', busIds)
          .order('timestamp', ascending: false)
          .limit(200);

      var sum = 0.0;
      var count = 0;
      for (final row in (response as List)) {
        final speed = (row['speed'] as num?)?.toDouble() ?? 0;
        // Moving samples only: a bus idling at a terminal would drag the
        // "cruise" speed down to near zero and inflate every ETA.
        if (speed > 5) {
          sum += speed;
          count++;
        }
      }
      // Too few moving samples is noise, not a calibration.
      if (count < 5) return null;
      final average = sum / count;
      return average.clamp(15.0, 45.0).toDouble();
    } catch (e) {
      // Calibration is a bonus; never let it break the map.
      debugPrint('[map] cruise-speed lookup failed: $e');
      return null;
    }
  }

  /// Creates or updates a route stop and returns the stored row.
  ///
  /// Powers the admin stop editor (drop-a-pin on the map). [id] null creates
  /// a row, non-null updates that one. [orderIndex] is the 1-based visit
  /// position. Writes need an admin RLS policy on `pickup_points` (see
  /// `supabase_admin_stops.sql`); a non-admin session fails loudly via the
  /// returned row being empty.
  Future<PickupPoint> upsertPickupPoint({
    required int routeId,
    int? id,
    required String pointName,
    required double latitude,
    required double longitude,
    String? address,
    String? landmark,
    required int orderIndex,
    int? estimatedTimeFromPrevious,
  }) async {
    final row = <String, dynamic>{
      'route_id': routeId,
      'point_name': pointName,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'landmark': landmark,
      'order_index': orderIndex,
      'estimated_time_from_previous': estimatedTimeFromPrevious,
    };
    try {
      final Map<String, dynamic> saved;
      if (id == null) {
        saved = await _client
            .from('pickup_points')
            .insert(row)
            .select()
            .single();
      } else {
        saved = await _client
            .from('pickup_points')
            .update(row)
            .eq('id', id)
            .select()
            .single();
      }
      return PickupPoint.fromJson(saved);
    } catch (e) {
      // A zero-row update (RLS filtered it out, or the stop is gone) makes
      // `.single()` throw - honest failure instead of a false "saved".
      throw Exception('Failed to save stop: $e');
    }
  }

  /// Deletes a stop by id. Row-verified: a zero-row delete (already gone, or
  /// RLS filtered it) throws instead of silently reporting success.
  Future<void> deletePickupPoint(int id) async {
    try {
      final deleted = await _client
          .from('pickup_points')
          .delete()
          .eq('id', id)
          .select('id');
      if (deleted.isEmpty) {
        throw StateError('delete stop affected no rows');
      }
    } catch (e) {
      throw Exception('Failed to delete stop: $e');
    }
  }

  Future<void> sendSOSAlert({
    required String userId,
    required String userName,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // `created_at` is deliberately NOT sent: the column default is the
      // SERVER's clock (same contract bus_issues documents), so dispatch's
      // "reported at" ordering cannot be scrambled by a wrong device clock.
      await _client.from('sos_alerts').insert({
        'user_id': userId,
        'user_name': userName,
        'latitude': latitude,
        'longitude': longitude,
        'status': 'active',
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
