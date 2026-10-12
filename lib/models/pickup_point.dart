class PickupPoint {
  final int id;
  final int routeId;
  final String pointName;
  final double latitude;
  final double longitude;
  final String? address;
  final String? landmark;
  final int orderIndex;
  final int? estimatedTimeFromPrevious;
  final DateTime createdAt;

  PickupPoint({
    required this.id,
    required this.routeId,
    required this.pointName,
    required this.latitude,
    required this.longitude,
    this.address,
    this.landmark,
    required this.orderIndex,
    this.estimatedTimeFromPrevious,
    required this.createdAt,
  });

  // Create from JSON (Supabase returns data as JSON)
  factory PickupPoint.fromJson(Map<String, dynamic> json) {
    return PickupPoint(
      id: json['id'] as int,
      // Nullable FK (never written by the app) — see `Bus.fromJson`.
      routeId: json['route_id'] as int? ?? 0,
      pointName: json['point_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      landmark: json['landmark'] as String?,
      orderIndex: json['order_index'] as int,
      estimatedTimeFromPrevious: json['estimated_time_from_previous'] as int?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  /// Row -> JSON, for the offline cache ([OfflineCache]). Mirrors [fromJson].
  Map<String, dynamic> toJson() => {
        'id': id,
        'route_id': routeId,
        'point_name': pointName,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'landmark': landmark,
        'order_index': orderIndex,
        'estimated_time_from_previous': estimatedTimeFromPrevious,
        'created_at': createdAt.toIso8601String(),
      };

  // For debugging
  @override
  String toString() {
    return 'PickupPoint(id: $id, name: $pointName, order: $orderIndex)';
  }
}
