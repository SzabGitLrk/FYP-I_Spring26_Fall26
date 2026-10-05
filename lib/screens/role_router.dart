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

  /// True when the profiles lookup threw. Fail-closed: no dashboard renders
  /// until a retry succeeds - the app never guesses a role, and never
  /// silently resolves to `student` either.
  bool _resolveFailed = false;

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
          // Signing out must clear the identity latch: the same user logging
          // back in (e.g. after an admin approved them) has to re-resolve,
          // and a demoted admin must not keep their old dashboard for the
          // rest of the app session.
          _resolvedForUserId = null;
          _resolvedRole = null;
          _isApproved = false;
          _resolveFailed = false;
          return const LoginScreen();
        }

        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          _resolvedForUserId = null;
          _resolvedRole = null;
          _isApproved = false;
          _resolveFailed = false;
          return const LoginScreen();
        }

        // Kick off (or restart) the DB lookup when the identity changes.
        if (_resolvedForUserId != user.id) {
          _resolvedForUserId = user.id;
          _resolvedRole = null;
          _isApproved = false;
          _resolveFailed = false;
          _resolveRoleFromProfile(user.id);
        }

        // The authoritative lookup threw: fail closed to a retryable error
        // screen - NOT to the student home screen, which used to swallow a
        // transient failure for admins with no way to tell what happened.
        if (_resolveFailed) {
          return _RoleResolveErrorScreen(onRetry: _reResolve);
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

      // Re-check ownership after the await: if the user changed while this
      // lookup was in flight, writing A's role into B's session would hand
      // B the wrong dashboard (admin rights included).
      if (!mounted || _resolvedForUserId != userId) return;

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

      if (mounted && _resolvedForUserId == userId) {
        setState(() {
          _resolvedRole = 'student';
          _isApproved = false;
        });
      }
    } catch (e) {
      // Fail closed: never GUESS a role from a failed lookup - and never
      // silently resolve to `student` either. A transient error used to
      // dump a (possibly admin) account into the student home screen with
      // no indication anything was wrong and no way to retry. Guarded to
      // the user this lookup still belongs to.
      debugPrint('[role_router] profile lookup failed: $e');
      if (mounted && _resolvedForUserId == userId) {
        setState(() => _resolveFailed = true);
      }
    }
  }

  /// Forces a fresh profiles lookup: clears the latch so the build-time
  /// kick re-runs [_resolveRoleFromProfile] for the current user.
  void _reResolve() {
    setState(() {
      _resolvedForUserId = null;
      _resolvedRole = null;
      _isApproved = false;
      _resolveFailed = false;
    });
  }

  Widget _buildScreenForRole(String role, bool isApproved) {
    switch (role) {
      case 'admin':
        return const AdminDashboard();
      case 'driver':
        // Drivers must be approved by an admin before they can operate a bus.
        if (!isApproved) {
          return _PendingApprovalScreen(role: role, onRefresh: _reResolve);
        }
        return const DriverDashboard();
      case 'student':
      default:
        return const UniversityListScreen();
    }
  }
}

/// Shown to accounts whose role requires admin approval (currently: drivers).
class _PendingApprovalScreen extends StatelessWidget {
  const _PendingApprovalScreen({required this.role, required this.onRefresh});

  final String role;

  /// Re-runs the profiles lookup: the approval may have landed since this
  /// screen was shown. The old version only offered sign-out, and - because
  /// sign-out never cleared the router's latch - the same user logging back
  /// in kept rendering this stale screen until the app was force-stopped.
  final VoidCallback onRefresh;

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
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Check approval status'),
            ),
            const SizedBox(height: 12),
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

/// Shown when the authoritative `profiles` lookup failed (offline, RLS,
/// schema). Fail-closed: no dashboard is rendered until a retry verifies
/// the role, but the failure is stated openly with a Retry button instead
/// of silently resolving to `student`.
class _RoleResolveErrorScreen extends StatelessWidget {
  const _RoleResolveErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Could not verify account')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cloud_off, size: 72, color: Colors.orange.shade700),
            const SizedBox(height: 24),
            const Text(
              'We could not verify your account',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'This usually means the connection dropped before your role '
              'could be checked. Nothing is wrong with your account - tap '
              'Retry, or sign out and sign in again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 12),
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
