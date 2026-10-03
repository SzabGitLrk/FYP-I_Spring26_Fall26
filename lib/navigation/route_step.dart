import 'package:latlong2/latlong.dart';

/// One turn-by-turn step of a routed trip.
///
/// Produced by [RouteStep.fromOsrmRoute] or [RouteStep.fromValhallaTrip] -
/// the two keyless routers this app uses - so the rest of the navigation
/// pipeline never has to care which one answered.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distance,
    required this.roadName,
    required this.location,
  });

  /// Human-readable action, e.g. "Turn right onto VIP Road". Shown in the
  /// navigation banner and spoken by voice guidance.
  final String instruction;

  /// Normalised maneuver family ("turn-right", "fork-slight-left",
  /// "roundabout", "arrive", ...) used to pick the banner icon.
  final String maneuver;

  /// Length of this step in meters: the distance from the previous maneuver
  /// to [location].
  final double distance;

  /// Road this step runs on, "" when the router did not name one.
  final String roadName;

  /// Where the maneuver happens.
  final LatLng location;

  /// Compact distance for banners and speech: "850 m" below a kilometer,
  /// "1.2 km" above.
  static String formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  /// Parses an OSRM route object (requested with `steps=true`) into steps.
  ///
  /// OSRM returns maneuvers, not text - the instruction is synthesised from
  /// type/modifier/name so the banner reads like a navigation app.
  static List<RouteStep> fromOsrmRoute(Map<String, dynamic> route) {
    final legs = route['legs'];
    if (legs is! List) return const [];

    final steps = <RouteStep>[];
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      final osrmSteps = leg['steps'];
      if (osrmSteps is! List) continue;

      for (final step in osrmSteps) {
        if (step is! Map<String, dynamic>) continue;
        final maneuver = step['maneuver'];
        if (maneuver is! Map<String, dynamic>) continue;
        final location = maneuver['location'];
        if (location is! List || location.length < 2) continue;

        final name = step['name'] is String ? step['name'] as String : '';
        final ref = step['ref'] is String ? step['ref'] as String : '';
        final road = name.isNotEmpty && ref.isNotEmpty
            ? '$name ($ref)'
            : (name.isNotEmpty ? name : ref);
        final type = maneuver['type'] is String
            ? maneuver['type'] as String
            : 'continue';
        final modifier = maneuver['modifier'] is String
            ? maneuver['modifier'] as String
            : null;

        steps.add(
          RouteStep(
            instruction: _osrmInstruction(maneuver, type, modifier, road),
            maneuver: '$type-${modifier ?? 'straight'}',
            distance: (step['distance'] as num?)?.toDouble() ?? 0,
            roadName: road,
            // OSRM positions are GeoJSON: [lon, lat].
            location: LatLng(
              (location[1] as num).toDouble(),
              (location[0] as num).toDouble(),
            ),
          ),
        );
      }
    }
    return steps;
  }

  /// Parses a Valhalla `trip` object into steps.
  ///
  /// Valhalla ships ready-made English instructions and lengths in kilometers
  /// (the app requests `units: kilometers`).
  static List<RouteStep> fromValhallaTrip(Map<String, dynamic> trip) {
    final legs = trip['legs'];
    if (legs is! List) return const [];

    final steps = <RouteStep>[];
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      final maneuvers = leg['maneuvers'];
      if (maneuvers is! List) continue;

      for (final maneuver in maneuvers) {
        if (maneuver is! Map<String, dynamic>) continue;
        final start = maneuver['start_location'];
        if (start is! Map) continue;

        final type = maneuver['type'] is String
            ? maneuver['type'] as String
            : 'straight';
        final road = maneuver['street_name'] is String
            ? maneuver['street_name'] as String
            : '';
        final instruction = maneuver['instruction'] is String
            ? maneuver['instruction'] as String
            : _valhallaFallbackInstruction(type, road);

        steps.add(
          RouteStep(
            instruction: instruction,
            maneuver: _valhallaManeuverKey(type),
            // Valhalla lengths are kilometers under our request options.
            distance: ((maneuver['length'] as num?)?.toDouble() ?? 0) * 1000,
            roadName: road,
            location: LatLng(
              (start['lat'] as num).toDouble(),
              (start['lon'] as num).toDouble(),
            ),
          ),
        );
      }
    }
    return steps;
  }

  /// OSRM maneuver -> spoken instruction ("Head south on VIP Road",
  /// "Turn right onto College Rd", "At the roundabout, take exit 2", ...).
  static String _osrmInstruction(
    Map<String, dynamic> maneuver,
    String type,
    String? modifier,
    String road,
  ) {
    final onto = road.isEmpty ? '' : ' onto $road';

    switch (type) {
      case 'depart':
        final onRoad = road.isEmpty ? '' : ' on $road';
        return 'Head ${_compass(maneuver['bearing_after'])}$onRoad';
      case 'arrive':
        return 'Arrive at your stop';
      case 'roundabout':
      case 'rotary':
        final exit = maneuver['exit'];
        if (exit is num) return 'At the roundabout, take exit ${exit.toInt()}$onto';
        return 'At the roundabout, take the exit$onto';
      case 'end of road':
        return '${_turnPhrase(modifier)}$onto at the end of the road';
      case 'on ramp':
      case 'off ramp':
        return 'Take the ramp$onto';
      case 'merge':
        return 'Merge$onto';
      case 'fork':
        return 'Keep ${modifier ?? 'right'} at the fork$onto';
      case 'new name':
      case 'continue':
        if (modifier == 'uturn') return 'Make a U-turn$onto';
        return 'Continue$onto';
      case 'turn':
      default:
        if (modifier == 'uturn') return 'Make a U-turn$onto';
        return '${_turnPhrase(modifier)}$onto';
    }
  }

  /// Text used only when a Valhalla instruction is missing from the body.
  static String _valhallaFallbackInstruction(String type, String road) {
    if (type == 'dest' || type == 'arrive') return 'Arrive at your stop';
    final onto = road.isEmpty ? '' : ' onto $road';
    return '${_turnPhrase(type)}$onto';
  }

  /// Valhalla's free-form type ("slight right", "ramp left", "dest", ...)
  /// normalised into the same key space as OSRM's type-modifier.
  static String _valhallaManeuverKey(String type) {
    if (type == 'dest' || type == 'arrive') return 'arrive';
    return type.replaceAll(' ', '-');
  }

  static String _turnPhrase(String? modifier) {
    switch (modifier) {
      case 'sharp right':
        return 'Turn sharp right';
      case 'right':
        return 'Turn right';
      case 'slight right':
        return 'Bear right';
      case 'slight left':
        return 'Bear left';
      case 'left':
        return 'Turn left';
      case 'sharp left':
        return 'Turn sharp left';
      case 'uturn':
        return 'Make a U-turn';
      default:
        return 'Continue straight';
    }
  }

  static const List<String> _compassPoints = [
    'north',
    'north-east',
    'east',
    'south-east',
    'south',
    'south-west',
    'west',
    'north-west',
  ];

  /// Compass word for an OSRM `bearing_after` (0 = north, clockwise).
  static String _compass(num? bearing) {
    if (bearing == null) return 'straight';
    final normalized = ((bearing.toDouble() % 360) + 360) % 360;
    final index = ((normalized + 22.5) ~/ 45) % 8;
    return _compassPoints[index];
  }
}
