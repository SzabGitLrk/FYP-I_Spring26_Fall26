import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshAll(initial: true);
    _subscribeToSOS();
  }

  @override
  void dispose() {
    final channel = _sosChannel;
    if (channel != null) supabase.removeChannel(channel);
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

  Future<void> _loadDrivers() async {
    final drivers = await supabase
        .from('profiles')
        .select()
        .eq('role', 'driver');

    if (mounted) {
      setState(() => _drivers = List<Map<String, dynamic>>.from(drivers));
    }
  }

  Future<void> _approveDriver(String driverId) async {
    try {
      await supabase
          .from('profiles')
          .update({'is_approved': true})
          .eq('id', driverId);
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
      _showError('Could not approve driver: $e');
    }
  }

  /// `created_at` arrives straight from the backend: one null or malformed
  /// value must not throw inside build() and take every other SOS card
  /// down with it.
  static String _formatSosTime(dynamic raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}');
    if (parsed == null) return '—';
    return '${parsed.toLocal()}';
  }

  Future<void> _resolveSOS(int alertId) async {
    try {
      await supabase
          .from('sos_alerts')
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', alertId);
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
      _showError('Could not resolve SOS alert: $e');
    }
  }

  Future<void> _rejectDriver(String driverId) async {
    try {
      await supabase
          .from('profiles')
          .update({'is_approved': false})
          .eq('id', driverId);
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
      _showError('Could not reject driver: $e');
    }
  }

  Future<void> _loadBuses() async {
    final buses = await supabase
        .from('buses')
        .select()
        .order('bus_number', ascending: true);
    if (mounted) {
      setState(() => _buses = List<Map<String, dynamic>>.from(buses));
    }
  }

  Future<void> _deleteBus(int busId) async {
    try {
      await supabase.from('buses').delete().eq('id', busId);
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
      _showError('Could not delete bus: $e');
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
                // error and the admin saw no feedback at all.
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Could not sign out: $e'),
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
                      'Students',
                      _totalStudents,
                      Icons.school,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Drivers',
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
                      'Buses',
                      _totalBuses,
                      Icons.bus_alert,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Active Trips',
                      _activeTrips,
                      Icons.route,
                      Colors.purple,
                    ),
                  ),
                ],
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
                        '🕐 ${_formatSosTime(alert['created_at'])}',
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
                      subtitle: Text(
                        'Route: ${bus['route_id'] ?? 'N/A'} • ${bus['status'] ?? 'active'}',
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
