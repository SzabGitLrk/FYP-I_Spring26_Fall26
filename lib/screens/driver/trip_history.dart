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

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _isLoading = true);
    try {
      final trips = await supabase
          .from('trips')
          .select('*, routes!inner(route_name)')
          .order('start_time', ascending: false);
      if (mounted) {
        setState(() {
          _trips = List<Map<String, dynamic>>.from(trips);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading trips: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getRouteName(Map<String, dynamic> trip) {
    if (trip['routes'] != null && trip['routes']['route_name'] != null) {
      return trip['routes']['route_name'];
    }
    return 'Trip #${_trips.indexOf(trip) + 1}';
  }

  String _calculateDuration(Map<String, dynamic> trip) {
    if (trip['start_time'] == null) return 'N/A';
    final start = DateTime.parse(trip['start_time']);
    if (trip['end_time'] != null) {
      final end = DateTime.parse(trip['end_time']);
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
                          ? DateTime.parse(trip['start_time']).toLocal()
                          : null;
                      final distance = trip['distance_km'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[100],
                            child: Text('${index + 1}'),
                          ),
                          title: Text(_getRouteName(trip)),
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
