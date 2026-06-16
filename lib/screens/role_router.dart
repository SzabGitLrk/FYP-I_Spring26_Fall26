import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/screens/login_screen.dart';
import 'package:university_point_locator/screens/university_list_screen.dart';
import 'package:university_point_locator/screens/driver/driver_dashboard.dart';
import 'package:university_point_locator/screens/admin/admin_dashboard.dart';

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  String _resolvedRole = 'student';
  bool _resolving = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = Supabase.instance.client.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return const LoginScreen();

        // Try metadata first (fast, no DB round-trip)
        final metaRole = user.userMetadata?['role'] as String?;
        if (metaRole != null && metaRole != 'student') {
          print('👤 Logged in as: ${user.email} (Role from metadata: $metaRole)');
          return _buildScreenForRole(metaRole);
        }

        // Fall back to profiles table (covers admin-created users)
        if (!_resolving) {
          _resolving = true;
          _resolveRoleFromProfile(user.id, metaRole);
        }

        if (_resolvedRole != 'student') {
          print('👤 Logged in as: ${user.email} (Role from profile: $_resolvedRole)');
          return _buildScreenForRole(_resolvedRole);
        }

        print('👤 Logged in as: ${user.email} (Role: student)');
        return const UniversityListScreen();
      },
    );
  }

  Future<void> _resolveRoleFromProfile(String userId, String? metaRole) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && mounted) {
        final dbRole = profile['role'] as String? ?? 'student';
        setState(() => _resolvedRole = dbRole);
      } else {
        // Profile doesn't exist (trigger may have failed); create it
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await Supabase.instance.client.from('profiles').upsert({
            'id': userId,
            'name': user.userMetadata?['name'] ?? 'User',
            'email': user.email,
            'role': metaRole ?? user.userMetadata?['role'] ?? 'student',
            'is_approved': metaRole == 'admin' ? true : false,
          });
          if (mounted) {
            setState(() => _resolvedRole = metaRole ?? 'student');
          }
        }
      }
    } catch (_) {
      // Fall through to student default
    }
  }

  Widget _buildScreenForRole(String role) {
    switch (role) {
      case 'admin':
        return const AdminDashboard();
      case 'driver':
        return const DriverDashboard();
      case 'student':
      default:
        return const UniversityListScreen();
    }
  }
}
