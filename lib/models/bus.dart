class Bus {
  final int id;
  final int routeId;
  final String busNumber;
  final String? driverName;
  final String? driverPhone;
  final int capacity;
  final String status;
  final DateTime createdAt;

  Bus({
    required this.id,
    required this.routeId,
    required this.busNumber,
    this.driverName,
    this.driverPhone,
    required this.capacity,
    required this.status,
    required this.createdAt,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json['id'] as int,
      routeId: json['route_id'] as int,
      busNumber: json['bus_number'] as String,
      driverName: json['driver_name'] as String?,
      driverPhone: json['driver_phone'] as String?,
      capacity: json['capacity'] as int? ?? 20,
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  @override
  String toString() => 'Bus(id: $id, number: $busNumber)';
}
