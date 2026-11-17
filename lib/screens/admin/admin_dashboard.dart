import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:university_point_locator/screens/admin/stop_editor_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supabase = Supabase.instance.client;

  int _totalStudents = 0;
  int _totalDrivers = 0;
  int _totalBuses = 0;
  int _activeTrips = 0;
  List<Map<String, dynamic>> _sosAlerts = [];
  /// Driver-reported bus problems (Fuel Empty / Bus Fault). Live via
  /// [_subscribeToBusIssues]; fails loudly like the SOS list above.
  List<Map<String, dynamic>> _busIssues = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _buses = [];
  /// Student accounts - a read-only roster. The dashboard could show
  /// drivers, buses and alerts but had no view at all of the students who
  /// actually make up the user base.
  List<Map<String, dynamic>> _students = [];
  /// Universities for the route dialog's dropdown (id + name only).
  List<Map<String, dynamic>> _universities = [];
  /// Routes, for the "Add Bus" route dropdown. Loaded once (they change
  /// rarely) so the admin can assign a new bus to a real route.
  List<Map<String, dynamic>> _routes = [];

  /// True while the first parallel load is in flight. Without this gate the
  /// dashboard rendered 0/0/0/0 and "No active SOS alerts" as facts while
  /// the data was still arriving - an emergency view claiming to be quiet.
  bool _isLoading = true;

  /// Non-null when any section failed to reload; shown as an in-page banner
  /// with Retry. Four stacked error snackbars used to be the only signal,
  /// and a failed SOS load looked exactly like "no alerts".
  String? _loadError;

  /// Live feed for SOS alerts. They were fetched exactly ONCE in initState,
  /// so a new emergency never appeared until the admin restarted the app.
  RealtimeChannel? _sosChannel;
  RealtimeChannel? _issuesChannel;
  /// Live feed for NEW driver sign-ups. Without it, a driver who registers
  /// while this screen is open never appears here until a manual refresh, so
  /// the admin thinks approval is broken. Subscribing to `profiles` makes a
  /// pending driver show up the moment they sign up.
  RealtimeChannel? _profilesChannel;

  @override
  void initState() {
    super.initState();
    // Loads routes too: they feed the "Add Bus" dropdown, and a first-open
    // that failed offline must be recoverable via pull-to-refresh (the
    // comment on _loadRoutes promises exactly that).
    _refreshAll(initial: true);
    _subscribeToSOS();
    _subscribeToBusIssues();
    _subscribeToProfiles();
  }

  @override
  void dispose() {
    final channel = _sosChannel;
    if (channel != null) supabase.removeChannel(channel);
    final issues = _issuesChannel;
    if (issues != null) supabase.removeChannel(issues);
    final profiles = _profilesChannel;
    if (profiles != null) supabase.removeChannel(profiles);
    super.dispose();
  }

  /// Surfaces a failed admin action/load to the admin.
  ///
  /// Every method below used to swallow errors with `catch (_) {}`. Because
  /// the success SnackBar lived *inside* the `try`, a rejected write showed
  /// nothing at all: approving a driver or resolving an SOS alert simply
  /// appeared to do nothing, and a failed `_loadSOSAlerts` rendered an empty
  /// emergency-alert list as if there were no alerts.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _signOut() async {
    // Captured before the await: both outlive this State, so they stay valid
    // even if the widget is disposed mid-request. A failed sign-out (offline)
    // used to escape as an unhandled async error with no on-screen feedback.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('[admin] sign out failed: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not sign out. Check your connection and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    navigator.pushReplacementNamed('/');
  }

  /// Reloads every section in parallel and surfaces any failure as an
  /// in-page banner.
  ///
  /// The four loads used to run sequentially in initState with no loading
  /// state at all, and pull-to-refresh ran three of them serially (never
  /// refreshing buses). [_guard] converts each failure into `false` so one
  /// dead request cannot stack four red snackbars.
  Future<void> _refreshAll({bool initial = false}) async {
    if (initial && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    final outcomes = await Future.wait<bool>([
      _guard(_loadStats),
      _guard(_loadSOSAlerts),
      _guard(_loadBusIssues),
      _guard(_loadDrivers),
      _guard(_loadStudents),
      _guard(_loadBuses),
      // Routes + universities: both feed the route add/edit dialog.
      _guard(_loadUniversities),
      // Routes included: without this, one offline first-open left the
      // "Add Bus" dropdown empty for the whole session - its own catch
      // swallowed the failure and nothing (not even pull-to-refresh) ever
      // retried it until an app restart.
      _guard(_loadRoutes),
    ]);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadError = outcomes.contains(false)
          ? 'Some dashboard data could not be loaded. Check your connection '
              'and tap Retry.'
          : null;
    });
  }

  Future<bool> _guard(Future<void> Function() load) async {
    try {
      await load();
      return true;
    } catch (e) {
      debugPrint('[admin] dashboard load failed: $e');
      return false;
    }
  }

  Future<void> _loadStats() async {
    // One round trip in parallel instead of four sequential awaits.
    final results = await Future.wait([
      supabase.from('profiles').select().eq('role', 'student'),
      supabase.from('profiles').select().eq('role', 'driver'),
      supabase.from('buses').select(),
      supabase.from('trips').select().eq('status', 'active'),
    ]);

    if (!mounted) return;
    setState(() {
      _totalStudents = results[0].length;
      _totalDrivers = results[1].length;
      _totalBuses = results[2].length;
      _activeTrips = results[3].length;
    });
  }

  /// Throws on failure: [_guard] reports it through the [_loadError] banner.
  /// The old `catch` turned a real outage into a green-looking empty list -
  /// "No active SOS alerts" while the query had actually failed.
  Future<void> _loadSOSAlerts() async {
    final alerts = await supabase
        .from('sos_alerts')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() => _sosAlerts = List<Map<String, dynamic>>.from(alerts));
    }
  }

  /// Keeps the emergency list live: without this subscription the alerts
  /// were fetched exactly once at app start, so a student pressing SOS
  /// never reached an admin who was already looking at the screen.
  void _subscribeToSOS() {
    _sosChannel = supabase
        .channel('admin-sos-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sos_alerts',
          callback: (_) {
            // Quiet on purpose: this callback sits outside _refreshAll's
            // Future.wait, so the banner cannot represent it - the periodic
            // pull-to-refresh remains the fallback if realtime is down.
            _loadSOSAlerts().catchError(
              (Object e) => debugPrint('[admin] sos live reload failed: $e'),
            );
          },
        )
        .subscribe();
  }

  /// Throws on failure: [_guard] reports it through the [_loadError] banner.
  Future<void> _loadBusIssues() async {
    final issues = await supabase
        .from('bus_issues')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() => _busIssues = List<Map<String, dynamic>>.from(issues));
    }
  }

  /// Keeps the driver-issue list live for the same reason the SOS feed is:
  /// a fuel-empty or breakdown report must reach an admin already looking
  /// at this screen, not the next time they pull to refresh.
  void _subscribeToBusIssues() {
    _issuesChannel = supabase
        .channel('admin-bus-issues-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bus_issues',
          callback: (_) {
            // Quiet on purpose, same as the SOS callback: this sits outside
            // _refreshAll's Future.wait, so the banner cannot represent it.
            _loadBusIssues().catchError(
              (Object e) =>
                  debugPrint('[admin] bus issues live reload failed: $e'),
            );
          },
        )
        .subscribe();
  }

  /// Keeps the pending-approval list live: a driver who signs up while this
  /// screen is open now appears immediately (with the stats) instead of only
  /// after a manual pull-to-refresh - which is exactly why approval looked
  /// "broken". Quiet on purpose like the other callbacks (outside
  /// _refreshAll's Future.wait); the periodic refresh remains the fallback if
  /// realtime is down.
  void _subscribeToProfiles() {
    _profilesChannel = supabase
        .channel('admin-profiles-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) {
            Future.wait([
              _loadDrivers().catchError(
                (Object e) =>
                    debugPrint('[admin] drivers live reload failed: $e'),
              ),
              // Students included: the stat card updated live while the
              // roster stayed frozen, so the dashboard could show
              // "42 enrolled" over "No student accounts yet".
              _loadStudents().catchError(
                (Object e) =>
                    debugPrint('[admin] students live reload failed: $e'),
              ),
              _loadStats().catchError(
                (Object e) =>
                    debugPrint('[admin] stats live reload failed: $e'),
              ),
            ]);
          },
        )
        .subscribe();
  }

  Future<void> _loadDrivers() async {
    // Explicit ascending name order: supabase-dart's .order() defaults to
    // DESCENDING, which would list drivers Z->A.
    final drivers = await supabase
        .from('profiles')
        .select()
        .eq('role', 'driver')
        .order('name', ascending: true);

    // Diagnostics: if RLS blocks this admin from reading driver rows, the
    // count is 0 and (when is_admin() errors) a banner also shows - together
    // these pin down "approval is broken" to DB-side vs. a stale view.
    final pending =
        drivers.where((d) => d['is_approved'] != true).length;
    debugPrint(
      '[admin] loaded ${drivers.length} driver row(s), '
      '$pending pending (RLS-visible to this admin)',
    );

    if (mounted) {
      setState(() => _drivers = List<Map<String, dynamic>>.from(drivers));
    }
  }

  /// All student accounts (read-only roster), alphabetically like the
  /// driver list. The dashboard previously showed drivers, buses and alerts
  /// but had no view at all of the students who actually use the app.
  /// Same is_admin() RLS path as [_loadDrivers].
  Future<void> _loadStudents() async {
    final students = await supabase
        .from('profiles')
        .select('id, name, email, created_at')
        .eq('role', 'student')
        // Explicit ascending: supabase-dart's .order() defaults to DESCENDING.
        .order('name', ascending: true);

    debugPrint(
      '[admin] loaded ${students.length} student row(s) '
      '(RLS-visible to this admin)',
    );

    if (mounted) {
      setState(() => _students = List<Map<String, dynamic>>.from(students));
    }
  }

  Future<void> _approveDriver(String driverId) async {
    try {
      // `.select('id')` returns the rows actually affected: RLS (or a stale
      // id) can make this a zero-row write that Supabase still reports as a
      // success - and the old code showed a green "Driver approved" for it.
      final updated = await supabase
          .from('profiles')
          .update({'is_approved': true})
          .eq('id', driverId)
          .select('id');
      if (updated.isEmpty) {
        throw StateError('approve driver affected no rows');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver approved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Raw exception text goes to the log, never to the screen.
      debugPrint('[admin] approve driver failed: $e');
      _showError(
        'Could not approve the driver. Refresh and try again - '
        'the record may have already changed.',
      );
    }
  }

  /// Month abbreviations for [_formatDateTime].
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `created_at` arrives straight from the backend: one null or malformed
  /// value must not throw inside build() and take every other card down with
  /// it. Formats as `11 Oct 2026, 2:05 PM` - the raw `DateTime.toString()`
  /// this used to return is not something an administrator should have to
  /// parse during an emergency.
  static String _formatDateTime(dynamic raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}');
    if (parsed == null) return '—';
    final local = parsed.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${local.day} ${_months[local.month - 1]} ${local.year}, '
        '$hour12:$minute $period';
  }

  Future<void> _resolveSOS(int alertId) async {
    try {
      // `.select('id')` + the emptiness check: a write RLS filtered to zero
      // rows must not show a green "SOS resolved" over an alert that is
      // still active.
      final updated = await supabase
          .from('sos_alerts')
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', alertId)
          .select('id');
      if (updated.isEmpty) {
        throw StateError('resolve SOS affected no rows');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS resolved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] resolve SOS failed: $e');
      _showError(
        'Could not resolve the SOS alert. Refresh and try again - '
        'the alert may have already been handled.',
      );
    }
  }

  Future<void> _resolveBusIssue(int issueId) async {
    try {
      // Same row-count guard as _resolveSOS: a zero-row write must not
      // show a green "resolved" over a report that is still active.
      final updated = await supabase
          .from('bus_issues')
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', issueId)
          .select('id');
      if (updated.isEmpty) {
        throw StateError('resolve bus issue affected no rows');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bus issue marked resolved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] resolve bus issue failed: $e');
      _showError(
        'Could not resolve the bus issue. Refresh and try again - '
        'it may have already been handled.',
      );
    }
  }

  /// Rejecting a PENDING driver really has to REMOVE the account: an
  /// unapproved row that just lingered in the list looked like the button
  /// did nothing, and the person could keep re-appearing forever. The
  /// profile row is deleted (locks that user id out of the app until it
  /// signs up again); the raw auth email stays in Supabase Auth.
  Future<void> _rejectDriver(Map<String, dynamic> driver) async {
    final confirmed = await _confirmDeleteAccount(driver, roleNoun: 'Driver');
    if (!confirmed) return;
    await _deleteAccount(driver, roleNoun: 'Driver', success: 'Driver rejected and removed');
  }

  /// Reversible demotion: approval off, the driver moves back to the
  /// pending list (where they can be re-approved). Unlike [_rejectDriver]
  /// this keeps the account.
  Future<void> _unapproveDriver(Map<String, dynamic> driver) async {
    try {
      final updated = await supabase
          .from('profiles')
          .update({'is_approved': false})
          .eq('id', driver['id'])
          .select('id');
      if (updated.isEmpty) {
        throw StateError('revoke driver affected no rows');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver approval revoked - back to pending'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] revoke driver failed: $e');
      _showError(
        'Could not revoke the driver. Refresh and try again - '
        'the record may have already changed.',
      );
    }
  }

  Future<bool> _confirmDeleteAccount(
    Map<String, dynamic> profile, {
    required String roleNoun,
  }) async {
    final name = '${profile['name'] ?? ''}'.trim();
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove $roleNoun'),
            content: Text(
              name.isEmpty
                  ? 'Remove this ${roleNoun.toLowerCase()} from the app? '
                      'Their account is deleted and they can sign up again '
                      'later.'
                  : 'Remove $name from the app? Their account is deleted '
                      'and they can sign up again later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  // Override the theme's full-width minimum: inside the
                  // actions row infinity clamps to the whole dialog width.
                  minimumSize: const Size(0, 40),
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Deletes a driver/student profile row (row-verified) and clears any
  /// bus assignment the name held, so a FUTURE account with the same name
  /// cannot inherit their bus.
  Future<void> _deleteAccount(
    Map<String, dynamic> profile, {
    required String roleNoun,
    String? success,
  }) async {
    try {
      // `.select('id')` + emptiness check: a zero-row delete (missing
      // policy - supabase_admin_powers.sql - or a stale id) must never
      // show a green "removed" over a row that is still there.
      final deleted = await supabase
          .from('profiles')
          .delete()
          .eq('id', profile['id'])
          .select('id');
      if (deleted.isEmpty) {
        throw StateError('delete profile affected no rows');
      }
      final name = '${profile['name'] ?? ''}';
      if (roleNoun == 'Driver' && name.isNotEmpty) {
        // Best effort: assignment cleanup must not fail the removal - the
        // buses UPDATE also needs supabase_admin_buses.sql.
        try {
          await supabase
              .from('buses')
              .update({'driver_name': null})
              .eq('driver_name', name);
        } catch (e) {
          debugPrint('[admin] assignment cleanup after delete failed: $e');
        }
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ?? '$roleNoun removed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] delete ${roleNoun.toLowerCase()} failed: $e');
      _showError(
        'Could not remove the ${roleNoun.toLowerCase()}. Make sure '
        'supabase_admin_powers.sql has been run (it grants admin DELETE '
        'on profiles), then refresh and try again.',
      );
    }
  }

  /// Edit dialog for a driver or student profile (name + display email).
  ///
  /// A driver RENAME also follows their bus assignment: buses.driver_name
  /// stores the old name, and a mismatch would silently orphan an active
  /// assignment back into "no bus is assigned".
  Future<void> _editProfileDialog(
    Map<String, dynamic> profile, {
    required bool isDriver,
  }) async {
    final nameController =
        TextEditingController(text: '${profile['name'] ?? ''}');
    final emailController =
        TextEditingController(text: '${profile['email'] ?? ''}');

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Edit ${isDriver ? 'driver' : 'student'}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (display)',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'App profile only - the login email itself is managed in '
                  'Supabase Auth.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  // Override the theme's full-width minimum (actions row).
                  minimumSize: const Size(0, 40),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    final newName = nameController.text.trim();
    final newEmail = emailController.text.trim();
    nameController.dispose();
    emailController.dispose();
    if (!saved || !mounted) return;

    try {
      // `.select('id')` + emptiness: a zero-row write (RLS, stale id) must
      // not show a green "Profile updated".
      final updated = await supabase
          .from('profiles')
          .update({'name': newName, 'email': newEmail})
          .eq('id', profile['id'])
          .select('id');
      if (updated.isEmpty) {
        throw StateError('edit profile affected no rows');
      }
      // Follow the rename onto the bus - best effort (needs the buses
      // write policy), and never fails the profile save itself.
      final oldName = '${profile['name'] ?? ''}';
      if (isDriver && oldName.isNotEmpty && oldName != newName) {
        try {
          // By NAME, not via _assignedBusFor: EVERY row carrying the old
          // name must follow the rename, or a duplicate leaves an orphaned
          // assignment that still reads as "no bus is assigned".
          await supabase
              .from('buses')
              .update({'driver_name': newName})
              .eq('driver_name', oldName);
        } catch (e) {
          debugPrint('[admin] assignment follow-rename failed: $e');
        }
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] edit profile failed: $e');
      _showError(
        'Could not save the profile. Refresh and try again - the record '
        'may have already changed.',
      );
    }
  }

  Future<void> _loadBuses() async {
    // Outer join (not `!inner`) so a bus keeps rendering even if its route
    // row disappears, and the list can show the route NAME - the raw
    // route_id number meant nothing to an admin.
    final buses = await supabase
        .from('buses')
        .select('*, routes(route_name)')
        .order('bus_number', ascending: true);
    if (mounted) {
      setState(() => _buses = List<Map<String, dynamic>>.from(buses));
    }
  }

  /// Route label for a bus row: the route NAME first, the id only as a
  /// fallback (a missing route renders as "Unassigned"). An admin should not
  /// have to remember that route 7 is "North Campus".
  static String _busRouteLabel(Map<String, dynamic> bus) {
    final routes = bus['routes'];
    if (routes is Map && routes['route_name'] != null) {
      return 'Route: ${routes['route_name']}';
    }
    final routeId = bus['route_id'];
    return 'Route: ${routeId == null ? 'Unassigned' : '#$routeId'}';
  }

  Future<void> _deleteBus(int busId) async {
    try {
      // `.select('id')` + emptiness check: a zero-row DELETE (RLS, or the
      // bus was already gone) must not show a green "Bus deleted".
      final deleted = await supabase
          .from('buses')
          .delete()
          .eq('id', busId)
          .select('id');
      if (deleted.isEmpty) {
        throw StateError('delete bus affected no rows');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bus deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] delete bus failed: $e');
      _showError(
        'Could not delete the bus. Refresh and try again - '
        'it may have already been removed.',
      );
    }
  }

  Future<bool> _confirmDeleteBus(Map<String, dynamic> bus) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Bus'),
            content: Text(
                'Are you sure you want to delete bus ${bus['bus_number']}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  // Override the theme's full-width minimum: inside the
                  // actions row infinity clamps to the whole dialog width.
                  minimumSize: const Size(0, 40),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Edit dialog for an existing bus (number, route, status) - the other
  /// half of fleet management next to Add / Delete.
  Future<void> _editBusDialog(Map<String, dynamic> bus) async {
    // Snapshot: a refresh while the dialog is open must not rebuild the
    // dropdowns from a changing list (see _assignRouteDialog).
    final routes = List<Map<String, dynamic>>.from(_routes);
    if (routes.isEmpty) {
      _showError(
        'No routes loaded yet. Pull to refresh, then add a route first.',
      );
      return;
    }
    final busController =
        TextEditingController(text: '${bus['bus_number'] ?? ''}');
    // A bus whose route row was deleted must degrade to "pick one" -
    // passing its stale id as initialValue would assert in the dropdown.
    final currentRouteId = bus['route_id'];
    int? routeId = currentRouteId is int &&
            routes.any((r) => r['id'] == currentRouteId)
        ? currentRouteId
        : null;
    // Anything outside the two dropdown items ('maintenance', hand edits,
    // different casing) must degrade to 'active' - a foreign value as
    // initialValue asserts in the dropdown and renders it blank.
    String status = bus['status'] == 'inactive' ? 'inactive' : 'active';

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text('Edit bus ${bus['bus_number'] ?? ''}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: busController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Bus number',
                      prefixIcon: Icon(Icons.directions_bus),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: routeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Route',
                      prefixIcon: Icon(Icons.route),
                    ),
                    items: routes
                        .map(
                          (r) => DropdownMenuItem<int>(
                            value: r['id'] as int,
                            child: Text('${r['route_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => routeId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.toggle_on),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(
                          value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? 'active'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (busController.text.trim().isNotEmpty &&
                        routeId != null) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    // Override the theme's full-width minimum (actions row).
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    final newNumber = busController.text.trim();
    final newRouteId = routeId;
    final newStatus = status;
    busController.dispose();
    if (!saved || !mounted) return;

    try {
      // `.select('id')` + emptiness: a zero-row write (missing UPDATE
      // policy - supabase_admin_buses.sql - or a deleted bus) must not
      // show a green "Bus updated".
      final updated = await supabase
          .from('buses')
          .update({
            'bus_number': newNumber,
            'route_id': newRouteId,
            'status': newStatus,
          })
          .eq('id', bus['id'])
          .select('id');
      if (updated.isEmpty) {
        throw StateError('edit bus affected no rows');
      }
      await _guard(_loadBuses);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bus updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] edit bus failed: $e');
      _showError(
        'Could not save the bus. Make sure supabase_admin_buses.sql has '
        'been run (it grants admin write on buses), then try again.',
      );
    }
  }

  /// The bus row (raw) currently assigned to [driverName], or null when the
  /// driver holds no bus.
  Map<String, dynamic>? _assignedBusFor(String driverName) {
    for (final bus in _buses) {
      if (bus['driver_name'] == driverName) return bus;
    }
    return null;
  }

  /// One-line assignment summary shown under a driver's email - the admin
  /// sees at a glance who is on which bus/route without opening each bus.
  String _assignmentLabel(dynamic driverName) {
    if (driverName is! String || driverName.isEmpty) {
      return 'Not assigned to a route';
    }
    final bus = _assignedBusFor(driverName);
    if (bus == null) return 'Not assigned to a route';
    final routes = bus['routes'];
    final routeName = routes is Map ? routes['route_name'] : null;
    final busNo = bus['bus_number'] ?? bus['id'] ?? '?';
    // An INACTIVE bus reads as "assigned" here but as "no bus is
    // assigned" on the driver's dashboard (it filters status = active) -
    // label it instead of re-creating that exact confusion.
    final inactive = bus['status'] == 'active' ? '' : ' (inactive)';
    return routeName == null
        ? 'Assigned: Bus $busNo$inactive'
        : 'Assigned: Bus $busNo • $routeName$inactive';
  }

  /// Writes [driverName] onto bus [busId], clearing it from every other bus
  /// first - a driver drives ONE bus, and a stale second row would make the
  /// driver's dashboard auto-pick whichever matched first.
  ///
  /// Needs admin UPDATE on `buses` (supabase_admin_buses.sql).
  Future<void> _assignDriverToBus({
    required String driverName,
    required int busId,
  }) async {
    // New assignment FIRST, row-verified: the old order cleared every other
    // bus before knowing this write would land, so a target that matched
    // zero rows (bus deleted between dialog and save, RLS, dropped
    // connection) left the driver unassigned from BOTH buses - an end state
    // neither the admin nor the driver asked for.
    final changed = await supabase
        .from('buses')
        .update({'driver_name': driverName})
        .eq('id', busId)
        .select('id');
    if (changed.isEmpty) {
      throw StateError('assign affected no rows');
    }
    // `.select('id')` returns the rows actually affected: write RLS
    // filtered to zero rows (SQL not run) must never report a green
    // "assigned" over a no-op. Only AFTER the target is safely written do
    // we clear the driver's previous bus (one driver drives ONE bus - a
    // stale second row would make the dashboard auto-pick whichever
    // matched first).
    await supabase
        .from('buses')
        .update({'driver_name': null})
        .eq('driver_name', driverName)
        .neq('id', busId);
  }

  /// Clears [driverName] from every bus. An empty result IS success here:
  /// the desired end state is zero rows carrying this name.
  Future<void> _unassignDriver(String driverName) async {
    await supabase
        .from('buses')
        .update({'driver_name': null})
        .eq('driver_name', driverName);
  }

  /// Route + bus picker for one driver. Pops with `null` (cancelled),
  /// `'unassign'` (clear the driver from every bus) or the chosen `int`
  /// bus id - the caller performs the write and refreshes.
  ///
  /// Only ACTIVE buses are offered: an assignment to a retired bus would
  /// silently read as "no bus is assigned" on the driver's dashboard,
  /// which filters on status = active.
  Future<void> _assignRouteDialog(Map<String, dynamic> driver) async {
    final driverName = driver['name'];
    if (driverName is! String || driverName.isEmpty) {
      _showError('This driver has no name to assign against.');
      return;
    }
    // Snapshot: a refresh/realtime setState while the dialog is open must
    // not rebuild its dropdowns from a changing list (the stored value
    // would stop matching an item -> assert in debug, blank in release).
    final routes = List<Map<String, dynamic>>.from(_routes);
    final buses = List<Map<String, dynamic>>.from(_buses);
    if (routes.isEmpty) {
      _showError(
        'No routes loaded yet. Pull to refresh - a driver is assigned to a '
        'bus, and every bus sits on a route.',
      );
      return;
    }

    final current = _assignedBusFor(driverName);
    // Pre-fill with the CURRENT assignment when it is still valid (its
    // route exists and the bus is active) so re-saving is one tap; a
    // deleted route or a retired bus degrades to "pick one".
    int? selectedRouteId;
    int? selectedBusId;
    final currentRouteId = current?['route_id'];
    if (currentRouteId is int && routes.any((r) => r['id'] == currentRouteId)) {
      selectedRouteId = currentRouteId;
      final currentBusId = current?['id'];
      if (currentBusId is int && current?['status'] == 'active') {
        selectedBusId = currentBusId;
      }
    } else if (routes.first['id'] is int) {
      selectedRouteId = routes.first['id'] as int;
    }

    final action = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final routeBuses = buses
                .where((b) =>
                    b['route_id'] == selectedRouteId &&
                    b['status'] == 'active' &&
                    b['id'] is int)
                .toList();
            return AlertDialog(
              title: Text('Assign - $driverName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _assignmentLabel(driverName),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedRouteId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Route',
                      prefixIcon: Icon(Icons.route),
                    ),
                    items: routes
                        .where((r) => r['id'] is int)
                        .map(
                          (r) => DropdownMenuItem<int>(
                            value: r['id'] as int,
                            child: Text(
                              '${r['route_name'] ?? 'Route ${r['id']}'}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      selectedRouteId = v;
                      // Buses belong to one route: the previous pick is void.
                      selectedBusId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  // Keyed on the route so the field is REBUILT when the route
                  // changes: initialValue only seeds a FormField once, so
                  // without this the bus dropdown kept DISPLAYING the old
                  // bus while the variable behind it was already null.
                  DropdownButtonFormField<int>(
                    key: ValueKey('assign-bus-$selectedRouteId'),
                    initialValue: selectedBusId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Bus',
                      prefixIcon: Icon(Icons.directions_bus),
                    ),
                    items: routeBuses
                        .map(
                          (b) => DropdownMenuItem<int>(
                            value: b['id'] as int,
                            child: Text(
                              '${b['bus_number'] ?? 'Bus ${b['id']}'}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: routeBuses.isEmpty
                        ? null
                        : (v) => setDialogState(() => selectedBusId = v),
                  ),
                  if (routeBuses.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'No active bus on this route yet - add one with '
                      '"Add Bus" first.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[900],
                      ),
                    ),
                  ],
                  if (current != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('unassign'),
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Unassign from all buses'),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedBusId == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(selectedBusId),
                  style: ElevatedButton.styleFrom(
                    // Override the theme's full-width minimum: inside the
                    // actions row infinity clamps to the whole dialog width.
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );

    if (action == null || !mounted) return; // cancelled
    // Assignment is keyed on the free-text driver_name (the driver_id
    // migration is still pending): two drivers sharing a name would
    // cross-link - assigning or clearing ONE silently hits the other's bus
    // too, and both rows display the same assignment. Refuse before any
    // write instead of silently picking a victim; renaming one disambiguates.
    if (action is int || action == 'unassign') {
      final sameName = await _countDriversNamed(driverName);
      if (!mounted) return;
      if (sameName > 1) {
        _showError(
          'Several drivers are named "$driverName". Rename one of them '
          'first - otherwise this changes the bus of the wrong driver.',
        );
        return;
      }
    }
    try {
      if (action == 'unassign') {
        await _unassignDriver(driverName);
      } else if (action is int) {
        await _assignDriverToBus(driverName: driverName, busId: action);
      } else {
        return;
      }
      // Refresh buses so the driver rows (and the fleet list) show the new
      // assignment immediately.
      await _guard(_loadBuses);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'unassign'
                  ? '$driverName unassigned from all buses'
                  : '$driverName assigned to the selected bus',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] driver assignment failed: $e');
      _showError(
        'Could not save the assignment. Make sure supabase_admin_buses.sql '
        'has been run (it grants admin write on buses) and the bus still '
        'exists.',
      );
    }
  }

  /// How many driver-role profiles carry [name] - the cross-link guard for
  /// name-keyed bus assignment. Returns 0 on any read failure: the write
  /// path below still row-verifies, so a failed probe degrades to the old
  /// behavior rather than blocking assignments forever.
  Future<int> _countDriversNamed(String name) async {
    try {
      final rows = await supabase
          .from('profiles')
          .select('id')
          .eq('role', 'driver')
          .eq('name', name);
      return List<Map<String, dynamic>>.from(rows as List).length;
    } catch (e) {
      debugPrint('[admin] duplicate-name probe failed: $e');
      return 0;
    }
  }

  /// Universities for the route dialog's dropdown (id + name only).
  /// Throws on purpose: every caller is [_guard]-wrapped or catches
  /// locally, so a swallowed failure here would render an empty dropdown
  /// on a clean-looking dashboard with no Retry.
  Future<void> _loadUniversities() async {
    final unis = await supabase
        .from('universities')
        .select('id, name')
        .order('name', ascending: true);
    if (mounted) {
      setState(() => _universities = List<Map<String, dynamic>>.from(unis));
    }
  }

  /// Add / edit dialog for a route (name, optional university,
  /// optional description). Editing pops nothing destructive; the write
  /// itself is row-verified below.
  Future<void> _showRouteDialog({Map<String, dynamic>? route}) async {
    final isEdit = route != null;
    final formKey = GlobalKey<FormState>();
    // Snapshot: a refresh/realtime setState while the dialog is open must
    // not rebuild its dropdowns from a changing list (the stored value
    // would stop matching an item -> assert in debug, blank in release).
    final universities = List<Map<String, dynamic>>.from(_universities);
    final nameController =
        TextEditingController(text: '${route?['route_name'] ?? ''}');
    final descController =
        TextEditingController(text: '${route?['description'] ?? ''}');

    var uniLoadFailed = false;
    if (universities.isEmpty) {
      // First-open path: the dialog may be opened before a full refresh
      // has ever succeeded - try once so the dropdown is not mysteriously
      // empty. Failures stay quiet (the None option still works) - but see
      // the guard below: quiet is only safe when nothing can be wiped.
      try {
        await _loadUniversities();
      } catch (e) {
        uniLoadFailed = true;
        debugPrint('[admin] universities load for route dialog failed: $e');
      }
      if (!mounted) {
        nameController.dispose();
        descController.dispose();
        return;
      }
      universities.addAll(_universities);
    }

    // Prefill AFTER the lazy load above: computing it earlier (while the
    // list was still empty) showed "None" for a route that DID have a
    // university, and saving then silently wiped the link.
    // A route whose university row was deleted degrades to "None" -
    // a stale id as initialValue would assert in the dropdown.
    final currentUniId = route?['university_id'];
    // ...but when the LOAD failed, an absent id proves nothing: the
    // dropdown would offer only "None" and Save would write null - erasing
    // a link that still exists (the exact wipe the comment above
    // describes, reintroduced through the failure path). Abort instead.
    if (route != null &&
        currentUniId is int &&
        uniLoadFailed &&
        !universities.any((u) => u['id'] == currentUniId)) {
      nameController.dispose();
      descController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load universities - saving now would drop this '
            "route's university link. Pull to refresh and try again.",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    int? universityId =
        currentUniId is int && universities.any((u) => u['id'] == currentUniId)
            ? currentUniId
            : null;

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text(isEdit ? 'Edit Route' : 'Add Route'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Route name',
                        prefixIcon: Icon(Icons.route),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a route name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: universityId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'University (optional)',
                        prefixIcon: Icon(Icons.school),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...universities.map(
                          (u) => DropdownMenuItem<int?>(
                            value: u['id'] as int,
                            child: Text('${u['name']}'),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => universityId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        prefixIcon: Icon(Icons.notes),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    // Override the theme's full-width minimum (actions row).
                    minimumSize: const Size(0, 40),
                  ),
                  child: Text(isEdit ? 'Save' : 'Add'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    final newName = nameController.text.trim();
    final newDesc = descController.text.trim();
    nameController.dispose();
    descController.dispose();
    if (!saved || !mounted) return;

    try {
      final payload = <String, dynamic>{
        'route_name': newName,
        'description': newDesc.isEmpty ? null : newDesc,
        'university_id': universityId,
      };
      if (isEdit) {
        // `.select('id')` + emptiness: a zero-row write (missing policy -
        // supabase_admin_powers.sql - or a deleted route) must not show a
        // green "Route updated".
        final updated = await supabase
            .from('routes')
            .update(payload)
            .eq('id', route['id'])
            .select('id');
        if (updated.isEmpty) {
          throw StateError('update route affected no rows');
        }
      } else {
        final inserted =
            await supabase.from('routes').insert(payload).select('id');
        if (inserted.isEmpty) {
          throw StateError('insert route affected no rows');
        }
      }
      await _guard(_loadRoutes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Route updated' : 'Route added'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] save route failed: $e');
      _showError(
        'Could not save the route. Make sure supabase_admin_powers.sql '
        'has been run (it grants admin write on routes), then try again.',
      );
    }
  }

  Future<bool> _confirmDeleteRoute(Map<String, dynamic> route) async {
    // buses.route_id is ON DELETE CASCADE in the original schema: without
    // the supabase_admin_powers.sql FK change, deleting a route DELETES
    // its buses. The old text promised they would merely be "unassigned" -
    // exactly the quiet data loss this confirm exists to prevent.
    final busCount = _buses.where((b) => b['route_id'] == route['id']).length;
    final busWarning = busCount == 0
        ? ''
        : ' It also has $busCount ${busCount == 1 ? 'bus' : 'buses'} on it, '
            'which are deleted with it unless supabase_admin_powers.sql has '
            'been run (that script keeps them, unassigned).';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Route'),
            content: Text(
              'Delete ${route['route_name'] ?? 'this route'}? Its pickup '
              'points are deleted with it.$busWarning',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  // Override the theme's full-width minimum (actions row).
                  minimumSize: const Size(0, 40),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    try {
      // Row-verified: a zero-row delete (missing DELETE policy -
      // supabase_admin_powers.sql - or a stale id) must not report success.
      final deleted = await supabase
          .from('routes')
          .delete()
          .eq('id', route['id'])
          .select('id');
      if (deleted.isEmpty) {
        throw StateError('delete route affected no rows');
      }
      // Buses CASCADE with the route (see supabase_admin_powers.sql's FK
      // change to keep them), so the bus list AND the stat cards must
      // re-render too - the fleet count used to go stale here.
      await _guard(_loadRoutes);
      await _guard(_loadBuses);
      await _guard(_loadStats);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] delete route failed: $e');
      _showError(
        'Could not delete the route. Make sure supabase_admin_powers.sql '
        'has been run (it grants admin DELETE on routes), then try again.',
      );
    }
  }

  /// Routes for the "Add Bus" dialog, the Assign dialog and the Routes
  /// list. Throws on purpose: every caller is [_guard]-wrapped (or catches
  /// locally), so _refreshAll's error banner + Retry actually fire when
  /// this fails - the old internal catch reported "success" and rendered
  /// "No routes yet" on an error-free dashboard.
  Future<void> _loadRoutes() async {
    final routes = await supabase
        .from('routes')
        // University NAME joined so the Routes list is readable; the
        // dropdowns only read id/route_name, so extra keys are harmless.
        .select('id, route_name, description, university_id, universities(name)')
        .order('route_name', ascending: true);
    if (mounted) {
      setState(() => _routes = List<Map<String, dynamic>>.from(routes));
    }
  }

  /// Opens a small in-app map centred on an SOS / bus-issue location so the
  /// admin sees WHERE the report came from instead of raw coordinates they
  /// would have to plot by hand during an emergency.
  void _showLocationOnMap(String title, double lat, double lng) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(lat, lng),
                initialZoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.university_point_locator',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 44,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// True when [raw] can be read as a coordinate pair. Guards the map action
  /// so a malformed lat/lng from the backend cannot throw in the builder.
  static bool _hasCoords(dynamic lat, dynamic lng) =>
      lat is num && lng is num;

  /// "Add Bus" dialog: bus number + route + status, then inserts the row.
  Future<void> _showAddBusDialog() async {
    if (_routes.isEmpty) {
      _showError(
        'No routes loaded yet. Pull to refresh, then add a route first.',
      );
      return;
    }
    // Snapshot: a refresh while the dialog is open must not rebuild the
    // dropdown from a changing list (see _assignRouteDialog).
    final routes = List<Map<String, dynamic>>.from(_routes);
    final formKey = GlobalKey<FormState>();
    final busController = TextEditingController();
    int? selectedRouteId;
    String status = 'active';

    final added = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Add Bus'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: busController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Bus number',
                        hintText: 'e.g. LHS-1234',
                        prefixIcon: Icon(Icons.directions_bus),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a bus number'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedRouteId,
                      decoration: const InputDecoration(
                        labelText: 'Route',
                        prefixIcon: Icon(Icons.route),
                      ),
                      items: routes
                          .map(
                            (r) => DropdownMenuItem<int>(
                              value: r['id'] as int,
                              child: Text('${r['route_name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedRouteId = v),
                      validator: (v) => v == null ? 'Select a route' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.toggle_on),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'inactive', child: Text('Inactive')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => status = v ?? 'active'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    // Override the theme's full-width minimum: inside the
                    // actions row infinity clamps to the whole dialog width.
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (added) {
      await _addBus(busController.text.trim(), selectedRouteId, status);
    }
    busController.dispose();
  }

  Future<void> _addBus(String busNumber, int? routeId, String status) async {
    if (busNumber.isEmpty || routeId == null) return;
    try {
      // `.select('id')` returns the created row: a write that produced
      // nothing (RLS, constraint) must not show a green "Bus added".
      final inserted = await supabase
          .from('buses')
          .insert({
            'bus_number': busNumber,
            'route_id': routeId,
            'status': status,
          })
          .select('id');
      if (inserted.isEmpty) {
        throw StateError('add bus returned no row');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bus added'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] add bus failed: $e');
      _showError(
        'Could not add the bus. It may already exist, or a required field '
        'is missing - refresh and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          // Account menu: shows WHO is signed in and offers Sign out. A bare
          // logout icon gave no hint of which account held admin rights.
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Account',
            onSelected: (value) async {
              if (value == 'logout') {
                await _signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  supabase.auth.currentUser?.email ?? 'Administrator',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: _isLoading
            ? const CustomScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // Load-failure banner. Partial failures keep whatever DID load
              // on screen and say so, instead of a snackbar that disappears
              // over an empty-looking dashboard.
              if (_loadError != null) ...[
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off, color: Colors.red),
                    title: Text(_loadError!),
                    trailing: TextButton(
                      onPressed: _refreshAll,
                      child: const Text('Retry'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Stats Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      _plural(_totalStudents, 'Student', 'Students'),
                      _totalStudents,
                      Icons.school,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      _plural(_totalDrivers, 'Driver', 'Drivers'),
                      _totalDrivers,
                      Icons.directions_bus,
                      Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      _plural(_totalBuses, 'Bus', 'Buses'),
                      _totalBuses,
                      Icons.bus_alert,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // Tappable: opens the active-trip detail list (bus,
                    // route, driver, start time, live GPS signal). The bare
                    // count could not tell a rolling bus from an orphaned
                    // trip left behind by a killed app.
                    child: _buildStatCard(
                      _plural(_activeTrips, 'Active Trip', 'Active Trips'),
                      _activeTrips,
                      Icons.route,
                      Colors.purple,
                      onTap: _showActiveTripsSheet,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Stop editor entry point. Editing stop coordinates is how a
              // route is really maintained; without this the only way was
              // raw SQL, which is exactly how a stop ended up on the wrong
              // side of the city. The editor drops a pin on a map with a
              // live nearest-road check, so that mistake is now visible.
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.shade50,
                    child: const Icon(Icons.add_location_alt, color: Colors.purple),
                  ),
                  title: const Text(
                    'Manage Route Stops',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Add or move pickup points on a map with a live '
                    'off-road check',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StopEditorScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Pending Driver Approvals. ALWAYS rendered - header + count +
              // either the list or an empty state - so the admin always sees
              // where new sign-ups land. The old version hid the entire
              // section when empty, which looked like approval was broken.
              // The live profiles subscription keeps it current.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pending Driver Approvals',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_drivers.where((d) => d['is_approved'] != true).length} waiting',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._drivers
                  .where((d) => d['is_approved'] != true)
                  .map(
                    (driver) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.person,
                          color: Colors.orange,
                        ),
                        title: Text(driver['name'] ?? 'Driver'),
                        subtitle: Text(driver['email'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () => _approveDriver(driver['id']),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                // Compact: override the theme's full-width
                                // minimum so the buttons fit this Row without
                                // squeezing the name to ~50 dp.
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: const Text('Approve'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _rejectDriver(driver),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              if (!_drivers.any((d) => d['is_approved'] != true))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.how_to_reg,
                              size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'No drivers waiting for approval',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'New driver sign-ups appear here automatically.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Approved Drivers. Previously the admin could only see PENDING
              // drivers; approved ones were counted but invisible and could
              // not be managed. This lists them with a Revoke action so the
              // admin can fully control who can drive.
              if (_drivers.any((d) => d['is_approved'] == true)) ...[
                const Text(
                  'Approved Drivers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._drivers
                    .where((d) => d['is_approved'] == true)
                    .map(
                      (driver) {
                        final email = '${driver['email'] ?? ''}';
                        final assignment = _assignmentLabel(driver['name']);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(
                              Icons.person,
                              color: Colors.green,
                            ),
                            title: Text(driver['name'] ?? 'Driver'),
                            // Email + assignment: the admin sees at a glance
                            // WHO drives which bus / route - this is also the
                            // answer to the driver's "no bus is assigned"
                            // complaint (the assignment was simply missing).
                            subtitle: Text(
                              email.isEmpty
                                  ? assignment
                                  : '$email\n$assignment',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  onPressed: () => _assignRouteDialog(driver),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    // Compact: override the theme's full-width
                                    // minimum so it fits beside the menu.
                                    minimumSize: const Size(0, 40),
                                  ),
                                  child: const Text('Assign'),
                                ),
                                const SizedBox(width: 4),
                                // Edit / Revoke / Remove live in a menu: four
                                // trailing buttons would squeeze on a narrow
                                // phone (the exact bug class the Resolve
                                // buttons had).
                                PopupMenuButton<String>(
                                  tooltip: 'More actions',
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'edit':
                                        _editProfileDialog(
                                            driver, isDriver: true);
                                      case 'revoke':
                                        _unapproveDriver(driver);
                                      case 'delete':
                                        // Confirm first: one accidental tap
                                        // must not permanently remove an
                                        // account (the Reject path has the
                                        // same guard).
                                        final confirmed =
                                            await _confirmDeleteAccount(
                                                driver, roleNoun: 'Driver');
                                        if (confirmed) {
                                          await _deleteAccount(driver,
                                              roleNoun: 'Driver');
                                        }
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 20),
                                          SizedBox(width: 10),
                                          Text('Edit details'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'revoke',
                                      child: Row(
                                        children: [
                                          Icon(Icons.block,
                                              size: 20, color: Colors.orange),
                                          SizedBox(width: 10),
                                          Text('Revoke approval'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete,
                                              size: 20, color: Colors.red),
                                          SizedBox(width: 10),
                                          Text('Remove driver',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                const SizedBox(height: 24),
              ],

              // SOS Alerts Section
              const Text(
                'Active SOS Alerts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_sosAlerts.isEmpty)
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No active SOS alerts')),
                  ),
                )
              else
                ..._sosAlerts.map(
                  (alert) {
                    final lat = alert['latitude'];
                    final lng = alert['longitude'];
                    final canMap = _hasCoords(lat, lng);
                    return Card(
                      color: Colors.red.shade50,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.sos,
                          color: Colors.red,
                          size: 32,
                        ),
                        title: Text(alert['user_name'] ?? 'Unknown User'),
                        subtitle: Text(
                          '${canMap ? '📍 $lat, $lng' : '📍 Location unavailable'}\n'
                          '🕐 ${_formatDateTime(alert['created_at'])}'
                          '${canMap ? '\nTap to view on map' : ''}',
                        ),
                        // 3-line layout only when the map hint is shown.
                        isThreeLine: canMap,
                        // Tap the card to plot the SOS location on a map so
                        // the admin can see exactly where the help call came
                        // from (and navigate there) instead of reading raw
                        // coordinates.
                        onTap: canMap
                            ? () => _showLocationOnMap(
                                  'SOS from ${alert['user_name'] ?? 'Unknown'}',
                                  (lat as num).toDouble(),
                                  (lng as num).toDouble(),
                                )
                            : null,
                        trailing: ElevatedButton(
                          onPressed: () => _resolveSOS(alert['id']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            // The theme's full-width minimumSize
                            // (double.infinity) squeezes trailing buttons
                            // into the leftover slot, wrapping "Resolve"
                            // into a vertical column of letters.
                            // Size(0, ...) restores its intrinsic width -
                            // same override as the Approve/Reject buttons.
                            minimumSize: const Size(0, 40),
                          ),
                          child: const Text('Resolve'),
                        ),
                      ),
                    );
                  },
                ),

              // Bus Issue Reports (Fuel Empty / Bus Fault), reported from
              // the driver dashboard and delivered live like the SOS feed.
              const Text(
                'Bus Issue Reports',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_busIssues.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No active bus issue reports')),
                  ),
                )
              else
                ..._busIssues.map(
                  (issue) {
                    final isFuel = issue['issue_type'] == 'fuel_empty';
                    final rawBus = issue['bus_number'];
                    final busLabel = rawBus is String && rawBus.isNotEmpty
                        ? 'Bus $rawBus'
                        : 'Bus not selected';
                    final lat = issue['latitude'];
                    final lng = issue['longitude'];
                    final canMap = _hasCoords(lat, lng);
                    return Card(
                      color: Colors.orange.shade50,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isFuel ? Icons.local_gas_station : Icons.build,
                          color: isFuel ? Colors.orange : Colors.red,
                          size: 32,
                        ),
                        title: Text(
                          '${isFuel ? 'Fuel Empty' : 'Bus Fault'} - $busLabel',
                        ),
                        subtitle: Text(
                          '\uD83D\uDC64 ${issue['driver_name'] ?? 'Unknown driver'}\n'
                          '${canMap ? '\uD83D\uDCCD $lat, $lng' : '\uD83D\uDCCD Location unavailable'}\n'
                          '\uD83D\uDD50 ${_formatDateTime(issue['created_at'])}',
                        ),
                        isThreeLine: true,
                        // Tap to plot the breakdown / fuel-stop location.
                        onTap: canMap
                            ? () => _showLocationOnMap(
                                  '${isFuel ? 'Fuel Empty' : 'Bus Fault'} - $busLabel',
                                  (lat as num).toDouble(),
                                  (lng as num).toDouble(),
                                )
                            : null,
                        trailing: ElevatedButton(
                          onPressed: () => _resolveBusIssue(issue['id']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            // See the SOS card: the theme's full-width
                            // minimumSize wrapped "Resolve" vertically in
                            // the trailing slot.
                            minimumSize: const Size(0, 40),
                          ),
                          child: const Text('Resolve'),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              // Student roster. The dashboard showed drivers, buses and
              // live alerts but never WHO the students using the app are.
              // Read-only (name, email, joined), same is_admin() RLS path
              // as the driver list. Placed below the live sections so an
              // emergency always stays one short scroll away.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Student Accounts',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_students.length} enrolled',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_students.isEmpty)
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No student accounts yet')),
                  ),
                )
              else
                ..._students.map(
                  (student) {
                    final name = '${student['name'] ?? ''}'.trim();
                    final email = '${student['email'] ?? ''}';
                    final initials =
                        name.isEmpty ? '?' : name[0].toUpperCase();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(name.isEmpty ? 'Student' : name),
                        subtitle: Text(
                          email.isEmpty
                              ? 'Joined ${_formatDateTime(student['created_at'])}'
                              : '$email\nJoined ${_formatDateTime(student['created_at'])}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.blueGrey),
                              tooltip: 'Edit student',
                              onPressed: () =>
                                  _editProfileDialog(student, isDriver: false),
                            ),
                            // Promote: a rejected/removed driver silently
                            // re-registers as a student (safe default), and
                            // there was no way back to driver except SQL.
                            IconButton(
                              icon: const Icon(Icons.upgrade,
                                  color: Colors.teal),
                              tooltip: 'Make driver',
                              onPressed: () => _promoteToDriver(student),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red),
                              tooltip: 'Remove student',
                              onPressed: () async {
                                // Confirm first: one accidental tap must not
                                // permanently remove an account.
                                final confirmed = await _confirmDeleteAccount(
                                  student,
                                  roleNoun: 'Student',
                                );
                                if (confirmed) {
                                  await _deleteAccount(
                                    student,
                                    roleNoun: 'Student',
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              // All Buses Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'All Buses',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  // Add Bus: pairs with the delete action so the admin can
                  // manage the fleet from the UI (previously only deletion
                  // was possible). Pull-to-refresh covers reloading.
                  ElevatedButton.icon(
                    onPressed: _showAddBusDialog,
                    style: ElevatedButton.styleFrom(
                      // Override the theme's full-width minimum so the button
                      // fits this Row instead of stretching across it.
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Bus'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_buses.isEmpty)
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No buses found')),
                  ),
                )
              else
                ..._buses.map(
                  (bus) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.directions_bus,
                        color: Colors.orange,
                        size: 32,
                      ),
                      title: Text(bus['bus_number'] ?? 'Unknown'),
                      // Route NAME first - the raw id only as a fallback -
                      // plus the added-on date as a human date+time instead
                      // of the raw ISO timestamp.
                      subtitle: Text(
                        '${_busRouteLabel(bus)} • ${bus['status'] ?? 'active'}\n'
                        'Added ${_formatDateTime(bus['created_at'])}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit,
                                color: Colors.blueGrey),
                            tooltip: 'Edit bus',
                            onPressed: () => _editBusDialog(bus),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Delete bus',
                            onPressed: () async {
                              final confirmed =
                                  await _confirmDeleteBus(bus);
                              if (confirmed) {
                                _deleteBus(bus['id']);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Routes. Previously only editable via raw SQL (the app even
              // ships supabase_route_fix.sql as a manual one-off fix); the
              // admin can now add / edit / delete routes in-app. Writes
              // need supabase_admin_powers.sql.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Routes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showRouteDialog(),
                    style: ElevatedButton.styleFrom(
                      // Override the theme's full-width minimum so the
                      // button fits this Row.
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Route'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_routes.isEmpty)
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No routes yet')),
                  ),
                )
              else
                ..._routes.map(
                  (route) {
                    final uni = route['universities'];
                    final uniName = uni is Map ? uni['name'] : null;
                    final desc = '${route['description'] ?? ''}';
                    final details = <String>[
                      if (uniName != null && '$uniName'.isNotEmpty)
                        '$uniName',
                      if (desc.trim().isNotEmpty) desc.trim(),
                    ];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading:
                            const Icon(Icons.route, color: Colors.purple),
                        title: Text(
                          '${route['route_name'] ?? 'Unnamed route'}',
                        ),
                        subtitle: Text(
                          details.isEmpty ? 'No details' : details.join(' • '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.blueGrey),
                              tooltip: 'Edit route',
                              onPressed: () =>
                                  _showRouteDialog(route: route),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete route',
                              onPressed: () async {
                                final confirmed =
                                    await _confirmDeleteRoute(route);
                                if (confirmed) {
                                  await _deleteRoute(route);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "1 Buses" reads as a bug in a list the admin reads during an incident:
  /// every count label next to a number is singular/plural aware.
  static String _plural(int count, String singular, String plural) =>
      count == 1 ? singular : plural;

  Widget _buildStatCard(
    String title,
    int value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(title, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
    return Card(
      elevation: 2,
      // Clip so the ripple stays inside the rounded card corners.
      clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }

  /// Promote a student row back to driver. A rejected or removed driver
  /// re-registers as a student on next login (the safe default for a
  /// missing profile row), so without this the only way back to a driver
  /// account was raw SQL. The new driver starts unapproved and must be
  /// approved from the drivers list - same gate as a fresh signup.
  Future<void> _promoteToDriver(Map<String, dynamic> student) async {
    final name = '${student['name'] ?? ''}'.trim();
    final label = name.isEmpty ? 'this student' : name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Make $label a driver?'),
        content: Text(
          '$label will keep the same login, but switch to the driver '
          'dashboard. They must be approved again from the Driver '
          'Accounts list before they can drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              // Bounded override: the theme's full-width minimum
              // wraps inside a dialog action row.
              minimumSize: const Size(0, 40),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Make driver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final id = student['id'];
      if (id is! String) throw Exception('student row has no id');
      final updated = await supabase
          .from('profiles')
          .update({'role': 'driver', 'is_approved': false})
          .eq('id', id)
          .select('id');
      if (updated.isEmpty) {
        // Row-verified miss: removed elsewhere between list and tap.
        throw Exception('profile row no longer exists');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label is now a pending driver - approve from the drivers '
            'list.',
          ),
        ),
      );
      await _refreshAll();
    } catch (e) {
      debugPrint('[admin] promote to driver failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not promote $label. Pull to refresh and try '
              'again.'),
        ),
      );
    }
  }

  /// Detail list behind the "Active Trips" stat card. The bare count told
  /// the admin nothing: an orphaned trip (app killed mid-drive, End Trip
  /// failed offline) sits at "active" forever and looks exactly like a bus
  /// that is genuinely rolling right now.
  Future<void> _showActiveTripsSheet() async {
    // Refresh the headline count too - it only reloads on pull-to-refresh
    // otherwise, so the card could disagree with the list below it.
    // Fire-and-forget: the sheet loads its own fresh copy either way.
    _guard(_loadStats);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => _ActiveTripsSheet(
          scrollController: scrollController,
        ),
      ),
    );
  }
}

/// One row of the admin "Active Trips" detail list.
class _ActiveTripRow {
  const _ActiveTripRow({
    required this.id,
    required this.busLabel,
    required this.routeName,
    required this.driverLabel,
    required this.started,
    required this.lastSignal,
  });

  /// trips.id - needed to close the row server-side.
  final int id;

  final String busLabel;
  final String routeName;
  final String driverLabel;
  final DateTime? started;

  /// Newest bus_locations row for this bus, if any arrived at all.
  final DateTime? lastSignal;
}

/// Detail list behind the Active Trips stat card: WHO is driving WHICH bus
/// on WHICH route, when the trip started, and whether the bus is actually
/// sending GPS - the distinction the bare count could not make.
class _ActiveTripsSheet extends StatefulWidget {
  const _ActiveTripsSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_ActiveTripsSheet> createState() => _ActiveTripsSheetState();
}

class _ActiveTripsSheetState extends State<_ActiveTripsSheet> {
  final supabase = Supabase.instance.client;

  List<_ActiveTripRow>? _trips;
  bool _loading = true;
  String? _error;

  /// Keeps the list honest while the sheet is open - a trip can be closed
  /// by its driver on another phone at any moment, and the GPS badges age
  /// in real time.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// [silent] refreshes keep the current view up (no spinner flash) so the
  /// sheet does not flicker every 15 seconds.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // Bus and route embed via their foreign keys on trips; start_time can
      // be NULL (rows written before defaults settled) - rendered as
      // "unknown" instead of being dropped.
      final rows = await supabase
          .from('trips')
          .select(
            'id, driver_id, bus_id, start_time, buses(bus_number), routes(route_name)',
          )
          .eq('status', 'active')
          .order('start_time', ascending: true);
      final trips = List<Map<String, dynamic>>.from(rows as List);

      // Driver names in one batch: trips.driver_id carries no FK to
      // profiles, so PostgREST cannot embed it. Best effort - a missing
      // profile degrades to a short user id instead of failing the sheet.
      final driverIds =
          trips.map((t) => t['driver_id']).whereType<String>().toSet().toList();
      final names = <String, String>{};
      if (driverIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('id, name')
              .inFilter('id', driverIds);
          for (final p in profiles as List) {
            final id = p['id'];
            if (id is String) names[id] = '${p['name'] ?? ''}';
          }
        } catch (e) {
          debugPrint('[admin] active-trip driver names failed: $e');
        }
      }

      // Newest signal per bus: newest-first + capped, then reduced
      // client-side - bus_locations keeps every historical row, so scanning
      // it all would be wasteful for a handful of buses.
      final busIds =
          trips.map((t) => t['bus_id']).whereType<int>().toSet().toList();
      final lastSignal = <int, DateTime>{};
      if (busIds.isNotEmpty) {
        try {
          final locs = await supabase
              .from('bus_locations')
              .select('bus_id, timestamp')
              .inFilter('bus_id', busIds)
              .order('timestamp', ascending: false)
              .limit(200);
          for (final l in locs as List) {
            final busId = l['bus_id'];
            final ts = l['timestamp'];
            if (busId is! int || ts is! String) continue;
            final parsed = DateTime.tryParse(ts);
            // First row per bus wins: the list is already newest-first.
            if (parsed != null) lastSignal.putIfAbsent(busId, () => parsed);
          }
        } catch (e) {
          debugPrint('[admin] active-trip signal lookup failed: $e');
        }
      }

      final built = trips.map((t) {
        final bus = t['buses'];
        final route = t['routes'];
        final driverId = t['driver_id'];
        final busId = t['bus_id'];
        final startedRaw = t['start_time'];
        final name = driverId is String ? names[driverId] : null;
        final tripId = t['id'];
        return _ActiveTripRow(
          id: tripId is int ? tripId : -1,
          busLabel: bus is Map && bus['bus_number'] != null
              ? 'Bus ${bus['bus_number']}'
              : 'Bus (deleted)',
          routeName: route is Map && route['route_name'] != null
              ? '${route['route_name']}'
              : 'Route (deleted)',
          driverLabel: (name != null && name.trim().isNotEmpty)
              ? name.trim()
              : driverId is String && driverId.length >= 8
                  ? 'Driver (${driverId.substring(0, 8)})'
                  : 'Unknown driver',
          started: startedRaw is String ? DateTime.tryParse(startedRaw) : null,
          lastSignal: busId is int ? lastSignal[busId] : null,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _trips = built;
        _loading = false;
        // A silent pass that recovers from a transient error clears the
        // banner by simply succeeding.
        if (silent) _error = null;
      });
    } catch (e) {
      debugPrint('[admin] active trips load failed: $e');
      if (!mounted) return;
      if (silent) return; // keep the last good view; retry next tick
      setState(() {
        _loading = false;
        _error = 'Could not load active trips. Check your connection.';
      });
    }
  }

  /// Close an orphaned trip the driver's own app can no longer end (killed
  /// mid-drive, End Trip failed offline). Only a driver can normally update
  /// their own trip row - this relies on the admin policy from
  /// supabase_admin_powers.sql.
  Future<void> _closeTrip(_ActiveTripRow trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Close ${trip.busLabel}?'),
        content: Text(
          '${trip.driverLabel}' 's trip on ${trip.routeName} will be marked '
          'completed with the distance unknown. Use this when the bus is '
          'not actually driving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              // Bounded override: the theme's full-width minimum
              // wraps inside a dialog action row.
              minimumSize: const Size(0, 40),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close trip'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updated = await supabase
          .from('trips')
          .update({'status': 'completed', 'end_time': DateTime.now().toUtc().toIso8601String()})
          .eq('id', trip.id)
          .eq('status', 'active') // never reopen a row closed elsewhere
          .select('id');
      if (updated.isEmpty) {
        // Row-verified miss. Distinguish "someone already closed it" from
        // "the admin UPDATE policy is missing" (supabase_admin_powers.sql)
        // before claiming anything - every other mutation here throws on an
        // empty result, and reporting "Closed trip!" over a zero-row write
        // told the admin an orphan was handled while it stayed active.
        final row = await supabase
            .from('trips')
            .select('status')
            .eq('id', trip.id)
            .maybeSingle();
        if (!mounted) return;
        if (row == null || row['status'] != 'active') {
          debugPrint('[admin] trip ${trip.id} already closed elsewhere');
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That trip was already closed.')),
          );
          return;
        }
        throw StateError('close trip affected no rows');
      }
      await _load(); // fresh list + count for the header
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Closed ${trip.busLabel} trip.')),
      );
    } catch (e) {
      debugPrint('[admin] close trip failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not close that trip. Check your connection.'),
        ),
      );
    }
  }

  static String _fmtClock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  String _fmtStarted(DateTime? started, DateTime now) {
    if (started == null) return 'Start time unknown';
    final clock = _fmtClock(started);
    final sameDay = started.year == now.year &&
        started.month == now.month &&
        started.day == now.day;
    final elapsed = now.difference(started);
    final String ago;
    if (elapsed.inMinutes < 1) {
      ago = 'just now';
    } else if (elapsed.inMinutes < 60) {
      ago = '${elapsed.inMinutes} min ago';
    } else if (elapsed.inHours < 24) {
      ago = '${elapsed.inHours}h ${elapsed.inMinutes.remainder(60)}m ago';
    } else {
      ago = '${elapsed.inDays}d ago';
    }
    final dayLabel =
        '${started.day.toString().padLeft(2, '0')}.${started.month.toString().padLeft(2, '0')}';
    return sameDay ? 'Started $clock • $ago' : 'Started $dayLabel $clock • $ago';
  }

  Widget _signalBadge(DateTime? lastSignal, DateTime now) {
    if (lastSignal == null) {
      return Text(
        'No GPS signal yet',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }
    final age = now.difference(lastSignal);
    final Color color;
    final String label;
    if (age.inMinutes < 3) {
      color = Colors.green;
      label = age.inSeconds < 60 ? '● Live' : '● Live • ${age.inSeconds}s ago';
    } else if (age.inMinutes < 15) {
      color = Colors.orange;
      label = '● Last signal ${age.inMinutes} min ago';
    } else {
      color = Colors.red;
      label = age.inMinutes < 60
          ? '● Last signal ${age.inMinutes} min ago'
          : '● Last signal ${age.inHours}h ${age.inMinutes.remainder(60)}m ago';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _trips == null || _loading
                      ? 'Active trips'
                      : 'Active trips (${_trips!.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off,
                                size: 48, color: Colors.orange.shade700),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                // Bounded override: the theme's
                                // full-width minimum wraps this button.
                                minimumSize: const Size(0, 40),
                              ),
                            ),
                          ],
                        ),
                      )
                    : (_trips == null || _trips!.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions_bus_filled,
                                    size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                const Text(
                                  'No active trips right now',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'A trip appears here the moment a driver '
                                  'taps Start Trip.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: widget.scrollController,
                            itemCount: _trips!.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final trip = _trips![index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.purple.shade50,
                                  child: const Icon(
                                    Icons.directions_bus,
                                    color: Colors.purple,
                                  ),
                                ),
                                title: Text(
                                  '${trip.busLabel} • ${trip.routeName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(trip.driverLabel),
                                    const SizedBox(height: 2),
                                    Text(
                                      _fmtStarted(trip.started, now),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    _signalBadge(trip.lastSignal, now),
                                  ],
                                ),
                                // Orphan killer: end a trip the driver's own
                                // app can no longer close.
                                trailing: trip.id < 0
                                    ? null
                                    : IconButton(
                                        tooltip: 'Close trip',
                                        icon: Icon(
                                          Icons.stop_circle_outlined,
                                          color: Colors.red.shade400,
                                        ),
                                        onPressed: () => _closeTrip(trip),
                                      ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
