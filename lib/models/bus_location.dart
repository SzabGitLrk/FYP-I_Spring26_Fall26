import 'dart:math';

class BusLocation {
  final int id;
  final int busId;
  final double latitude;
  final double longitude;
  final double speed;
  final double heading;
  final int nextStopIndex;
  final DateTime timestamp;

  BusLocation({
    required this.id,
    required this.busId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    required this.nextStopIndex,
    required this.timestamp,
  });

  factory BusLocation.fromJson(Map<String, dynamic> json) {
    return BusLocation(
      id: json['id'] as int,
      // `bus_id`, `speed` and `heading` are all nullable in the schema
      // (plain FK, and `DEFAULT 0` without NOT NULL), so a hand-inserted row
      // would otherwise throw a TypeError and take the whole bus list down.
      busId: json['bus_id'] as int? ?? 0,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      nextStopIndex: json['next_stop_index'] as int? ?? 0,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : DateTime.now(),
    );
  }

  /// Row -> JSON, for the offline cache ([OfflineCache]). Mirrors [fromJson].
  Map<String, dynamic> toJson() => {
        'id': id,
        'bus_id': busId,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'heading': heading,
        'next_stop_index': nextStopIndex,
        'timestamp': timestamp.toIso8601String(),
      };

  // Calculate distance to a point (in km using Haversine formula)
  double distanceTo(double lat, double lng) {
    const R = 6371; // Earth's radius in km
    final dLat = _toRadians(lat - latitude);
    final dLng = _toRadians(lng - longitude);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(latitude)) *
            cos(_toRadians(lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) => degree * (pi / 180);

  // Estimate time to reach a point (in minutes).
  //
  // Straight-line distance over current speed - a coarse model (it ignores
  // the road geometry), so callers treat the result as approximate. Null
  // means "no estimate possible": the bus is stopped somewhere away from
  // the point and will not arrive on any predictable schedule.
  int? estimatedTimeTo(double lat, double lng) {
    final distance = distanceTo(lat, lng);
    if (speed <= 1) {
      // Stopped AT the point means the bus has arrived (0 min), not "no
      // data" - otherwise the approaching-bus alert can never fire for the
      // bus already sitting at your stop. Stopped elsewhere stays null so a
      // bus at a red light 2 km away never shows a phantom ETA.
      return distance < 0.05 ? 0 : null;
    }
    final timeHours = distance / speed;
    // Ceiling: the app must never promise an earlier arrival than reality
    // (round() on 4.9 min claimed "5", but 0.4 min of real travel used to
    // round down to "0 min" and read as "already here").
    return (timeHours * 60).ceil();
  }

  // Check if bus is moving
  bool get isMoving => speed > 2;

  // Get status text
  String get statusText {
    if (speed < 1) return 'Stopped';
    if (speed < 10) return 'Moving slowly';
    if (speed < 25) return 'Moving normally';
    return 'Moving fast';
  }

  @override
  String toString() =>
      'BusLocation(busId: $busId, lat: $latitude, lng: $longitude, speed: $speed)';
}
