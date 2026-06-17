import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Generates routes:
///   - Intra-city: origin → place (city inferred from nearest origin if missing)
///   - Inter-anchor: origin → other origin
///   - Origin → city_landmark
///
/// File naming: <origin_slug>__<dest_slug>.json
/// Run: dart run scripts/generate_routes.dart
void main() async {
  final placesFile = File('assets/places.json');
  if (!placesFile.existsSync()) {
    print('ERROR: ${placesFile.path} not found');
    exit(1);
  }

  final data = jsonDecode(placesFile.readAsStringSync()) as Map<String, dynamic>;
  final origins = (data['origins'] as List).cast<Map<String, dynamic>>();
  final cityLandmarks =
      (data['city_landmarks'] as List).cast<Map<String, dynamic>>();
  final places = (data['places'] as List).cast<Map<String, dynamic>>();

  // For places missing `city`, infer from nearest origin
  for (var place in places) {
    if (place['city'] == null || (place['city'] as String).isEmpty) {
      final placeLat = (place['lat'] as num).toDouble();
      final placeLng = (place['lng'] as num).toDouble();
      Map<String, dynamic> nearest = origins.first;
      double bestDist = double.infinity;
      for (var o in origins) {
        final oLat = (o['lat'] as num).toDouble();
        final oLng = (o['lng'] as num).toDouble();
        final d = _haversineKm(placeLat, placeLng, oLat, oLng);
        if (d < bestDist) {
          bestDist = d;
          nearest = o;
        }
      }
      place['city'] = nearest['city'];
    }
  }

  // Write back the enriched places.json so the app sees city fields too
  placesFile.writeAsStringSync(JsonEncoder.withIndent('  ').convert({
    'origins': origins,
    'city_landmarks': cityLandmarks,
    'places': places,
  }));
  print('Updated places.json with inferred city fields.\n');

  final outputDir = Directory('assets/routes');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  // Build all (origin, destination) pairs
  final pairs = <Map<String, dynamic>>[];

  // 1. Intra-city: origin → place (same city)
  for (var origin in origins) {
    final originCity = origin['city'] as String;
    for (var place in places) {
      if (place['city'] == originCity) {
        pairs.add({'from': origin, 'to': place, 'kind': 'intra'});
      }
    }
  }

  // 2. Inter-anchor: origin → other origin
  for (var a in origins) {
    for (var b in origins) {
      if (a['name'] != b['name']) {
        pairs.add({'from': a, 'to': b, 'kind': 'inter-anchor'});
      }
    }
  }

  // 3. Origin → city landmark
  for (var origin in origins) {
    for (var city in cityLandmarks) {
      pairs.add({'from': origin, 'to': city, 'kind': 'city'});
    }
  }

  print('========================================');
  print('Origins: ${origins.length}');
  print('City landmarks: ${cityLandmarks.length}');
  print('Places: ${places.length}');
  print('Total pairs: ${pairs.length}');
  print('Est. time: ${(pairs.length * 1.2 / 60).toStringAsFixed(1)} min');
  print('========================================\n');

  int success = 0;
  int failed = 0;
  int skipped = 0;
  int done = 0;

  for (var pair in pairs) {
    done++;
    final from = pair['from'] as Map<String, dynamic>;
    final to = pair['to'] as Map<String, dynamic>;
    final kind = pair['kind'] as String;

    final fromName = from['name'] as String;
    final toName = to['name'] as String;
    final fromLat = (from['lat'] as num).toDouble();
    final fromLng = (from['lng'] as num).toDouble();
    final toLat = (to['lat'] as num).toDouble();
    final toLng = (to['lng'] as num).toDouble();

    final fromSlug = _slugify(fromName);
    final toSlug = _slugify(toName);
    final outFile = File('${outputDir.path}/${fromSlug}__$toSlug.json');

    if (outFile.existsSync()) {
      skipped++;
      continue;
    }

    final profile = (kind == 'intra') ? 'foot' : 'driving';

    try {
      final url = 'https://router.project-osrm.org/route/v1/$profile/'
          '$fromLng,$fromLat;$toLng,$toLat'
          '?overview=full&geometries=geojson&steps=true';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 429) {
        print('  RATE LIMITED — waiting 30 sec...');
        await Future.delayed(const Duration(seconds: 30));
        done--;
        continue;
      }
      if (response.statusCode != 200) {
        print('  FAIL  [$done/${pairs.length}] $fromName → $toName  HTTP ${response.statusCode}');
        failed++;
        continue;
      }

      final body = jsonDecode(response.body);
      if (body['code'] != 'Ok') {
        print('  FAIL  [$done/${pairs.length}] $fromName → $toName  ${body['code']}');
        failed++;
        continue;
      }

      final route = body['routes'][0];
      final coords = (route['geometry']['coordinates'] as List)
          .map<List<double>>((c) =>
              [(c[1] as num).toDouble(), (c[0] as num).toDouble()])
          .toList();

      final instructions = <Map<String, dynamic>>[];
      for (var leg in route['legs']) {
        for (var step in leg['steps']) {
          final maneuver = step['maneuver'];
          final type = maneuver['type'] ?? 'continue';
          final modifier = maneuver['modifier'] ?? '';
          final roadName = step['name'] ?? '';
          final distance = (step['distance'] as num).toDouble();

          instructions.add({
            'text': _formatInstruction(type, modifier, roadName, distance),
            'distance': distance,
            'type': type,
            'modifier': modifier,
            'road': roadName,
          });
        }
      }

      final output = {
        'origin': fromName,
        'destination': toName,
        'kind': kind,
        'profile': profile,
        'from_coords': [fromLat, fromLng],
        'to_coords': [toLat, toLng],
        'distance_meters': route['distance'],
        'duration_seconds': route['duration'],
        'polyline': coords,
        'instructions': instructions,
      };

      outFile.writeAsStringSync(
          JsonEncoder.withIndent('  ').convert(output));

      final km = (route['distance'] / 1000).toStringAsFixed(1);
      print('  OK    [$done/${pairs.length}] ($kind) $fromName → $toName  $km km');
      success++;

      await Future.delayed(const Duration(milliseconds: 1100));
    } catch (e) {
      print('  FAIL  [$done/${pairs.length}] $fromName → $toName ($e)');
      failed++;
    }
  }

  print('\n========================================');
  print('Done. Success: $success, Failed: $failed, Skipped: $skipped');
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
          sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

String _slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

String _formatInstruction(
    String type, String modifier, String road, double distance) {
  final dist = distance.round();
  final on = road.isNotEmpty ? ' onto $road' : '';
  switch (type) {
    case 'depart':
      return 'Start by heading${modifier.isNotEmpty ? ' $modifier' : ''}$on';
    case 'arrive':
      return 'You have arrived at your destination';
    case 'turn':
      return 'In $dist meters, turn $modifier$on';
    case 'merge':
      return 'In $dist meters, merge $modifier$on';
    case 'on ramp':
    case 'off ramp':
      return 'In $dist meters, take the ramp$on';
    case 'fork':
      return 'In $dist meters, keep $modifier at the fork$on';
    case 'roundabout':
      return 'In $dist meters, enter the roundabout$on';
    case 'continue':
    default:
      return 'Continue${modifier.isNotEmpty ? ' $modifier' : ''} for $dist meters$on';
  }
}