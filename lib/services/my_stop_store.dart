import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pickup_point.dart';

/// A student's regular stop, remembered so the app can open straight to its
/// route and arm the bus-approaching alert without re-picking every morning.
class MyStop {
  const MyStop({
    required this.universityId,
    required this.routeId,
    required this.routeName,
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  final int universityId;
  final int routeId;
  final String routeName;
  final int stopId;
  final String stopName;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
        'universityId': universityId,
        'routeId': routeId,
        'routeName': routeName,
        'stopId': stopId,
        'stopName': stopName,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory MyStop.fromJson(Map<String, dynamic> json) => MyStop(
        universityId: json['universityId'] as int,
        routeId: json['routeId'] as int,
        routeName: json['routeName'] as String,
        stopId: json['stopId'] as int,
        stopName: json['stopName'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );

  /// Builds the record from a route context + a picked stop.
  factory MyStop.fromPickup({
    required int universityId,
    required int routeId,
    required String routeName,
    required PickupPoint stop,
  }) => MyStop(
        universityId: universityId,
        routeId: routeId,
        routeName: routeName,
        stopId: stop.id,
        stopName: stop.pointName,
        latitude: stop.latitude,
        longitude: stop.longitude,
      );
}

/// Persists the signed-in student's "my stop" on device (shared_preferences).
///
/// Deliberately local-only: it is a convenience pointer, not account data, so
/// it survives app restarts and works offline without a network round-trip.
/// The key is scoped to the signed-in user id: without that, student A's saved
/// stop would show up on the home card of student B who signs in later on the
/// same phone, and B could navigate straight to A's route. Unauthenticated
/// callers see/store nothing (the store is only reachable when signed in).
/// All operations swallow errors - a full or corrupted entry just means "no
/// saved stop", never a crash.
class MyStopStore {
  MyStopStore._();

  static final MyStopStore instance = MyStopStore._();

  static const String _keyPrefix = 'my_stop_v1_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Per-user key, or null when nobody is signed in.
  String? _key() {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      return uid == null ? null : '$_keyPrefix$uid';
    } catch (e) {
      // Supabase not initialized (e.g. unit tests) - treat as signed out.
      debugPrint('[mystop] auth lookup failed: $e');
      return null;
    }
  }

  Future<bool> save(MyStop stop) async {
    try {
      final key = _key();
      if (key == null) return false;
      final prefs = await _ensure();
      return await prefs.setString(key, jsonEncode(stop.toJson()));
    } catch (e) {
      debugPrint('[mystop] save failed: $e');
      return false;
    }
  }

  Future<MyStop?> load() async {
    try {
      final key = _key();
      if (key == null) return null;
      final prefs = await _ensure();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return MyStop.fromJson(decoded);
    } catch (e) {
      debugPrint('[mystop] load failed: $e');
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final key = _key();
      if (key == null) return;
      final prefs = await _ensure();
      await prefs.remove(key);
    } catch (e) {
      debugPrint('[mystop] clear failed: $e');
    }
  }
}
