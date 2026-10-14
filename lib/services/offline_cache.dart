import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bus.dart';
import '../models/bus_location.dart';
import '../models/pickup_point.dart';

/// A cached bus-position snapshot plus when it was written, so the UI can
/// honestly say "last position 3 min ago" instead of pretending it is live.
class BusSnapshot {
  const BusSnapshot({required this.locations, required this.savedAt});

  final List<BusLocation> locations;

  /// Device clock at write time (the cache is a local convenience, so the
  /// device clock is the only clock available here - unlike the live feed,
  /// whose freshness is owned by map_screen against the SERVER fix horizon).
  final DateTime savedAt;
}

/// A cached stop list plus when it was written.
class StopSnapshot {
  const StopSnapshot({required this.points, required this.savedAt});

  final List<PickupPoint> points;
  final DateTime savedAt;
}

/// A cached bus list (the route's buses) plus when it was written. Kept
/// alongside the position snapshot so an offline map can still label markers
/// with real bus numbers and, on the next poll, auto-recover the moment
/// connectivity returns.
class BusListSnapshot {
  const BusListSnapshot({required this.buses, required this.savedAt});

  final List<Bus> buses;
  final DateTime savedAt;
}

/// Last-known data kept on disk so a dead data connection still shows a
/// useful map instead of a blank error screen.
///
/// Larkana's mobile data drops constantly. Without a cache, one failed
/// refresh blanks the buses a student was watching. This stores, per route:
///
///  * the most recent bus fixes ([saveBusSnapshot]);
///  * the stop list ([saveStopSnapshot]).
///
/// On a failed load the screens fall back to these and label them "offline"
/// with the snapshot's age - stale but honest, never a false "live".
///
/// Every operation swallows its own errors: a full disk or a corrupted entry
/// must degrade to "no cache", never crash a screen that could otherwise
/// have shown live data.
class OfflineCache {
  OfflineCache._();

  static final OfflineCache instance = OfflineCache._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static String _busKey(int routeId) => 'offline_bus_$routeId';
  static String _busListKey(int routeId) => 'offline_buslist_$routeId';
  static String _stopKey(int routeId) => 'offline_stops_$routeId';

  /// True when a non-empty snapshot is already stored for [key].
  ///
  /// An empty result is a legitimate response (the route has no location rows
  /// yet), but writing it over a good snapshot would make the next offline
  /// window find `[]` and reject it - a blank map where the honest "offline,
  /// 3 min ago" view should have rendered. So empty incoming lists never
  /// clobber existing data.
  Future<bool> _hasNonEmpty(String key) async {
    try {
      final prefs = await _ensure();
      final raw = prefs.getString(key);
      if (raw == null) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      for (final field in ['locations', 'buses', 'points']) {
        final rows = decoded[field];
        if (rows is List && rows.isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Persists the freshest [locations] for [routeId], replacing any previous
  /// snapshot. Callers pass the already-filtered, newest-per-bus list.
  Future<void> saveBusSnapshot(
    int routeId,
    List<BusLocation> locations,
  ) async {
    try {
      if (locations.isEmpty && await _hasNonEmpty(_busKey(routeId))) return;
      final prefs = await _ensure();
      await prefs.setString(
        _busKey(routeId),
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'locations': [for (final l in locations) l.toJson()],
        }),
      );
    } catch (e) {
      // A cache write is best-effort; never surface it to the UI.
      debugPrint('[offline] bus snapshot write failed: $e');
    }
  }

  /// Returns the last snapshot for [routeId], or null when none exists or the
  /// stored entry is unreadable. Decoding is per-row tolerant: one bad row is
  /// skipped rather than discarding the whole snapshot.
  Future<BusSnapshot?> loadBusSnapshot(int routeId) async {
    try {
      final prefs = await _ensure();
      final raw = prefs.getString(_busKey(routeId));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final savedAt = DateTime.tryParse(decoded['savedAt'] as String? ?? '');
      final rows = decoded['locations'];
      if (savedAt == null || rows is! List) return null;

      final locations = <BusLocation>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        try {
          locations.add(BusLocation.fromJson(row));
        } catch (_) {
          // Skip the malformed row, keep the rest.
        }
      }
      return BusSnapshot(locations: locations, savedAt: savedAt);
    } catch (e) {
      debugPrint('[offline] bus snapshot read failed: $e');
      return null;
    }
  }

  /// Persists the route's bus list for [routeId], replacing any previous
  /// snapshot. Stored with the position snapshot so an offline map can label
  /// markers and auto-recover on the next poll.
  Future<void> saveBusListSnapshot(int routeId, List<Bus> buses) async {
    try {
      if (buses.isEmpty && await _hasNonEmpty(_busListKey(routeId))) return;
      final prefs = await _ensure();
      await prefs.setString(
        _busListKey(routeId),
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'buses': [for (final b in buses) b.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('[offline] bus-list snapshot write failed: $e');
    }
  }

  /// Returns the last bus list for [routeId], or null when none exists or it
  /// is unreadable. Same per-row tolerance as [loadBusSnapshot].
  Future<BusListSnapshot?> loadBusListSnapshot(int routeId) async {
    try {
      final prefs = await _ensure();
      final raw = prefs.getString(_busListKey(routeId));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final savedAt = DateTime.tryParse(decoded['savedAt'] as String? ?? '');
      final rows = decoded['buses'];
      if (savedAt == null || rows is! List) return null;

      final buses = <Bus>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        try {
          buses.add(Bus.fromJson(row));
        } catch (_) {
          // Skip the malformed row, keep the rest.
        }
      }
      return BusListSnapshot(buses: buses, savedAt: savedAt);
    } catch (e) {
      debugPrint('[offline] bus-list snapshot read failed: $e');
      return null;
    }
  }

  /// Persists the stop list for [routeId], replacing any previous snapshot.
  Future<void> saveStopSnapshot(
    int routeId,
    List<PickupPoint> points,
  ) async {
    try {
      if (points.isEmpty && await _hasNonEmpty(_stopKey(routeId))) return;
      final prefs = await _ensure();
      await prefs.setString(
        _stopKey(routeId),
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'points': [for (final p in points) p.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('[offline] stop snapshot write failed: $e');
    }
  }

  /// Returns the last stop list for [routeId], or null when none exists or it
  /// is unreadable. Same per-row tolerance as [loadBusSnapshot].
  Future<StopSnapshot?> loadStopSnapshot(int routeId) async {
    try {
      final prefs = await _ensure();
      final raw = prefs.getString(_stopKey(routeId));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final savedAt = DateTime.tryParse(decoded['savedAt'] as String? ?? '');
      final rows = decoded['points'];
      if (savedAt == null || rows is! List) return null;

      final points = <PickupPoint>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        try {
          points.add(PickupPoint.fromJson(row));
        } catch (_) {
          // Skip the malformed row, keep the rest.
        }
      }
      return StopSnapshot(points: points, savedAt: savedAt);
    } catch (e) {
      debugPrint('[offline] stop snapshot read failed: $e');
      return null;
    }
  }
}
