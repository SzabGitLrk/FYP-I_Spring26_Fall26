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
      routeId: json['route_id'] as int,
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

  // For debugging
  @override
  String toString() {
    return 'PickupPoint(id: $id, name: $pointName, order: $orderIndex)';
  }
}
