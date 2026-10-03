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
  /// `Dart/<version>` string.
  static const String _userAgent =
      'UniversityPointLocator/1.0 (university final-year student project)';

  Future<RoadRoute?> fetchRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;
    debugPrint('[route] fetching road geometry for ${waypoints.length} waypoints');

    final osrm = await _fetchOsrm(waypoints);
    if (osrm != null) return osrm;

    return _fetchValhalla(waypoints);
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
      final response = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
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
      final response = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));
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
    final coordinates = route['coordinates'];
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
