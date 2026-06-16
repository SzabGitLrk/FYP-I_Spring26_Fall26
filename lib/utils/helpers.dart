import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Helpers {
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    return '$hours:$minutes hrs';
  }

  static String timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 30) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static String formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degree) => degree * (pi / 180);

  static int? estimateTimeMinutes(double distanceKm, double speedKmh) {
    if (speedKmh <= 1) return null;
    return (distanceKm / speedKmh * 60).round();
  }

  static BitmapDescriptor? _cachedGreen;
  static BitmapDescriptor? _cachedBlue;
  static BitmapDescriptor? _cachedRed;
  static BitmapDescriptor? _cachedAzure;
  static BitmapDescriptor? _cachedViolet;

  static BitmapDescriptor getStopMarker(bool isFirst, bool isLast) {
    if (isFirst) {
      _cachedGreen ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      return _cachedGreen!;
    }
    if (isLast) {
      _cachedRed ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      return _cachedRed!;
    }
    _cachedBlue ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    return _cachedBlue!;
  }

  static BitmapDescriptor getBusMarker(bool isMoving) {
    if (isMoving) {
      _cachedAzure ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      return _cachedAzure!;
    }
    _cachedViolet ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    return _cachedViolet!;
  }
}
