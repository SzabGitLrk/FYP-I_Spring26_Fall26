class RouteModel {
  final int id;
  final int universityId;
  final String routeName;
  final String? description;
  final DateTime createdAt;

  RouteModel({
    required this.id,
    required this.universityId,
    required this.routeName,
    this.description,
    required this.createdAt,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      id: json['id'] as int,
      universityId: json['university_id'] as int,
      routeName: json['route_name'] as String,
      description: json['description'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  @override
  String toString() => 'RouteModel(id: $id, name: $routeName)';
}
