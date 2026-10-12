import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _refreshAll(initial: true);
    _subscribeToSOS();
    _subscribeToBusIssues();
  }

  @override
  void dispose() {
    final channel = _sosChannel;
    if (channel != null) supabase.removeChannel(channel);
    final issues = _issuesChannel;
    if (issues != null) supabase.removeChannel(issues);
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
      _guard(_loadBuses),
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

  Future<void> _loadDrivers() async {
    // Explicit ascending name order: supabase-dart's .order() defaults to
    // DESCENDING, which would list drivers Z->A.
    final drivers = await supabase
        .from('profiles')
        .select()
        .eq('role', 'driver')
        .order('name', ascending: true);

    if (mounted) {
      setState(() => _drivers = List<Map<String, dynamic>>.from(drivers));
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

  Future<void> _rejectDriver(String driverId) async {
    try {
      // See _approveDriver: verify the write actually affected a row.
      final updated = await supabase
          .from('profiles')
          .update({'is_approved': false})
          .eq('id', driverId)
          .select('id');
      if (updated.isEmpty) {
        throw StateError('reject driver affected no rows');
      }
      await _refreshAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('[admin] reject driver failed: $e');
      _showError(
        'Could not reject the driver. Refresh and try again - '
        'the record may have already changed.',
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
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Capture before the await: both outlive this State, so they
              // stay valid even if the widget is disposed mid-request.
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await supabase.auth.signOut();
              } catch (e) {
                // Without this the failure escaped as an unhandled async
                // error and the admin saw no feedback at all. Raw exception
                // text goes to the log, never to the screen.
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
            },
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
                    child: _buildStatCard(
                      _plural(_activeTrips, 'Active Trip', 'Active Trips'),
                      _activeTrips,
                      Icons.route,
                      Colors.purple,
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

              // Pending Approvals Section. Derived from `_drivers` - the same
              // list the cards below render - because the old `_pendingDrivers`
              // snapshot lived in _loadStats(), which approve/reject never
              // refreshed: the header could sit above an empty section after
              // the last approval (and `== false` ignored a NULL is_approved,
              // while the list filter below counts it).
              if (_drivers.any((d) => d['is_approved'] != true)) ...[
                const Text(
                  'Pending Driver Approvals',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () =>
                                    _approveDriver(driver['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text('Approve'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () =>
                                    _rejectDriver(driver['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                  (alert) => Card(
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
                        '📍 ${alert['latitude']}, ${alert['longitude']}\n'
                        '🕐 ${_formatDateTime(alert['created_at'])}',
                      ),
                      trailing: ElevatedButton(
                        onPressed: () => _resolveSOS(alert['id']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Resolve'),
                      ),
                    ),
                  ),
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
                          '\uD83D\uDCCD ${issue['latitude']}, ${issue['longitude']}\n'
                          '\uD83D\uDD50 ${_formatDateTime(issue['created_at'])}',
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () => _resolveBusIssue(issue['id']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          child: const Text('Resolve'),
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
                  TextButton(
                    onPressed: _refreshAll,
                    child: const Text('Refresh'),
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
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirmed =
                              await _confirmDeleteBus(bus);
                          if (confirmed) {
                            _deleteBus(bus['id']);
                          }
                        },
                        tooltip: 'Delete bus',
                      ),
                    ),
                  ),
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

  Widget _buildStatCard(String title, int value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
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
      ),
    );
  }
}
