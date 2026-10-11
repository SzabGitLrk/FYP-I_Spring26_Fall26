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
    // Fail fast on a caller bug: an empty polyline would otherwise throw an
    // obscure StateError deep inside update() at the first GPS fix.
    if (this.points.isEmpty) {
      throw ArgumentError('RouteFollower requires at least one point');
    }

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
    // when the user's along-distance passes this mark. Global projection can
    // snap two steps onto the wrong leg of a self-crossing route and make the
    // marks run backwards, which would break the "first step not passed yet"
    // scan below - so the marks are forced monotonically non-decreasing
    // (steps happen in order by definition).
    final marks = <double>[];
    var mark = 0.0;
    for (final step in this.steps) {
      final raw = math.min(math.max(_alongFor(step.location), 0.0), _total);
      if (raw > mark) mark = raw;
      marks.add(mark);
    }
    _stepAlong = marks;
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

  /// Meters of along-route continuity between fixes: projections are only
  /// considered on segments within +/- this window of the previous fix.
  /// Without it, a route that crosses or runs parallel to itself (or plain
  /// GPS noise far from the road) can snap the user onto the wrong leg and
  /// teleport progress - reporting "1 km remaining" while they stand 100 m
  /// from the stop, or jumping straight to the end and declaring arrival.
  static const double _continuityWindow = 200;

  /// With a speed fix, the step-advance lookahead covers this many seconds
  /// of travel (scaled by speedMps, never below [stepAdvanceBefore]).
  static const double _speedLookaheadSeconds = 5.0;

  /// The `depart` maneuver sits at the route start, so its along-mark
  /// (~0 m) is always inside the lookahead and the plain loop skipped it
  /// on the very first fix - students never saw or heard "Head north on
  /// ...". Treat step 0 as the current step until the position is at least
  /// this many meters along the route.
  static const double _departHoldMeters = 25;

  /// Second arrival gate: within this many meters of the FINAL step's
  /// maneuver point (and not wildly off-route) also counts as near the end
  /// - see the arrived calculation in [update].
  static const double _finalManeuverArrivalRadius = 15;

  /// Where the previous fix projected onto the route; null until the first
  /// fix, which seeds the window with the whole route.
  double? _lastAlong;

  /// Consecutive fixes near the route end while sitting more than
  /// [offRouteThreshold] m off the polyline - the GPS-noise tiebreaker for
  /// arrival (see the arrived calculation in [update]).
  int _nearEndFixes = 0;

  /// Total length of the route in meters.
  double get totalMeters => _total;

  /// Progress of [position] along the route. Safe to call at any rate.
  ///
  /// [speedMps], when supplied and > 0, widens the step-advance lookahead
  /// to ~5 seconds of travel (never below [stepAdvanceBefore]): a fixed
  /// 15 m flips the banner only ~1.4 s before an intersection at 40 km/h,
  /// which is too late to react. Default (null) keeps the fixed-lookahead
  /// behaviour callers and tests rely on.
  RouteProgress update(LatLng position, {double? speedMps}) {
    var along = 0.0;
    var offRoute = double.infinity;

    // Closest point over every segment near the previous fix (see
    // [_continuityWindow]; the first fix scans the whole route).
    for (var i = 1; i < points.length; i++) {
      final segStart = _cumulative[i - 1];
      final segEnd = _cumulative[i];
      if (_lastAlong != null &&
          (segStart > _lastAlong! + _continuityWindow ||
              segEnd < _lastAlong! - _continuityWindow)) {
        continue;
      }

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
    // A fix more than [_continuityWindow] away from every windowed segment
    // (or a window that matched no segment at all) means the window itself
    // is stale: a GNSS gap, an urban-canyon teleport, or the burst after
    // the send throttle. Re-seed from a whole-route scan instead of
    // accepting the stale projection - which reported the jump as
    // off-route (latching a needless debounced reroute) while progress
    // lagged at the old mark and self-healed only ~200 m per fix.
    if (offRoute > _continuityWindow) {
      for (var i = 1; i < points.length; i++) {
        final segStart = _cumulative[i - 1];
        final segAlong = _segmentMeters(points[i - 1], points[i]);
        if (segAlong == 0) continue;
        final projection = _projectOnSegment(
          position,
          points[i - 1],
          points[i],
        );
        if (projection.perpendicular < offRoute) {
          offRoute = projection.perpendicular;
          along = segStart + projection.fraction * segAlong;
        }
      }
    }
    if (offRoute == double.infinity) {
      // Degenerate route: a single point, or every segment zero-length
      // (duplicate vertices) - the position counts as at that point.
      offRoute = distanceMeters(position, points.first);
    }

    along = math.min(math.max(along, 0), _total);
    _lastAlong = along;
    final remaining = math.max(_total - along, 0.0);

    // First maneuver the user has not passed yet. Lookahead is
    // [stepAdvanceBefore] m of GPS-noise guard, widened to ~5 s of travel
    // when the caller supplies a speed: 15 m alone flips the banner only
    // ~1.4 s before an intersection at 40 km/h.
    var lookahead = stepAdvanceBefore;
    if (speedMps != null && speedMps > 0) {
      lookahead = math.max(lookahead, speedMps * _speedLookaheadSeconds);
    }

    var next = 0;
    while (next < steps.length && _stepAlong[next] <= along + lookahead) {
      next++;
    }
    if (next >= steps.length) next = math.max(steps.length - 1, 0);
    // Hold the `depart` step for the first [_departHoldMeters] m: its mark
    // sits at the route start, so the loop above would skip it on the very
    // first fix (see [_departHoldMeters]).
    if (steps.isNotEmpty && next > 0 && along < _departHoldMeters) {
      next = 0;
    }

    final distanceToManeuver = steps.isEmpty
        ? remaining
        : math.max(_stepAlong[next] - along, 0.0);

    // Arrival: at the route's end and (normally) near the polyline. GPS
    // noise near a stop can put the user 50-100 m off the drawn line while
    // they stand at the destination - that fell between the arrival gate
    // (off-route <= 45 m) and the reroute trigger (remaining > 120 m), so
    // guidance hung forever. Three consecutive near-end fixes settle it.
    // Second gate: a fix with 30-120 m remaining that reports 45-90 m
    // off-route (busy built-up stop area) neither arrived nor got rerouted
    // (the caller suppresses reroutes near the stop) - standing within
    // [_finalManeuverArrivalRadius] m of the FINAL step's maneuver point
    // while not wildly off-route (<= 2x [offRouteThreshold]) also counts
    // as near the end, settled by the same 3-fix latch.
    // A degenerate zero-length route never arrives: `remaining` is 0 from
    // the first fix, and standing at the route's *start* is not the end.
    final nearEndManeuver =
        steps.isNotEmpty &&
        _total > 0 &&
        math.max(_stepAlong.last - along, 0.0) <= _finalManeuverArrivalRadius &&
        offRoute <= 2 * offRouteThreshold;
    final nearEnd =
        _total > 0 && (remaining <= arrivalRadius || nearEndManeuver);
    bool arrived;
    if (!nearEnd) {
      _nearEndFixes = 0;
      arrived = false;
    } else if (offRoute <= offRouteThreshold) {
      arrived = true;
    } else {
      arrived = ++_nearEndFixes >= 3;
    }

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
