import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../navigation/route_step.dart';

/// A routed trip: real road geometry plus turn-by-turn steps.
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.steps,
    required this.source,
  });

  /// The road polyline, in visit order.
  final List<LatLng> points;

  /// Turn-by-turn steps along [points] (may be empty if a router returned
  /// geometry without maneuvers).
  final List<RouteStep> steps;

  /// Which router answered: 'OSRM' or 'Valhalla'.
  final String source;
}

/// Fetches real road geometry between waypoints from keyless public routers.
///
/// This is the fix for "the map draws straight lines instead of the real
/// route": connecting pickup points directly cuts across buildings and
/// fields, so the actual driving path is requested instead. Two routers are
/// tried in order:
///
/// 1. OSRM's public demo (`router.project-osrm.org`) - GeoJSON off the wire.
/// 2. Valhalla's public OSM instance (`valhalla1.openstreetmap.de`) - an
///    encoded polyline, decoded here.
///
/// Neither needs an API key nor a billing account - the same constraint
/// that ruled out Google Maps elsewhere in this app. Every step logs with a
/// `[route]` prefix, so `adb logcat -s flutter:I` shows exactly which router
/// answered and what came back when a device draws the straight fallback.
///
/// Returns null only when *every* router fails (offline, rate limited, no
/// drivable path); the caller then keeps its straight placeholder on screen.
class RouteService {
  /// Identifies these requests to the shared public routers: their usage
  /// policies ask for a real User-Agent (with contact info), not the default
  /// `Dart/<version>` string. The contact points at the project repository
  /// (no personal email is published with every request).
  static const String _userAgent =
      'UniversityPointLocator/1.0 (university final-year student project; '
      'contact=https://github.com/SzabGitLrk/FYP-I_Spring26_Fall26)';

  /// Public demo routers occasionally hang; fail over fast. Serial worst
  /// case is now 6 s + 8 s = 14 s instead of 27 s.
  static const Duration _osrmTimeout = Duration(seconds: 6);
  static const Duration _valhallaTimeout = Duration(seconds: 8);

  /// How long a cached route stays valid - long enough to cover a student
  /// opening the map, starting guidance, ending it and reopening it.
  static const Duration _cacheTtl = Duration(minutes: 15);

  /// Hard cap on cached routes; the oldest entry is evicted first.
  static const int _cacheMaxEntries = 32;

  /// Successful routes keyed by [_cacheKey]. STATIC because production call
  /// sites construct a fresh [RouteService] per fetch - an instance field
  /// would never hit the cache in practice.
  static final Map<String, _RouteCacheEntry> _cache = {};

  /// [client] is injected by tests; production call sites omit it and keep
  /// the one-shot `http.get` behaviour (no pooled client to outlive).
  ///
  /// With an injected client the response cache is bypassed: the test suite
  /// pins per-call request counts and the OSRM-before-Valhalla ordering,
  /// which a shared cache would short-circuit.
  RouteService({http.Client? client})
    : _client = client,
      _cacheEnabled = client == null;

  final http.Client? _client;

  /// Whether [fetchRoute] may read from and write to the shared cache.
  final bool _cacheEnabled;

  /// GET [uri] with the identifying User-Agent, via the injected client
  /// when one was supplied.
  Future<http.Response> _get(Uri uri) {
    const headers = {'User-Agent': _userAgent};
    final client = _client;
    return client == null
        ? http.get(uri, headers: headers)
        : client.get(uri, headers: headers);
  }

  Future<RoadRoute?> fetchRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;

    // Identical geometry (map open / nav start / nav end / reroute over the
    // same waypoints) is served from cache instead of another 6-14 s serial
    // trip to the keyless public demo routers.
    final cacheKey = _cacheEnabled ? _cacheKey(waypoints) : null;
    if (cacheKey != null) {
      final hit = _readCache(cacheKey);
      if (hit != null) {
        debugPrint('[route] cache hit (${hit.source}) - no network round-trip');
        return hit;
      }
    }

    debugPrint('[route] fetching road geometry for ${waypoints.length} waypoints');

