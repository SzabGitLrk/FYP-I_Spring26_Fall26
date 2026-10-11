import 'package:latlong2/latlong.dart';

import '../navigation/route_follower.dart';

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

  /// Straight-line distance in **kilometers** between two WGS84 points.
  ///
  /// Delegates to [distanceMeters] - the app's canonical great-circle
  /// helper (the same latlong2 Haversine the live navigation and
  /// stop-proximity code runs on). There is deliberately no second distance
  /// formula in this file: the unused haversine duplicate that used to live
  /// here was a trap for whoever wired it up next, drifting from the live
  /// implementation.
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return distanceMeters(LatLng(lat1, lon1), LatLng(lat2, lon2)) / 1000;
  }

  /// ETA in minutes for [distanceKm] at [speedKmh], mirroring
  /// `BusLocation.estimatedTimeTo`'s semantics exactly:
  ///
  /// - `speedKmh <= 1` means stopped: `0` when stopped *at* the point
  ///   (within 50 m - the bus has arrived), `null` ("no estimate
  ///   possible") anywhere else.
  /// - Moving buses report the CEILING of the minutes - the app must never
  ///   promise an earlier arrival than reality (a `.round()` here once
  ///   produced "Bus arrives in 0 minutes" for a bus still 2 km away).
  ///
  /// Keep in lock-step with `BusLocation.estimatedTimeTo`; models_test
  /// pins that method's ceiling behavior.
  static int? estimateTimeMinutes(double distanceKm, double speedKmh) {
    if (speedKmh <= 1) return distanceKm < 0.05 ? 0 : null;
    return (distanceKm / speedKmh * 60).ceil();
  }
}
