import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Map-matching for display: snaps a raw GPS fix onto a route line when the
/// fix is genuinely close to it.
///
/// GPS on a phone in a city wanders off the drawn road (tree cover, alleys,
/// multi-storey buildings), which reads to a watcher as "the bus left the
/// route" even though it is still on the road it is supposed to be on.
/// Real tracking apps map-match the marker for exactly this reason.
///
/// The contract is honest on purpose:
///   - within [maxDistanceMeters] of the line -> the closest point ON the
///     line is returned (the bus is on-route, drawn on the road);
///   - beyond it -> the ORIGINAL point is returned unchanged (a real detour
///     or a bad fix is shown where it actually is, never faked onto the
///     route). Distances, ETAs and arrival logic always use the raw fix —
///     this function only moves the drawn marker.
///
/// Geometry: a local flat-earth (equirectangular) projection around
/// [point], where one degree of latitude is 111 320 m and one degree of
/// longitude is that scaled by cos(latitude). At city scale the distortion
/// is far below GPS accuracy, and it avoids a haversine per candidate
/// segment — this runs for every bus on every feed update.
LatLng snapToRoute(
  LatLng point,
  List<LatLng> route,
  double maxDistanceMeters,
) {
  // Degenerate geometry: nothing to snap onto (or a pointless request).
  if (route.length < 2 || maxDistanceMeters <= 0) return point;

  const double metersPerDegreeLat = 111320.0;
  final double metersPerDegreeLon =
      metersPerDegreeLat * math.cos(point.latitude * math.pi / 180.0);

  // The search point is the origin of the local plane: (0, 0).
  double bestDistanceSquared = double.infinity;
  LatLng bestPoint = point;

  for (var i = 0; i < route.length - 1; i++) {
    final LatLng a = route[i];
    final LatLng b = route[i + 1];

    // Segment endpoints in local metres relative to the search point.
    final double ax = (a.longitude - point.longitude) * metersPerDegreeLon;
    final double ay = (a.latitude - point.latitude) * metersPerDegreeLat;
    final double bx = (b.longitude - point.longitude) * metersPerDegreeLon;
    final double by = (b.latitude - point.latitude) * metersPerDegreeLat;

    final double dx = bx - ax;
    final double dy = by - ay;
    final double segmentLengthSquared = dx * dx + dy * dy;

    // Parameter t of the projection of (0, 0) onto the segment, clamped to
    // [0, 1] so the result lands ON the segment, not on its infinite line.
    // A zero-length segment keeps t = 0 (the projection is the endpoint).
    double t = 0;
    if (segmentLengthSquared > 0) {
      t = -(ax * dx + ay * dy) / segmentLengthSquared;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
    }

    final double px = ax + t * dx;
    final double py = ay + t * dy;
    final double distanceSquared = px * px + py * py;

    if (distanceSquared < bestDistanceSquared) {
      bestDistanceSquared = distanceSquared;
      bestPoint = LatLng(
        point.latitude + py / metersPerDegreeLat,
        point.longitude + px / metersPerDegreeLon,
      );
    }
  }

  if (bestDistanceSquared > maxDistanceMeters * maxDistanceMeters) {
    return point; // Genuinely off-route: shown honestly where it is.
  }
  return bestPoint;
}