    final osrm = await _fetchOsrm(waypoints);
    final route = osrm ?? await _fetchValhalla(waypoints);
    if (route != null && cacheKey != null) _writeCache(cacheKey, route);
    return route;
  }

  /// Meters from [point] to the nearest drivable road, via OSRM's `/nearest`
  /// snap.
  ///
  /// Used by the admin stop editor to catch a stop dropped in a field or on
  /// the wrong side of the city (the "Qamber" bug) before it can be saved.
  /// Returns null when the router is unreachable or the answer is unusable -
  /// the editor then shows "check unavailable" rather than a false reading.
  Future<double?> nearestRoadDistanceMeters(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/nearest/v1/driving/'
        '${point.longitude},${point.latitude}?number=1',
      );
      final response = await _get(uri).timeout(_osrmTimeout);
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final waypoints = decoded['waypoints'];
      if (waypoints is! List || waypoints.isEmpty) return null;
      final first = waypoints.first;
      if (first is! Map<String, dynamic>) return null;
      final distance = first['distance'];
      if (distance is! num) return null;
      return distance.toDouble();
    } catch (e) {
      debugPrint('[route] nearest-road lookup failed: $e');
      return null;
    }
  }

  /// Normalized cache key for [waypoints]: coordinates on a ~1 m grid (5
  /// decimals), so identical stop lists hit while live GPS positions (which
  /// change every fix) do not - plus the request options, which are fixed
  /// today but must be part of the key if they ever vary.
  static String _cacheKey(List<LatLng> waypoints) {
    final normalized = waypoints
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(5)},'
              '${p.longitude.toStringAsFixed(5)}',
        )
        .join(';');
    // costing=driving (OSRM) / auto (Valhalla), overview=full, steps=true -
    // every option the service requests today.
    return 'driving/overview=full/steps=true|$normalized';
  }

  /// Cache read honoring [_cacheTtl]; expired entries are dropped on sight.
  static RoadRoute? _readCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return entry.route;
  }

  /// Cache write with simple oldest-first eviction at [_cacheMaxEntries].
  static void _writeCache(String key, RoadRoute route) {
    if (_cache.length >= _cacheMaxEntries) {
      _cache.remove(_cache.keys.first); // Map iterates in insertion order.
    }
    _cache[key] = _RouteCacheEntry(route, DateTime.now());
  }

  Future<RoadRoute?> _fetchOsrm(List<LatLng> waypoints) async {
    // Routers address waypoints GeoJSON-style: [longitude, latitude] - the
    // reverse of Flutter's LatLng - joined by ';' in visit order.
    final path = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$path'
        '?overview=full&geometries=geojson&steps=true',
      );
      final response = await _get(uri).timeout(_osrmTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          '[route] OSRM: HTTP ${response.statusCode} - ${_bodySnippet(response.body)}',
        );
        return null;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['code'] != 'Ok') {
        debugPrint(
          '[route] OSRM: 200 but no usable route - ${_bodySnippet(response.body)}',
        );
        return null;
      }

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        debugPrint('[route] OSRM: 200 with an empty route list');
        return null;
      }

      final route = routes.first;
      if (route is! Map<String, dynamic>) return null;
      final points = _osrmPoints(route);
      if (points == null || points.length < 2) {
        debugPrint('[route] OSRM: route without usable geometry');
        return null;
      }
      return RoadRoute(
        points: points,
        steps: RouteStep.fromOsrmRoute(route),
        source: 'OSRM',
      );
    } catch (e) {
      debugPrint('[route] OSRM: failed - $e');
      return null;
    }
  }

  Future<RoadRoute?> _fetchValhalla(List<LatLng> waypoints) async {
    try {
      final uri = Uri.https('valhalla1.openstreetmap.de', '/route', {
        'json': jsonEncode({
          'locations': [
            for (final p in waypoints) {'lat': p.latitude, 'lon': p.longitude},
          ],
          'costing': 'auto',
          'directions_options': {'units': 'kilometers'},
        }),
      });
      final response = await _get(uri).timeout(_valhallaTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          '[route] Valhalla: HTTP ${response.statusCode} - ${_bodySnippet(response.body)}',
        );
        return null;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final trip = decoded['trip'];
      if (trip is! Map<String, dynamic>) {
        debugPrint(
          '[route] Valhalla: 200 but no trip - ${_bodySnippet(response.body)}',
        );
        return null;
      }

      final points = _valhallaPoints(trip);
      if (points == null || points.length < 2) {
        debugPrint('[route] Valhalla: trip without usable geometry');
        return null;
      }
      return RoadRoute(
        points: points,
        steps: RouteStep.fromValhallaTrip(trip),
        source: 'Valhalla',
      );
    } catch (e) {
      debugPrint('[route] Valhalla: failed - $e');
      return null;
    }
  }

  /// OSRM route geometry -> points, or null when malformed.
  static List<LatLng>? _osrmPoints(Map<String, dynamic> route) {
    // GeoJSON shape: routes[0].geometry.coordinates -> [[lon, lat], ...].
    // (An earlier version read a top-level `coordinates` key that OSRM never
    // sends, so every OSRM answer looked unusable and only the Valhalla
    // fallback ever drew a route.)
    final geometry = route['geometry'];
    if (geometry is! Map<String, dynamic>) return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;

    final points = <LatLng>[];
    for (final coordinate in coordinates) {
      if (coordinate is! List || coordinate.length < 2) return null;
      points.add(
        // GeoJSON position: [lon, lat].
        LatLng(
          (coordinate[1] as num).toDouble(),
          (coordinate[0] as num).toDouble(),
        ),
      );
    }
    return points;
  }

  /// Valhalla trip geometry -> points across every leg, or null.
  static List<LatLng>? _valhallaPoints(Map<String, dynamic> trip) {
    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) return null;

    final points = <LatLng>[];
    for (final leg in legs) {
      final shape = leg is Map<String, dynamic> ? leg['shape'] : null;
      if (shape is! String) return null;
      points.addAll(_decodeValhallaPolyline(shape));
    }
    return points.length >= 2 ? points : null;
  }

  /// Decodes an encoded polyline (precision 1e-6, signed deltas - the format
  /// Valhalla ships its route shape in) into map points.
  static List<LatLng> _decodeValhallaPolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      var byte = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      result = 0;
      shift = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e6, lng / 1e6));
    }
    return points;
  }

  /// First bytes of an error body on one line - enough to recognise the
  /// responder (rate-limit page, proxy block, router error object, ...).
  static String _bodySnippet(String body) {
    final clipped = body.length > 120 ? body.substring(0, 120) : body;
    return clipped.replaceAll(RegExp(r'\s+'), ' ');
  }
}

/// One cached route plus the instant it was stored, so [_readCache] can
/// expire it after [_cacheTtl].
class _RouteCacheEntry {
  const _RouteCacheEntry(this.route, this.storedAt);

  final RoadRoute route;
  final DateTime storedAt;
}
