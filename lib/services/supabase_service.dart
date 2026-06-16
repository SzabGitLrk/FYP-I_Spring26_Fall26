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
        'start_time': DateTime.now().toIso8601String(),
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
            'end_time': DateTime.now().toIso8601String(),
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

  Future<List<BusLocation>> getBusLocationsForRoute(int routeId) async {
    try {
      final buses = await getBusesForRoute(routeId);
      if (buses.isEmpty) return [];

      final busIds = buses.map((b) => b.id).toList();

      final response = await _client
          .from('bus_locations')
          .select()
          .inFilter('bus_id', busIds)
          .order('timestamp', ascending: false);

      final Map<int, dynamic> latestLocations = {};
      for (var loc in (response as List)) {
        final busId = loc['bus_id'] as int;
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

  Stream<List<BusLocation>> subscribeToBusLocations(int routeId) {
    return _client
        .from('bus_locations')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: false)
        .map((maps) {
          return maps.map((map) => BusLocation.fromJson(map)).toList();
        });
  }

  Future<void> simulateBusMovement(
    int busId,
    List<PickupPoint> routePoints,
  ) async {
    for (var i = 0; i < routePoints.length; i++) {
      final point = routePoints[i];

      await _client.from('bus_locations').insert({
        'bus_id': busId,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'speed': 25.0,
        'heading': 45.0,
        'next_stop_index': i + 1,
      });

      await Future.delayed(const Duration(seconds: 3));
    }
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
      await _client.from('stop_notifications').upsert({
        'user_id': uid,
        'stop_id': stopId,
        'route_id': routeId,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
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

  Future<bool> isSubscribedToStop(int stopId) async {
    final uid = _getUserId();
    if (uid == null) return false;
    try {
      final response = await _client
          .from('stop_notifications')
          .select('is_active')
          .eq('user_id', uid)
          .eq('stop_id', stopId)
          .maybeSingle();

      return response != null && response['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> testConnection() async {
    try {
      await _client.from('universities').select().limit(1);
      return true;
    } catch (e) {
      return false;
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
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      rethrow;
    }
  }
}
