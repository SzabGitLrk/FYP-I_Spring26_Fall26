class Profile {
  final String id;
  final String name;
  final String? email;
  final String role;
  final bool isApproved;
  final DateTime createdAt;

  Profile({
    required this.id,
    required this.name,
    this.email,
    required this.role,
    required this.isApproved,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      role: json['role'] as String? ?? 'student',
      isApproved: json['is_approved'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'role': role,
      'is_approved': isApproved,
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isDriver => role == 'driver';
  bool get isStudent => role == 'student';

  @override
  String toString() => 'Profile(id: $id, name: $name, role: $role)';
}
