import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/pickup_point.dart';
import '../../models/route_model.dart';
import '../../models/university.dart';
import '../../services/route_service.dart';
import '../../services/supabase_service.dart';

/// Admin tool for adding / editing / deleting a route's stops on a map.
///
/// The whole point is to make the "Qamber" class of mistake - a stop typed
/// into SQL on the wrong side of the city, or 100+ m off any road -
/// visually impossible. The admin picks a route, drops a pin (tap the map or
/// drag the marker), sees the live distance to the nearest road, and saves.
/// A stop far off-road is warned about before it can be written.
///
/// Requires an admin RLS policy on `pickup_points` (see
/// `supabase_admin_stops.sql`); a non-admin sees a clear save failure.
class StopEditorScreen extends StatefulWidget {
  const StopEditorScreen({super.key});

  @override
  State<StopEditorScreen> createState() => _StopEditorScreenState();
}

/// One university + route pair in the route picker.
class _RouteOption {
  _RouteOption(this.university, this.route);

  final University university;
  final RouteModel route;

  String get label => '${university.name} • ${route.routeName}';
}

class _StopEditorScreenState extends State<StopEditorScreen> {
  final SupabaseService _service = SupabaseService();
  final RouteService _routeService = RouteService();

  bool _loadingRoutes = true;
  String? _error;
  List<_RouteOption> _routeOptions = [];
  _RouteOption? _selected;

  bool _loadingStops = false;
  List<PickupPoint> _stops = [];

  @override
  void initState() {
    super.initState();
    _loadRouteOptions();
  }

  Future<void> _loadRouteOptions() async {
    setState(() {
      _loadingRoutes = true;
      _error = null;
    });
    try {
      final universities = await _service.getUniversities();
      final options = <_RouteOption>[];
      for (final university in universities) {
        final routes = await _service.getRoutesForUniversity(university.id);
        for (final route in routes) {
          options.add(_RouteOption(university, route));
        }
      }
      if (!mounted) return;
      setState(() {
        _routeOptions = options;
        _loadingRoutes = false;
      });
      if (options.isNotEmpty) _select(options.first);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[stops-admin] route load failed: $e');
      setState(() {
        _error = 'Could not load routes. Check your connection and try again.';
        _loadingRoutes = false;
      });
    }
  }

  Future<void> _select(_RouteOption option) async {
    setState(() {
      _selected = option;
      _loadingStops = true;
      // Drop the PREVIOUS route's stops immediately: the "Add stop" FAB
      // computes its order_index from `_stops`, and during the load it would
      // otherwise derive the index from another route's max - silently
      // corrupting the new stop's visit order.
      _stops = [];
      _error = null;
    });
    try {
      final stops = await _service.getPickupPointsForRoute(option.route.id);
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _loadingStops = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[stops-admin] stop load failed: $e');
      setState(() {
        _error = 'Could not load stops for this route.';
        _loadingStops = false;
      });
    }
  }

  /// Highest current order index, so a new stop lands at the end of the visit
  /// order (never before an existing one).
  int get _nextOrderIndex =>
      _stops.isEmpty
          ? 1
          : _stops.map((s) => s.orderIndex).reduce((a, b) => a > b ? a : b) + 1;

  Future<void> _edit({PickupPoint? existing}) async {
    final option = _selected;
    if (option == null) return;
    final saved = await Navigator.push<PickupPoint>(
      context,
      MaterialPageRoute(
        builder: (_) => StopPointEditor(
          service: _service,
          routeService: _routeService,
          routeId: option.route.id,
          existing: existing,
          nextOrderIndex: _nextOrderIndex,
        ),
      ),
    );
    if (saved != null && mounted) _select(option);
  }

