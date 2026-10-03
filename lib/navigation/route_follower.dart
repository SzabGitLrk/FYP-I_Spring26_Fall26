import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'route_step.dart';

/// Straight-line distance between two coordinates in meters.
///
/// latlong2's [Distance] gives the great-circle distance - accurate enough
/// at city scale and the metric stop-proximity checks run on.
double distanceMeters(LatLng a, LatLng b) => const Distance().distance(a, b);

/// Where the user currently is relative to the route.
class RouteProgress {
  const RouteProgress({
    required this.distanceAlong,
    required this.remainingMeters,
    required this.nextStepIndex,
    required this.distanceToManeuver,
    required this.distanceOffRoute,
    required this.arrived,
  });

  /// Meters traveled from the first route point to the user's closest
  /// projection onto the route.
  final double distanceAlong;

  /// Meters from that projection to the end of the route.
  final double remainingMeters;

  /// Index into [RouteFollower.steps] of the next maneuver to perform.
  final int nextStepIndex;

  /// Meters from the user to [RouteFollower.steps]' [nextStepIndex] point.
  final double distanceToManeuver;

  /// Meters between the user and the closest point on the route - the
  /// off-route signal for rerouting.
  final double distanceOffRoute;

  /// True once the user is near the end of the route and not far off it.
  final bool arrived;
}

/// Follows a GPS position along a fixed route polyline and turns it into
/// navigation state: progress, distance to the next maneuver, off-route
/// detection and arrival.
///
/// Pure Dart (no Flutter dependencies) so the geometry can be unit-tested.
/// Positions are projected with a local flat-earth approximation: over the
/// few kilometers a campus route spans, the error stays well under a meter.
class RouteFollower {
  RouteFollower({
    required List<LatLng> points,
    required List<RouteStep> steps,
    this.arrivalRadius = 30,
    this.offRouteThreshold = 45,
    this.stepAdvanceBefore = 15,
  }) : points = List<LatLng>.unmodifiable(points),
       steps = List<RouteStep>.unmodifiable(steps) {
    // Cumulative distance at each route vertex, so any projection can be
    // converted to "meters from the start".
    final cumulative = <double>[0];
    for (var i = 1; i < this.points.length; i++) {
      cumulative.add(
        cumulative.last + _segmentMeters(this.points[i - 1], this.points[i]),
      );
    }
    _cumulative = cumulative;
    _total = cumulative.last;

    // Each maneuver point projected onto the route once: step i happens
    // when the user's along-distance passes this mark.
    _stepAlong = [
      for (final step in this.steps)
        math.min(math.max(_alongFor(step.location), 0), _total),
    ];
  }

  /// The routed polyline the user should stay on.
  final List<LatLng> points;

  /// Turn-by-turn steps (may be empty: the follower still tracks progress).
  final List<RouteStep> steps;

  /// How close (m) to the route's end counts as "arrived".
  final double arrivalRadius;

  /// How far (m) off the polyline before progress is considered off-route.
  final double offRouteThreshold;

  /// Advance to the next maneuver this many meters *before* its point, so
  /// the banner is already showing the next turn when the user reaches it.
  final double stepAdvanceBefore;

  late final List<double> _cumulative;
  late final double _total;
  late final List<double> _stepAlong;

  /// Total length of the route in meters.
  double get totalMeters => _total;

  /// Progress of [position] along the route. Safe to call at any rate.
  RouteProgress update(LatLng position) {
    var along = 0.0;
    var offRoute = double.infinity;

    // Closest point over every segment (routes are small; a full scan keeps
    // the answer stable no matter where the user jumped from).
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final segAlong = _segmentMeters(a, b);
      if (segAlong == 0) continue;

      final projection = _projectOnSegment(position, a, b);
      if (projection.perpendicular < offRoute) {
        offRoute = projection.perpendicular;
        along = _cumulative[i - 1] + projection.fraction * segAlong;
      }
    }
    if (offRoute == double.infinity) {
      // Degenerate single-point route: treat the position as at the start.
      offRoute = distanceMeters(position, points.first);
    }

    along = math.min(math.max(along, 0), _total);
    final remaining = math.max(_total - along, 0.0);

    // First maneuver the user has not passed yet (15 m of lookahead, so GPS
    // noise does not flicker the banner between two steps).
    var next = 0;
    while (next < steps.length && _stepAlong[next] <= along + stepAdvanceBefore) {
      next++;
    }
    if (next >= steps.length) next = math.max(steps.length - 1, 0);

    final distanceToManeuver = steps.isEmpty
        ? remaining
        : math.max(_stepAlong[next] - along, 0.0);

    final arrived =
        remaining <= arrivalRadius && offRoute <= offRouteThreshold;

    return RouteProgress(
      distanceAlong: along,
      remainingMeters: remaining,
      nextStepIndex: next,
      distanceToManeuver: distanceToManeuver,
      distanceOffRoute: offRoute,
      arrived: arrived,
    );
  }

  /// Along-route distance (m from the start) of an arbitrary point snapped
  /// onto the route. Used to pre-position each maneuver step.
  double _alongFor(LatLng position) {
    var bestDistance = double.infinity;
    var bestAlong = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final segAlong = _segmentMeters(a, b);
      if (segAlong == 0) continue;

      final projection = _projectOnSegment(position, a, b);
      if (projection.perpendicular < bestDistance) {
        bestDistance = projection.perpendicular;
        bestAlong = _cumulative[i - 1] + projection.fraction * segAlong;
      }
    }
    return bestAlong;
  }

  /// Meters between two points via the same flat-earth approximation the
  /// projection uses (keeps "off-route" and "distance" consistent).
  static double _segmentMeters(LatLng a, LatLng b) {
    final dEast =
        (b.longitude - a.longitude) *
        math.cos(a.latitude * math.pi / 180) *
        111320;
    final dNorth = (b.latitude - a.latitude) * 110540;
    return math.sqrt(dEast * dEast + dNorth * dNorth);
  }

  /// Projects [position] onto segment a->b.
  ///
  /// Returns the perpendicular distance to the segment and the fraction
  /// (0..1) along it - in local east/north meters around [a].
  ({double perpendicular, double fraction}) _projectOnSegment(
    LatLng position,
    LatLng a,
    LatLng b,
  ) {
    final cosLat = math.cos(a.latitude * math.pi / 180);
    final abEast = (b.longitude - a.longitude) * 111320 * cosLat;
    final abNorth = (b.latitude - a.latitude) * 110540;
    final apEast = (position.longitude - a.longitude) * 111320 * cosLat;
    final apNorth = (position.latitude - a.latitude) * 110540;

    final lengthSquared = abEast * abEast + abNorth * abNorth;
    if (lengthSquared == 0) {
      return (
        perpendicular: math.sqrt(
          apEast * apEast + apNorth * apNorth,
        ),
        fraction: 0,
      );
    }

    var fraction = (apEast * abEast + apNorth * abNorth) / lengthSquared;
    fraction = math.min(math.max(fraction, 0), 1);

    final dEast = apEast - fraction * abEast;
    final dNorth = apNorth - fraction * abNorth;
    return (
      perpendicular: math.sqrt(dEast * dEast + dNorth * dNorth),
      fraction: fraction,
    );
  }
}
