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
  /// Role as recorded in the `profiles` table. `null` means "not loaded yet".
  ///
  /// SECURITY: the role is read ONLY from the database. It is never taken from
  /// `user.userMetadata`, because signup metadata is fully client-controlled —
  /// trusting it would let anyone register as `admin` and land on the admin
  /// dashboard. See `supabase_security_fix.sql`.
  String? _resolvedRole;

  /// Whether an admin has approved this account (only meaningful for drivers).
  bool _isApproved = false;

  /// User id `_resolvedRole` / `_isApproved` belong to. Used to re-resolve when
  /// the signed-in user changes; the previous implementation never reset its
  /// latch, so switching accounts showed the prior user's role.
  String? _resolvedForUserId;

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
        if (session == null) return const LoginScreen();

        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return const LoginScreen();

        // Kick off (or restart) the DB lookup when the identity changes.
        if (_resolvedForUserId != user.id) {
          _resolvedForUserId = user.id;
          _resolvedRole = null;
          _isApproved = false;
          _resolveRoleFromProfile(user.id);
        }

        // Still loading the authoritative role: show progress rather than
        // guessing, otherwise a fresh login would flash the wrong dashboard.
        if (_resolvedRole == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _buildScreenForRole(_resolvedRole!, _isApproved);
      },
    );
  }

  Future<void> _resolveRoleFromProfile(String userId) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role, is_approved')
          .eq('id', userId)
          .maybeSingle();

      if (!mounted) return;

      if (profile != null) {
        setState(() {
          _resolvedRole = profile['role'] as String? ?? 'student';
          _isApproved = profile['is_approved'] == true;
        });
        return;
      }

      // Profile row is missing (the signup trigger failed or was never run).
      // Create it with SAFE defaults: never forward client-supplied role or
      // approval state, and let the database guard normalise whatever we send.
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('profiles').upsert({
        'id': userId,
        'name': user.userMetadata?['name'] ?? 'User',
        'email': user.email,
        'role': 'student',
        'is_approved': false,
      });

      if (mounted) {
        setState(() {
          _resolvedRole = 'student';
          _isApproved = false;
        });
      }
    } catch (_) {
      // Fail closed: default to the least-privileged role.
      if (mounted && _resolvedRole == null) {
        setState(() {
          _resolvedRole = 'student';
          _isApproved = false;
        });
      }
    }
  }

  Widget _buildScreenForRole(String role, bool isApproved) {
    switch (role) {
      case 'admin':
        return const AdminDashboard();
      case 'driver':
        // Drivers must be approved by an admin before they can operate a bus.
        if (!isApproved) return _PendingApprovalScreen(role: role);
        return const DriverDashboard();
      case 'student':
      default:
        return const UniversityListScreen();
    }
  }
}

/// Shown to accounts whose role requires admin approval (currently: drivers).
class _PendingApprovalScreen extends StatelessWidget {
  const _PendingApprovalScreen({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account pending approval')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.hourglass_top, size: 72, color: Colors.blue.shade700),
            const SizedBox(height: 24),
            const Text(
              'Your account is waiting for approval',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'A $role account must be approved by an administrator before it '
              'can be used. Please try again later, or contact support if this '
              'takes too long.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