  Future<void> _delete(PickupPoint point) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete stop'),
            content: Text('Delete "${point.pointName}" from this route?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
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
    if (!confirmed || !mounted) return;
    try {
      await _service.deletePickupPoint(point.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop deleted'),
          backgroundColor: Colors.red,
        ),
      );
      final option = _selected;
      if (option != null) _select(option);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[stops-admin] delete failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not delete the stop. It may already be gone, or you may '
            'not have admin permission.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Route Stops'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      // Gated on loading too: while the route's stops are still loading, the
      // true max order_index is unknown and a new stop could get a duplicated
      // index.
      floatingActionButton: (_selected == null || _loadingStops)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Add stop'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingRoutes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _selected == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRouteOptions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_routeOptions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No routes found to manage.'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownButtonFormField<_RouteOption>(
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: 'Route',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.route),
            ),
            items: [
              for (final option in _routeOptions)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (option) {
              if (option != null) _select(option);
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        Expanded(
          child: _loadingStops
              ? const Center(child: CircularProgressIndicator())
              : _stops.isEmpty
              ? const Center(
                  child: Text('No stops on this route yet. Add one.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: _stops.length,
                  itemBuilder: (context, index) {
                    final stop = _stops[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade50,
                          child: Text(
                            '${stop.orderIndex}',
                            style: const TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(stop.pointName),
                        subtitle: Text(
                          '${stop.latitude.toStringAsFixed(5)}, '
                          '${stop.longitude.toStringAsFixed(5)}'
                          '${stop.landmark == null ? '' : ' • ${stop.landmark}'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit',
                              onPressed: () => _edit(existing: stop),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete',
                              onPressed: () => _delete(stop),
                            ),
                          ],
                        ),
                        onTap: () => _edit(existing: stop),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Full-screen map pin-dropper for one stop: tap the map or drag the marker,
/// watch the live "distance to nearest road" readout, name it, save.
class StopPointEditor extends StatefulWidget {
  const StopPointEditor({
    super.key,
    required this.service,
    required this.routeService,
    required this.routeId,
    required this.existing,
    required this.nextOrderIndex,
  });

  final SupabaseService service;
  final RouteService routeService;
  final int routeId;

  /// Non-null when editing an existing stop; null when adding.
  final PickupPoint? existing;

  /// Order index a NEW stop will take (edit keeps the existing one).
  final int nextOrderIndex;

  @override
  State<StopPointEditor> createState() => _StopPointEditorState();
}

class _StopPointEditorState extends State<StopPointEditor> {
  /// Default drop point: Larkana city centre, so a new pin is never at
  /// (0, 0) in the Atlantic.
  static const LatLng _larkanaCenter = LatLng(27.5580, 68.2120);

  final MapController _mapController = MapController();

  /// Identifies the FlutterMap's own render box, so marker drags can convert
  /// the gesture's screen-global position into map-local coordinates.
  final GlobalKey _mapKey = GlobalKey();
  late LatLng _picked;
  late final TextEditingController _nameController;
  late final TextEditingController _landmarkController;

  /// Meters to the nearest road for the current pin; null = not checked yet
  /// or the lookup failed.
  double? _roadDistance;
  bool _checkingRoad = false;
  Timer? _roadDebounce;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _picked = existing == null
        ? _larkanaCenter
        : LatLng(existing.latitude, existing.longitude);
    _nameController = TextEditingController(text: existing?.pointName ?? '');
    _landmarkController = TextEditingController(text: existing?.landmark ?? '');
    _checkRoad();
  }

  @override
  void dispose() {
    _roadDebounce?.cancel();
    _nameController.dispose();
    _landmarkController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _movePicked(LatLng point) {
    setState(() => _picked = point);
    _scheduleRoadCheck();
  }

  /// Debounce the nearest-road lookup: a drag fires it on every frame, and
  /// hammering the public OSRM demo would get us rate-limited.
  void _scheduleRoadCheck() {
    _roadDebounce?.cancel();
    _roadDebounce = Timer(const Duration(milliseconds: 350), _checkRoad);
  }

  Future<void> _checkRoad() async {
    setState(() => _checkingRoad = true);
    final distance = await widget.routeService.nearestRoadDistanceMeters(
      _picked,
    );
    if (!mounted) return;
    setState(() {
      _roadDistance = distance;
      _checkingRoad = false;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a stop name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.service.upsertPickupPoint(
        routeId: widget.routeId,
        id: widget.existing?.id,
        pointName: name,
        latitude: _picked.latitude,
        longitude: _picked.longitude,
        landmark: _landmarkController.text.trim().isEmpty
            ? null
            : _landmarkController.text.trim(),
        orderIndex: widget.existing?.orderIndex ?? widget.nextOrderIndex,
      );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[stops-admin] save failed: $e');
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the stop. You may not have admin permission, '
            'or the network is down.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color get _roadColor {
    final d = _roadDistance;
    if (d == null) return Colors.grey;
    if (d <= 30) return Colors.green;
    if (d <= 80) return Colors.orange;
    return Colors.red;
  }

  String get _roadLabel {
    if (_checkingRoad) return 'Checking distance to nearest road…';
    final d = _roadDistance;
    if (d == null) return 'Road check unavailable (offline?)';
    final meters = d.round();
    if (meters <= 30) return 'On road (~$meters m)';
    if (meters <= 80) return 'Near a road (~$meters m) - check it';
    return 'Far off any road (~$meters m) - likely wrong';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add stop' : 'Edit stop'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              key: _mapKey,
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _picked,
                initialZoom: _picked == _larkanaCenter ? 13 : 16,
                // Tap anywhere to move the pin - the simple, reliable way to
                // place it exactly where you mean.
                onTap: (tapPoint, latlng) => _movePicked(latlng),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName:
                      'com.example.university_point_locator',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked,
                      width: 44,
                      height: 44,
                      // Draggable: pan the marker to re-place the pin; the
                      // road check re-runs (debounced) as it moves.
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          // camera.screenOffsetToLatLng wants an offset
                          // RELATIVE TO THE MAP WIDGET, but pan details give
                          // screen-global pixels. Feeding globalPosition
                          // straight in put the pin ~status-bar + AppBar
                          // height (~180-200 m at zoom 16) south-east of the
                          // finger - the exact wrong-pin this editor exists
                          // to prevent. Convert through the map's box first.
                          final box =
                              _mapKey.currentContext?.findRenderObject()
                                  as RenderBox?;
                          if (box == null || !box.attached) return;
                          final latlng = _mapController.camera
                              .screenOffsetToLatLng(
                                box.globalToLocal(details.globalPosition),
                              );
                          _movePicked(latlng);
                        },
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 44,
                        ),
                      ),
                    ),
                  ],
                ),
                const SimpleAttributionWidget(
                  source: Text('OpenStreetMap contributors'),
                ),
              ],
            ),
          ),
          // Control + readout panel.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live nearest-road readout.
                Row(
                  children: [
                    Icon(Icons.traffic, color: _roadColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _roadLabel,
                        style: TextStyle(
                          color: _roadColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Re-check road',
                      onPressed: _checkingRoad ? null : _checkRoad,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Stop name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landmarkController,
                  decoration: const InputDecoration(
                    labelText: 'Landmark (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pin: ${_picked.latitude.toStringAsFixed(5)}, '
                  '${_picked.longitude.toStringAsFixed(5)}  •  '
                  'tap the map or drag the marker to move it',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
