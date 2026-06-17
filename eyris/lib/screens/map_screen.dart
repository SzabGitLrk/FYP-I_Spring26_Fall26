import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/offline_place_service.dart';
import '../services/offline_route_service.dart';
import '../services/alert_service.dart';

/// Average speeds in km/h for duration estimation.
/// These are realistic urban averages — adjust if your demo region differs.
const Map<String, double> _speedKmh = {
  'foot': 5.0,
  'bike': 15.0,
  'car': 35.0,
};

const Map<String, IconData> _transportIcons = {
  'foot': Icons.directions_walk,
  'bike': Icons.directions_bike,
  'car': Icons.directions_car,
};

const Map<String, String> _transportLabels = {
  'foot': 'Walk',
  'bike': 'Bike',
  'car': 'Drive',
};

/// Time the user must remain stationary before triggering the alert.
const Duration _stationaryAlertAfter = Duration(minutes: 1);

/// Distance (meters) within which the user is considered "not moving".
const double _stationaryThresholdMeters = 20.0;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final OfflinePlaceService _placeService = OfflinePlaceService();
  final OfflineRouteService _routeService = OfflineRouteService();
  final AlertService _alertService = AlertService();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  StreamSubscription<Position>? _positionStream;
  MbTilesTileProvider? _tileProvider;

  LatLng _currentLocation = const LatLng(24.9189, 67.0986);
  Origin? _selectedOrigin;
  OfflinePlace? _selectedDestination;
  String _transportMode = 'foot';

  List<LatLng> _routePoints = [];
  List<NavigationInstruction> _instructions = [];
  List<OfflinePlace> _searchSuggestions = [];
  int _currentInstructionIndex = 0;
  double _currentRouteDistanceMeters = 0;

  bool _loading = true;
  bool _navigationActive = false;
  bool _manualStepMode = false;
  String _instruction = 'Pick origin and search destination';

  // Stationary detection
  Timer? _stationaryTimer;
  LatLng? _stationaryAnchor;
  bool _stationaryAlertActive = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _placeService.loadPlaces();
    await _loadTiles();
    await _initTts();

    if (_placeService.origins.isNotEmpty) {
      _selectedOrigin = _placeService.origins.first;
    }

    if (mounted) setState(() => _loading = false);

    await _startLocation();
  }

  Future<void> _loadTiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pakistan-tiles.mbtiles');
    final bytes = await rootBundle.load('assets/maps/pakistan.mbtiles');

    if (!await file.exists() ||
        await file.length() != bytes.lengthInBytes) {
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }

    _tileProvider = MbTilesTileProvider.fromPath(path: file.path);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async => _tts.speak(text);

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      final nearest = _placeService.nearestOrigin(pos.latitude, pos.longitude);
      if (nearest != null) _selectedOrigin = nearest;
    });

    _safeMove(_currentLocation, 13);

    _positionStream = Geolocator.getPositionStream().listen((p) {
      if (!mounted) return;
      final newLoc = LatLng(p.latitude, p.longitude);
      setState(() => _currentLocation = newLoc);

      // If navigating, check if user has moved enough to reset stationary timer
      if (_navigationActive && _stationaryAnchor != null) {
        final moved = Geolocator.distanceBetween(
          _stationaryAnchor!.latitude,
          _stationaryAnchor!.longitude,
          newLoc.latitude,
          newLoc.longitude,
        );
        if (moved >= _stationaryThresholdMeters) {
          _resetStationaryWatch();
        }
      }

      // Only auto-advance instructions if NOT in manual mode
      if (_navigationActive && !_manualStepMode) _checkNextInstruction();
    });
  }

  void _safeMove(LatLng target, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(target, zoom);
      } catch (_) {}
    });
  }

  void _onSearchChanged(String text) {
    setState(() {
      _searchSuggestions =
          text.isEmpty ? [] : _placeService.searchPlaces(text);
    });
  }

  /// Computes estimated travel time for a given distance and transport mode.
  /// Returns a human-readable string like "2 days 4 hours" or "35 minutes".
  String _estimateDuration(double meters, String mode) {
    final speedKmh = _speedKmh[mode] ?? 5.0;
    final hours = (meters / 1000) / speedKmh;
    final totalMinutes = (hours * 60).round();

    if (totalMinutes < 1) return 'less than a minute';

    final days = totalMinutes ~/ (60 * 24);
    final remainingAfterDays = totalMinutes % (60 * 24);
    final hoursPart = remainingAfterDays ~/ 60;
    final minutesPart = remainingAfterDays % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days ${days == 1 ? 'day' : 'days'}');
    if (hoursPart > 0) {
      parts.add('$hoursPart ${hoursPart == 1 ? 'hour' : 'hours'}');
    }
    if (minutesPart > 0 && days == 0) {
      parts.add('$minutesPart ${minutesPart == 1 ? 'minute' : 'minutes'}');
    }
    return parts.isEmpty ? '$totalMinutes minutes' : parts.join(' ');
  }

  Future<void> _selectPlace(OfflinePlace place) async {
    if (_selectedOrigin == null) {
      setState(() => _instruction = 'Select a starting point first');
      await _speak('Please select a starting point');
      return;
    }

    setState(() {
      _searchController.text = place.name;
      _searchSuggestions = [];
      _selectedDestination = place;
      _instruction = 'Loading route...';
      _routePoints = [];
      _instructions = [];
      _navigationActive = false;
    });

    final route = await _routeService.getRoute(_selectedOrigin!, place);
    if (!mounted) return;

    if (route == null) {
      setState(() => _instruction =
          'No route from ${_selectedOrigin!.name} to ${place.name}');
      await _speak('Route not available');
      return;
    }

    final km = (route.distanceMeters / 1000).toStringAsFixed(1);
    final eta = _estimateDuration(route.distanceMeters, _transportMode);
    final transportLabel = _transportLabels[_transportMode] ?? _transportMode;

    setState(() {
      _routePoints = route.polyline;
      _instructions = route.instructions;
      _currentRouteDistanceMeters = route.distanceMeters;
      _currentInstructionIndex = 0;
      _instruction = '$km km · $eta by $transportLabel · Tap Start';
    });

    await _speak(
        'Route to ${place.name}. $km kilometers. Approximately $eta by $transportLabel.');

    if (route.polyline.isNotEmpty) _fitBoundsToRoute(route.polyline);
  }

  void _changeTransport(String mode) {
    setState(() => _transportMode = mode);
    // Refresh the displayed ETA without reloading the route
    if (_selectedDestination != null && _instructions.isNotEmpty) {
      final km = (_currentRouteDistanceMeters / 1000).toStringAsFixed(1);
      final eta = _estimateDuration(_currentRouteDistanceMeters, mode);
      final label = _transportLabels[mode] ?? mode;
      setState(() => _instruction = '$km km · $eta by $label · Tap Start');
    }
  }

  void _fitBoundsToRoute(List<LatLng> points) {
    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _safeMove(
      LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
      _zoomForBounds(maxLat - minLat, maxLng - minLng),
    );
  }

  double _zoomForBounds(double dLat, double dLng) {
    final span = dLat > dLng ? dLat : dLng;
    if (span > 3) return 7;
    if (span > 1) return 9;
    if (span > 0.3) return 11;
    if (span > 0.1) return 12;
    return 14;
  }

  void _checkNextInstruction() {
    if (_currentInstructionIndex >= _instructions.length) {
      if (_navigationActive) {
        _speak('You have reached your destination');
        setState(() {
          _navigationActive = false;
          _instruction = 'Destination reached';
        });
      }
      return;
    }
    if (_selectedDestination == null) return;

    final remaining = Geolocator.distanceBetween(
      _currentLocation.latitude,
      _currentLocation.longitude,
      _selectedDestination!.lat,
      _selectedDestination!.lng,
    );

    final next = _instructions[_currentInstructionIndex];
    if (remaining < next.distance + 30) {
      _speak(next.text);
      setState(() {
        _instruction = next.text;
        _currentInstructionIndex++;
      });
    }
  }

  /// Manual mode — user taps Next to advance instructions
  void _nextStepManual() {
    if (_currentInstructionIndex >= _instructions.length) {
      _speak('You have reached your destination');
      setState(() {
        _navigationActive = false;
        _instruction = 'Destination reached. End of instructions.';
      });
      return;
    }

    final step = _instructions[_currentInstructionIndex];
    setState(() {
      _instruction =
          'Step ${_currentInstructionIndex + 1} of ${_instructions.length}: ${step.text}';
      _currentInstructionIndex++;
    });
    _speak(step.text);
  }

  void _previousStepManual() {
    if (_currentInstructionIndex <= 1) {
      setState(() {
        _currentInstructionIndex = 0;
        _instruction = 'At the start. Tap Next to begin.';
      });
      return;
    }
    setState(() => _currentInstructionIndex -= 2);
    _nextStepManual();
  }

  void _startNavigation() {
    if (_instructions.isEmpty) {
      setState(() => _instruction = 'Search destination first');
      return;
    }
    setState(() {
      _navigationActive = true;
      _currentInstructionIndex = 0;
    });

    if (_manualStepMode) {
      setState(() => _instruction =
          'Navigation started in manual mode. Tap Next for first instruction.');
      _speak('Navigation started. Tap Next for instructions.');
    } else {
      setState(() => _instruction = _instructions.first.text);
      _speak(_instructions.first.text);
      _currentInstructionIndex = 1;
    }

    _startStationaryWatch();
  }

  void _stopNavigation() {
    _cancelStationaryWatch();
    setState(() {
      _navigationActive = false;
      _currentInstructionIndex = 0;
      _instruction = 'Navigation stopped';
      _stationaryAlertActive = false;
    });
    _tts.stop();
  }

  // ---------- Stationary detection ----------

  void _startStationaryWatch() {
    _cancelStationaryWatch();
    _stationaryAnchor = _currentLocation;
    _stationaryTimer = Timer(_stationaryAlertAfter, _checkStationary);
  }

  void _resetStationaryWatch() {
    _stationaryAnchor = _currentLocation;
    _stationaryTimer?.cancel();
    _stationaryTimer = Timer(_stationaryAlertAfter, _checkStationary);
  }

  void _cancelStationaryWatch() {
    _stationaryTimer?.cancel();
    _stationaryTimer = null;
    _stationaryAnchor = null;
  }

  void _checkStationary() {
    if (!_navigationActive || _stationaryAnchor == null) return;

    final movedMeters = Geolocator.distanceBetween(
      _stationaryAnchor!.latitude,
      _stationaryAnchor!.longitude,
      _currentLocation.latitude,
      _currentLocation.longitude,
    );

    if (movedMeters < _stationaryThresholdMeters) {
      setState(() {
        _stationaryAlertActive = true;
        _instruction =
            "You don't seem to be moving. Tap 'I'm okay' to continue.";
      });
      _speak(
          "You don't seem to be moving. Are you having trouble? Tap I'm okay to continue.");

      // Save to alert history
      final dest = _selectedDestination?.name ?? 'destination';
      _alertService.saveAlert(
        'Stuck during navigation to $dest. No movement for 1 minute.',
        'navigation',
      );
    } else {
      _resetStationaryWatch();
    }
  }

  void _dismissStationaryAlert() {
    setState(() {
      _stationaryAlertActive = false;
      _instruction = _instructions.isNotEmpty &&
              _currentInstructionIndex > 0 &&
              _currentInstructionIndex <= _instructions.length
          ? _instructions[_currentInstructionIndex - 1].text
          : 'Continue to destination';
    });
    _speak('Okay. Continuing navigation.');
    _resetStationaryWatch();
  }

  Future<void> _startVoiceSearch() async {
    final available = await _speech.initialize();
    if (!available) {
      await _speak('Speech not available');
      return;
    }
    setState(() {
      _isListening = true;
      _instruction = 'Listening...';
    });
    _speech.listen(
      onResult: (r) {
        setState(() {
          _isListening = false;
          _searchController.text = r.recognizedWords;
        });
        // Voice input is usually imperfect, so use fuzzy matching
        _searchDestination(fromVoice: true);
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 2),
    );
  }

  void _searchDestination({bool fromVoice = false}) {
    final text = _searchController.text.trim();
    if (text.isEmpty) {
      setState(() => _instruction = 'Enter destination');
      return;
    }

    // Try exact substring first (typed search usually matches exactly)
    final exact = _placeService.getPlace(text);
    if (exact != null && !fromVoice) {
      _selectPlace(exact);
      return;
    }

    // For voice — or when exact failed — use fuzzy matching.
    // Prefer the city of the currently selected origin for tie-breaking.
    final preferredCity = _selectedOrigin?.city;
    final match = _placeService.findBestMatch(
      text,
      preferredCity: preferredCity,
    );

    if (match != null) {
      // Update the text box so the user sees the resolved name
      _searchController.text = match.place.name;
      _selectPlace(match.place);
      if (fromVoice) {
        final confidence = (match.score * 100).round();
        debugPrint('Voice match: "$text" -> "${match.place.name}" '
            '($confidence% confidence)');
      }
    } else if (exact != null) {
      // Fall back to typed exact match even if it was a low-quality one
      _selectPlace(exact);
    } else {
      setState(() =>
          _instruction = 'Place not found. Try a different name.');
      _speak('Sorry, place not found.');
    }
  }

  void _showOriginPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(8),
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Select Starting Point',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ..._placeService.origins.map((o) {
                  final isSelected = o.name == _selectedOrigin?.name;
                  return ListTile(
                    leading: Icon(
                      _iconForType(o.type),
                      color: isSelected ? Colors.blue : Colors.grey,
                    ),
                    title: Text(o.name),
                    subtitle: Text('${o.city} · ${o.type}'),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.blue)
                        : null,
                    onTap: () {
                      setState(() => _selectedOrigin = o);
                      Navigator.pop(context);
                      if (_selectedDestination != null) {
                        _selectPlace(_selectedDestination!);
                      }
                    },
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  IconData _iconForType(String t) {
    switch (t) {
      case 'university':
        return Icons.school;
      case 'hospital':
        return Icons.local_hospital;
      case 'transit':
        return Icons.train;
      case 'market':
        return Icons.storefront;
      case 'mosque':
        return Icons.mosque;
      case 'residential':
        return Icons.home;
      default:
        return Icons.location_on;
    }
  }

  @override
  void dispose() {
    _cancelStationaryWatch();
    _positionStream?.cancel();
    _tts.stop();
    _tileProvider?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _tileProvider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('EYRIS Navigation'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: InkWell(
              onTap: () {
                setState(() => _manualStepMode = !_manualStepMode);
                _speak(_manualStepMode ? 'Manual mode' : 'Automatic mode');
              },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _manualStepMode
                      ? Colors.orange
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _manualStepMode
                          ? Icons.touch_app
                          : Icons.gps_fixed,
                      size: 18,
                      color: _manualStepMode
                          ? Colors.white
                          : Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _manualStepMode ? 'Manual' : 'Auto',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _manualStepMode
                            ? Colors.white
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 13,
            ),
            children: [
              TileLayer(tileProvider: _tileProvider!),
              if (_routePoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5,
                    color: Colors.blue,
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: _currentLocation,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.my_location,
                      color: Colors.blue, size: 35),
                ),
                if (_selectedOrigin != null)
                  Marker(
                    point: _selectedOrigin!.coordinates,
                    width: 50,
                    height: 50,
                    child: const Icon(Icons.trip_origin,
                        color: Colors.green, size: 40),
                  ),
                if (_selectedDestination != null)
                  Marker(
                    point: _selectedDestination!.coordinates,
                    width: 50,
                    height: 50,
                    child: const Icon(Icons.location_on,
                        color: Colors.red, size: 40),
                  ),
              ]),
            ],
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(children: [
              // Origin picker
              InkWell(
                onTap: _showOriginPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.trip_origin, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text('From:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedOrigin?.name ?? 'Tap to select',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              // Search row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : Colors.blue),
                    onPressed: _startVoiceSearch,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search destination...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _searchDestination,
                    icon: const Icon(Icons.search),
                  ),
                ]),
              ),
              // Transport mode selector
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['foot', 'bike', 'car'].map((m) {
                    final selected = m == _transportMode;
                    return GestureDetector(
                      onTap: () => _changeTransport(m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.blue
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(_transportIcons[m],
                              color: selected
                                  ? Colors.white
                                  : Colors.black54,
                              size: 22),
                          const SizedBox(width: 4),
                          Text(
                            _transportLabels[m] ?? m,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (_searchSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _searchSuggestions.length > 6
                        ? 6
                        : _searchSuggestions.length,
                    itemBuilder: (_, i) {
                      final p = _searchSuggestions[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          p.isCityLandmark
                              ? Icons.location_city
                              : Icons.location_on,
                          color: p.isCityLandmark
                              ? Colors.orange
                              : Colors.blue,
                        ),
                        title: Text(p.name),
                        subtitle: Text('${p.city} · ${p.category}'),
                        onTap: () => _selectPlace(p),
                      );
                    },
                  ),
                ),
            ]),
          ),

          // Start Navigation button (before navigation starts)
          if (_instructions.isNotEmpty && !_navigationActive)
            Positioned(
              bottom: 140,
              left: 16,
              right: 16,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: _startNavigation,
                child: const Text('Start Navigation',
                    style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),

          // Manual step controls (when nav active AND manual mode)
          if (_navigationActive && _manualStepMode)
            Positioned(
              bottom: 140,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      onPressed: _previousStepManual,
                      child:
                          const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: _nextStepManual,
                        icon: const Icon(Icons.arrow_forward,
                            color: Colors.white),
                        label: const Text('Next Step',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      onPressed: _stopNavigation,
                      child: const Icon(Icons.stop, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          // Stop button (when nav active AND auto mode)
          if (_navigationActive && !_manualStepMode)
            Positioned(
              bottom: 140,
              left: 16,
              right: 16,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: _stopNavigation,
                child: const Text('Stop Navigation',
                    style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),

          // Bottom instruction panel
          Positioned(
            bottom: 30,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _navigationActive ? Colors.green : Colors.blue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.navigation, color: Colors.white),
                    if (_navigationActive && _instructions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_currentInstructionIndex}/${_instructions.length}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ]),
            ),
          ),

          // Stationary alert banner (shown when user hasn't moved in 5 min)
          if (_stationaryAlertActive)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: Colors.orange.shade700,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Are you stuck?",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "You haven't moved for 1 minute. Do you need help?",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.orange.shade900,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _dismissStationaryAlert,
                              child: const Text(
                                "I'm okay",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _stopNavigation,
                              child: const Text(
                                "Stop Navigation",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}