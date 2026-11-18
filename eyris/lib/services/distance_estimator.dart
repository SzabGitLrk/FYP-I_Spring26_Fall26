import 'dart:math' as math;

/// How a camera-only range was derived.
enum CameraRangeMethod { objectHeight, groundPlane }

class CameraRange {
  const CameraRange(this.meters,
      {required this.method, required this.approximate});

  final double meters;
  final CameraRangeMethod method;

  /// True when the box is cut off by the frame edge or the estimate relies on
  /// the assumed camera height.
  final bool approximate;
}

/// Camera-only (monocular) range estimates. They are approximate by nature:
/// the ultrasonic sensor stays the authority for whatever is straight ahead.
class DistanceEstimator {
  const DistanceEstimator({
    this.focalFactor = phoneFocalFactor,
    this.cameraHeightMeters = 1.2,
  });

  /// ESP32-S3-EYE OV2640 lens (about 55 degrees horizontally).
  static const double espFocalFactor = 0.95;

  /// Typical 26 mm-equivalent phone main camera.
  static const double phoneFocalFactor = 0.72;

  /// Focal length in pixels divided by the long side of the frame.
  final double focalFactor;

  /// Height of the camera above the ground, used by the ground-plane method.
  final double cameraHeightMeters;

  /// Typical real-world heights, keyed by the lower-cased spoken label.
  /// Classes whose height varies too much (tree, pole, wall) or that lie on
  /// the ground (pothole, speed breaker, footpath, stairs) are ranged from
  /// where they meet the ground instead.
  static const Map<String, double> objectHeightsMeters = {
    'person': 1.65,
    'car': 1.50,
    'truck': 3.00,
    'bus': 3.10,
    'bike': 1.10,
    'chair': .90,
    'table': .75,
    'door': 2.00,
    'bed': .60,
    'sofa': .85,
    'bottle': .25,
    'backpack': .45,
    'laptop': .24,
    'dustbin': .80,
    'traffic sign': .70,
  };

  /// Classes that stand on the ground, so the bottom edge of their box can be
  /// ranged with the ground-plane method.
  static const Set<String> groundStanding = {
    'person', 'car', 'truck', 'bus', 'bike', 'chair', 'table', 'door', 'bed',
    'sofa', 'dustbin', 'tree', 'pole', 'wall', ...groundSurface,
  };

  /// Things that are part of the ground itself. When their box runs off the
  /// bottom of the frame they start right at the user's feet.
  static const Set<String> groundSurface = {
    'pothole', 'speed breaker', 'footpath', 'stairs', 'open drain',
  };

  /// Flat things in or on the ground. The ultrasonic sensor's beam passes
  /// over them, so its reading belongs to whatever stands behind them and
  /// must not replace their camera distance.
  static const Set<String> belowSensor = {
    'pothole', 'speed breaker', 'footpath', 'open drain',
  };

  double focalLengthPixels(double frameWidth, double frameHeight) =>
      focalFactor * math.max(frameWidth, frameHeight);

  /// Returns null when the box is invalid or the class cannot be ranged from
  /// this view.
  CameraRange? estimate({
    required String label,
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double frameWidth,
    required double frameHeight,
  }) {
    if (frameWidth <= 0 || frameHeight <= 0) return null;
    final boxHeight = bottom - top;
    if (boxHeight <= 1 || right - left <= 1) return null;

    final key = label.trim().toLowerCase();
    final focal = focalLengthPixels(frameWidth, frameHeight);
    final margin = frameHeight * .02;
    final cutTop = top <= margin;
    final cutBottom = bottom >= frameHeight - margin;

    final height = objectHeightsMeters[key];
    final byHeight = height == null ? null : height * focal / boxHeight;

    // Assumes a level camera: the horizon is the middle row of the frame.
    double? byGround;
    final belowHorizon = bottom - frameHeight / 2;
    if (groundStanding.contains(key) && belowHorizon > frameHeight * .05) {
      if (!cutBottom) {
        byGround = cameraHeightMeters * focal / belowHorizon;
      } else if (groundSurface.contains(key)) {
        // Nearest ground the camera can see at all.
        byGround = cameraHeightMeters * focal / (frameHeight / 2);
      }
    }

    if (byHeight != null && !cutTop && !cutBottom) {
      return CameraRange(_clamp(byHeight),
          method: CameraRangeMethod.objectHeight, approximate: false);
    }
    if (byGround != null) {
      return CameraRange(_clamp(byGround),
          method: CameraRangeMethod.groundPlane, approximate: true);
    }
    if (byHeight != null) {
      // Part of the object is outside the frame, so it is at most this far.
      return CameraRange(_clamp(byHeight),
          method: CameraRangeMethod.objectHeight, approximate: true);
    }
    if (key == 'wall' && cutTop && cutBottom) {
      // The wall fills the view and the floor in front of it is not visible,
      // so its foot is nearer than the nearest ground the camera can see.
      // Report well inside that limit: too near is the safe mistake.
      final nearestVisibleGround =
          cameraHeightMeters * focal / (frameHeight / 2);
      return CameraRange(_clamp(nearestVisibleGround * .6),
          method: CameraRangeMethod.groundPlane, approximate: true);
    }
    return null;
  }

  static double _clamp(double meters) => meters.clamp(.1, 30.0).toDouble();
}
