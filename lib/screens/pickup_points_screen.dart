import 'package:flutter/material.dart';
import 'package:university_point_locator/models/route_model.dart';
import 'package:university_point_locator/services/supabase_service.dart';
import 'package:university_point_locator/models/pickup_point.dart';
import 'package:university_point_locator/screens/map_screen.dart';

class PickupPointsScreen extends StatefulWidget {
  final RouteModel route;

  const PickupPointsScreen({super.key, required this.route});

  @override
  State<PickupPointsScreen> createState() => _PickupPointsScreenState();
}

class _PickupPointsScreenState extends State<PickupPointsScreen> {
  final SupabaseService _service = SupabaseService();
  List<PickupPoint> _pickupPoints = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPickupPoints();
  }

  Future<void> _loadPickupPoints() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final points = await _service.getPickupPointsForRoute(widget.route.id);
      if (!mounted) return;
      setState(() {
        _pickupPoints = points;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pickup Points',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.route.routeName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              if (_pickupPoints.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapScreen(
                      route: widget.route,
                      pickupPoints: _pickupPoints,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No pickup points to show on map'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            tooltip: 'Live Tracking',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            SizedBox(height: 16),
            Text('Loading pickup points...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 60,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Error Loading Pickup Points',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadPickupPoints,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_pickupPoints.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off,
                color: Colors.orange,
                size: 60,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Pickup Points Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Add pickup points in Supabase Dashboard for ${widget.route.routeName}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadPickupPoints,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPickupPoints,
      color: Colors.blue,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pickupPoints.length,
        itemBuilder: (context, index) {
          final point = _pickupPoints[index];
          final isFirst = point.orderIndex == 1;
          final isLast = point.orderIndex == _pickupPoints.length;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                // Show details in a dialog
                _showPointDetails(point);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Order indicator with special styling for first/last
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isFirst
                            ? Colors.green[100]
                            : isLast
                            ? Colors.red[100]
                            : Colors.orange[100],
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: isFirst
                              ? Colors.green
                              : isLast
                              ? Colors.red
                              : Colors.orange,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${point.orderIndex}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isFirst
                                ? Colors.green
                                : isLast
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Point details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            point.pointName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (point.landmark != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    point.landmark!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (point.address != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    point.address!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ETA if available
                    if (point.estimatedTimeFromPrevious != null) ...[
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          const Icon(Icons.timer, size: 16, color: Colors.blue),
                          Text(
                            '${point.estimatedTimeFromPrevious} min',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPointDetails(PickupPoint point) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(point.pointName),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(
                  Icons.confirmation_number,
                  'Stop #${point.orderIndex}',
                ),
                if (point.landmark != null)
                  _buildDetailRow(Icons.info_outline, point.landmark!),
                if (point.address != null)
                  _buildDetailRow(Icons.location_on, point.address!),
                _buildDetailRow(
                  Icons.pin_drop,
                  'Lat: ${point.latitude.toStringAsFixed(4)}',
                ),
                _buildDetailRow(
                  Icons.pin_drop,
                  'Lng: ${point.longitude.toStringAsFixed(4)}',
                ),
                if (point.estimatedTimeFromPrevious != null)
                  _buildDetailRow(
                    Icons.timer,
                    '${point.estimatedTimeFromPrevious} min from previous stop',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            // ✅ UPDATED: Working map button in dialog
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapScreen(
                      route: widget.route,
                      pickupPoints: _pickupPoints,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('View on Map'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
