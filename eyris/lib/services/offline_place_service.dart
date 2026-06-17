import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class Origin {
  final String name;
  final String city;
  final double lat;
  final double lng;
  final String type;

  Origin({
    required this.name,
    required this.city,
    required this.lat,
    required this.lng,
    required this.type,
  });

  LatLng get coordinates => LatLng(lat, lng);

  factory Origin.fromJson(Map<String, dynamic> j) => Origin(
        name: j['name'],
        city: j['city'] ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        type: j['type'] ?? '',
      );
}

class OfflinePlace {
  final String name;
  final String city;
  final double lat;
  final double lng;
  final String category;
  final bool isCityLandmark;

  OfflinePlace({
    required this.name,
    required this.city,
    required this.lat,
    required this.lng,
    required this.category,
    this.isCityLandmark = false,
  });

  LatLng get coordinates => LatLng(lat, lng);

  String get slug => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

/// Result of a fuzzy match. `score` is in [0.0, 1.0].
class PlaceMatch {
  final OfflinePlace place;
  final double score;
  PlaceMatch({required this.place, required this.score});
}

class OfflinePlaceService {
  final List<OfflinePlace> _places = [];
  final List<Origin> _origins = [];
  bool _isLoaded = false;

  List<Origin> get origins => List.unmodifiable(_origins);
  List<OfflinePlace> get allPlaces => List.unmodifiable(_places);

  Future<void> loadPlaces() async {
    try {
      final jsonString = await rootBundle.loadString('assets/places.json');
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      _origins.clear();
      for (var o in data['origins'] as List) {
        _origins.add(Origin.fromJson(o));
      }

      _places.clear();
      for (var p in data['places'] as List) {
        _places.add(OfflinePlace(
          name: p['name'],
          city: p['city'] ?? '',
          lat: (p['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
          category: p['category'] ?? '',
        ));
      }
      for (var p in (data['city_landmarks'] as List? ?? [])) {
        _places.add(OfflinePlace(
          name: p['name'],
          city: p['city'] ?? '',
          lat: (p['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
          category: p['category'] ?? 'city_center',
          isCityLandmark: true,
        ));
      }

      _isLoaded = true;
      if (kDebugMode) {
        debugPrint(
            'Loaded ${_places.length} places, ${_origins.length} origins');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading places: $e');
    }
  }

  List<OfflinePlace> searchPlaces(String query) {
    if (!_isLoaded || query.isEmpty) return [];
    final q = query.toLowerCase().trim();
    return _places.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  OfflinePlace? getPlace(String query) {
    final results = searchPlaces(query);
    return results.isEmpty ? null : results.first;
  }

  /// Fuzzy-matches a (possibly imperfect) phrase to the best known place.
  /// Returns null if no candidate scores at least [threshold] (default 0.55).
  /// If [preferredCity] is supplied, places in that city get a small boost
  /// so ambiguous matches (e.g. "Civil Hospital") pick the right one.
  PlaceMatch? findBestMatch(
    String spokenText, {
    String? preferredCity,
    double threshold = 0.55,
  }) {
    if (!_isLoaded || spokenText.trim().isEmpty) return null;

    final spoken = _normalize(spokenText);
    final spokenTokens = _tokens(spoken);
    if (spokenTokens.isEmpty) return null;

    PlaceMatch? best;
    for (final place in _places) {
      final candidate = _normalize(place.name);
      final candidateTokens = _tokens(candidate);
      if (candidateTokens.isEmpty) continue;

      final tokenScore = _tokenOverlap(spokenTokens, candidateTokens);
      final charScore = _normalizedLevenshteinScore(spoken, candidate);
      double score = (tokenScore * 0.7) + (charScore * 0.3);

      if (preferredCity != null &&
          place.city.toLowerCase() == preferredCity.toLowerCase()) {
        score += 0.05;
      }

      if (best == null || score > best.score) {
        best = PlaceMatch(place: place, score: score);
      }
    }

    if (best == null || best.score < threshold) return null;
    return best;
  }

  /// Returns the origin nearest to the given location (haversine).
  Origin? nearestOrigin(double lat, double lng) {
    if (_origins.isEmpty) return null;
    Origin best = _origins.first;
    double bestDist = double.infinity;
    for (final o in _origins) {
      final d = _haversineKm(lat, lng, o.lat, o.lng);
      if (d < bestDist) {
        bestDist = d;
        best = o;
      }
    }
    return best;
  }

  // ---------- helpers ----------

  String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _tokens(String s) =>
      s.split(' ').where((t) => t.length >= 2).toList();

  /// Jaccard-like token overlap. 1.0 = same set, 0.0 = no overlap.
  double _tokenOverlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final setA = a.toSet();
    final setB = b.toSet();
    final inter = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0 : inter / union;
  }

  /// 1.0 minus normalized Levenshtein. Bounded [0, 1].
  double _normalizedLevenshteinScore(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final maxLen = max(a.length, b.length);
    if (maxLen == 0) return 1.0;
    final dist = _levenshtein(a, b);
    return 1.0 - (dist / maxLen);
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final m = a.length;
    final n = b.length;
    final prev = List<int>.filled(n + 1, 0);
    final curr = List<int>.filled(n + 1, 0);

    for (int j = 0; j <= n; j++) {
      prev[j] = j;
    }

    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce(min);
      }
      for (int j = 0; j <= n; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[n];
  }

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;
}
