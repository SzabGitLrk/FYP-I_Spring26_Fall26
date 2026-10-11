import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripHistory extends StatefulWidget {
  const TripHistory({super.key});

  @override
  State<TripHistory> createState() => _TripHistoryState();
}

class _TripHistoryState extends State<TripHistory> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;

  /// Set on failure so the body can tell "failed" from "genuinely empty" -
  /// both used to render the same confident "No trips found".
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _error = 'You are not signed in.';
            _isLoading = false;
          });
        }
        return;
      }
      // Own trips only: RLS should block other drivers' rows anyway, but the
      // explicit filter keeps the screen correct regardless of RLS state.
      // Outer join on purpose: `routes!inner(...)` silently HID every trip
      // whose route row was deleted (trips.route_id is ON DELETE SET NULL),
      // so a driver's completed history vanished from the app.
      final trips = await supabase
          .from('trips')
          .select('*, routes(route_name)')
          .eq('driver_id', userId)
          .order('start_time', ascending: false);
      if (mounted) {
        setState(() {
          _trips = List<Map<String, dynamic>>.from(trips);
          _isLoading = false;
        });
      }
    } catch (e) {
      // Raw exception text goes to the log, never to the UI.
      debugPrint('[trips] load failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not load your trips. Check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  /// Null-safe: with the outer join, `routes` is null for exactly the trips
  /// whose route was deleted - the builder's own index keeps the fallback
  /// label stable (the old `_trips.indexOf(trip)` was O(n), broke on
  /// duplicate maps, and could never run for those rows behind an inner join).
  String _getRouteName(Map<String, dynamic> trip, int index) {
    final routes = trip['routes'];
    if (routes is Map && routes['route_name'] != null) {
      return '${routes['route_name']}';
    }
    return 'Trip #${index + 1}';
  }

  String _calculateDuration(Map<String, dynamic> trip) {
    if (trip['start_time'] == null) return 'N/A';
    // tryParse, not parse: one malformed backend row must not throw inside
    // build() and red-screen the whole page.
    final start = DateTime.tryParse('${trip['start_time']}');
    if (start == null) return 'N/A';
    if (trip['end_time'] != null) {
      final end = DateTime.tryParse('${trip['end_time']}');
      if (end == null) return 'N/A';
      final diff = end.difference(start);
      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      return '${hours}h ${minutes}m';
    }
    return 'In progress';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrips,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadTrips,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : _trips.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No trips found',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTrips,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _trips.length,
                    itemBuilder: (context, index) {
                      final trip = _trips[index];
                      final date = trip['start_time'] != null
                          ? DateTime.tryParse('${trip['start_time']}')
                              ?.toLocal()
                          : null;
                      final distance = trip['distance_km'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[100],
                            child: Text('${index + 1}'),
                          ),
                          title: Text(_getRouteName(trip, index)),
                          subtitle: Text(
                            date != null
                                ? '${date.day}/${date.month}/${date.year} • ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
                                : 'Date unknown',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (distance != null)
                                Chip(
                                  label: Text(
                                      '${distance.toStringAsFixed(1)} km'),
                                  backgroundColor: Colors.green[50],
                                  labelStyle: const TextStyle(fontSize: 11),
                                ),
                              Text(
                                _calculateDuration(trip),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
