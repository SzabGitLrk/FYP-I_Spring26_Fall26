class University {
  final int id;
  final String name;
  final String city;
  final DateTime createdAt;

  University({
    required this.id,
    required this.name,
    required this.city,
    required this.createdAt,
  });

  // Create from JSON (Supabase returns data as JSON)
  factory University.fromJson(Map<String, dynamic> json) {
    return University(
      id: json['id'] as int,
      name: json['name'] as String,
      city: json['city'] as String,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  // Convert to JSON (for inserting data)
  Map<String, dynamic> toJson() {
    return {'name': name, 'city': city};
  }

  @override
  String toString() {
    return 'University{id: $id, name: $name, city: $city}';
  }
}
