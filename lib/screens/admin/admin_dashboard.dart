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
    _refreshAll(initial: true);
    // Routes feed the "Add Bus" dropdown and change rarely, so they load
    // once here rather than on every pull-to-refresh.
    _loadRoutes();
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

  /// Routes for the "Add Bus" dropdown. Fails quietly (the dialog simply
  /// shows an empty dropdown the admin can retry via pull-to-refresh).
  Future<void> _loadRoutes() async {
    try {
      final routes = await supabase
          .from('routes')
          .select('id, route_name')
          .order('route_name', ascending: true);
      if (mounted) {
        setState(() => _routes = List<Map<String, dynamic>>.from(routes));
      }
    } catch (e) {
      debugPrint('[admin] load routes failed: $e');
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
                      items: _routes
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
                                // minimum so the buttons fit this Row.
                                minimumSize: const Size(0, 40),
                              ),
                              child: const Text('Approve'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _rejectDriver(driver['id']),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 40),
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
                      (driver) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(
                            Icons.person,
                            color: Colors.green,
                          ),
                          title: Text(driver['name'] ?? 'Driver'),
                          subtitle: Text(driver['email'] ?? ''),
                          trailing: TextButton.icon(
                            onPressed: () => _rejectDriver(driver['id']),
                            icon: const Icon(Icons.block, color: Colors.red),
                            label: const Text(
                              'Revoke',
                              style: TextStyle(color: Colors.red),
                            ),
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
