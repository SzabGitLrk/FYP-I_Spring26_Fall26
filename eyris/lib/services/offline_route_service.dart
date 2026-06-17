import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'offline_place_service.dart';

class NavigationInstruction {
  final String text;
  final double distance;
  final String type;
  final String modifier;

  NavigationInstruction({
    required this.text,
    required this.distance,
    required this.type,
    required this.modifier,
  });
}

class OfflineRoute {
  final String origin;
  final String destination;
  final List<LatLng> polyline;
  final List<NavigationInstruction> instructions;
  final double distanceMeters;
  final double durationSeconds;
  final String kind;

  OfflineRoute({
    required this.origin,
    required this.destination,
    required this.polyline,
    required this.instructions,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.kind,
  });
}

class OfflineRouteService {
  String _slugify(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  Future<OfflineRoute?> getRoute(Origin origin, OfflinePlace place) async {
    final fromSlug = _slugify(origin.name);
    final toSlug = _slugify(place.name);
    final assetPath = 'assets/routes/${fromSlug}__$toSlug.json';

    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final polyline = (data['polyline'] as List)
          .map<LatLng>((p) => LatLng(
                (p[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ))
          .toList();

      final instructions = (data['instructions'] as List)
          .map<NavigationInstruction>((i) => NavigationInstruction(
                text: i['text'] ?? '',
                distance: (i['distance'] as num).toDouble(),
                type: i['type'] ?? '',
                modifier: i['modifier'] ?? '',
              ))
          .toList();

      return OfflineRoute(
        origin: data['origin'] ?? origin.name,
        destination: data['destination'] ?? place.name,
        polyline: polyline,
        instructions: instructions,
        distanceMeters: (data['distance_meters'] as num).toDouble(),
        durationSeconds: (data['duration_seconds'] as num).toDouble(),
        kind: data['kind'] ?? 'intra',
      );
    } catch (e) {
      return null;
    }
  }
}