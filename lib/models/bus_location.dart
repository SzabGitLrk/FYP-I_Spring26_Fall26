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
      busId: json['bus_id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      heading: (json['heading'] as num).toDouble(),
      nextStopIndex: json['next_stop_index'] as int? ?? 0,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : DateTime.now(),
    );
  }

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

  // Estimate time to reach a point (in minutes)
  int? estimatedTimeTo(double lat, double lng) {
    if (speed <= 1) return null; // Bus stopped or very slow
    final distance = distanceTo(lat, lng);
    final timeHours = distance / speed;
    return (timeHours * 60).round();
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
