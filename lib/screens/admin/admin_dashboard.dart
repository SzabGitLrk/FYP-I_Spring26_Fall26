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
  int _pendingDrivers = 0;
  List<Map<String, dynamic>> _sosAlerts = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _buses = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadSOSAlerts();
    _loadDrivers();
    _loadBuses();
  }

  Future<void> _loadStats() async {
    try {
      if (!mounted) return;
      final students = await supabase
          .from('profiles')
          .select()
          .eq('role', 'student');
      if (!mounted) return;
      final drivers = await supabase
          .from('profiles')
          .select()
          .eq('role', 'driver');
      if (!mounted) return;
      final buses = await supabase.from('buses').select();
      if (!mounted) return;
      final trips = await supabase.from('trips').select().eq('status', 'active');

      if (!mounted) return;
      setState(() {
        _totalStudents = students.length;
        _totalDrivers = drivers.length;
        _totalBuses = buses.length;
        _activeTrips = trips.length;
        _pendingDrivers = drivers.where((d) => d['is_approved'] == false).length;
      });
    } catch (_) {}
  }

  Future<void> _loadSOSAlerts() async {
    try {
      final alerts = await supabase
          .from('sos_alerts')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() => _sosAlerts = List<Map<String, dynamic>>.from(alerts));
      }
    } catch (_) {}
  }

  Future<void> _loadDrivers() async {
    try {
      final drivers = await supabase
          .from('profiles')
          .select()
          .eq('role', 'driver');

      if (mounted) {
        setState(() => _drivers = List<Map<String, dynamic>>.from(drivers));
      }
    } catch (_) {}
  }

  Future<void> _approveDriver(String driverId) async {
    try {
      await supabase
          .from('profiles')
          .update({'is_approved': true})
          .eq('id', driverId);
      await _loadDrivers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver approved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _resolveSOS(int alertId) async {
    try {
      await supabase
          .from('sos_alerts')
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', alertId);
      await _loadSOSAlerts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS resolved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _rejectDriver(String driverId) async {
    try {
      await supabase
          .from('profiles')
          .update({'is_approved': false})
          .eq('id', driverId);
      await _loadDrivers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadBuses() async {
    try {
      final buses = await supabase.from('buses').select().order('bus_number');
      if (mounted) {
        setState(() => _buses = List<Map<String, dynamic>>.from(buses));
      }
    } catch (_) {}
  }

  Future<void> _deleteBus(int busId) async {
    try {
      await supabase.from('buses').delete().eq('id', busId);
      await _loadBuses();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bus deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {}
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
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStats();
          await _loadSOSAlerts();
          await _loadDrivers();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              // Pending Approvals Section
              if (_pendingDrivers > 0) ...[
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
                        '📍 ${alert['latitude']}, ${alert['longitude']}\n🕐 ${DateTime.parse(alert['created_at']).toLocal()}',
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
                    onPressed: _loadBuses,
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
