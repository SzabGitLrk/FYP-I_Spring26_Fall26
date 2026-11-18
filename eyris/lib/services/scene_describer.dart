import 'distance_estimator.dart';

/// One detected object with where it is and (when known) how far.
class SceneObject {
  const SceneObject({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.meters,
  });

  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Distance in meters, or null when it cannot be estimated.
  final double? meters;

  double get centerX => (left + right) / 2;
  double get area => (right - left).abs() * (bottom - top).abs();
}

enum Side { farLeft, left, ahead, right, farRight }

Side sideOf(SceneObject object, double frameWidth) {
  if (frameWidth <= 0) return Side.ahead;
  final x = object.centerX / frameWidth;
  // A box that spans the middle of the view is in the way wherever its
  // centre happens to be.
  final spansMiddle = object.left / frameWidth < .40 &&
      object.right / frameWidth > .60;
  if (spansMiddle) return Side.ahead;
  if (x < .18) return Side.farLeft;
  if (x < .38) return Side.left;
  if (x > .82) return Side.farRight;
  if (x > .62) return Side.right;
  return Side.ahead;
}

String sidePhrase(Side side) {
  switch (side) {
    case Side.farLeft:
      return 'far left';
    case Side.left:
      return 'on your left';
    case Side.ahead:
      return 'straight ahead';
    case Side.right:
      return 'on your right';
    case Side.farRight:
      return 'far right';
  }
}

const _numberWords = [
  'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven',
];

/// "less than a meter", "about one meter", "about 3 meters", "far away".
/// Empty when the distance is unknown.
String distancePhrase(double? meters) {
  if (meters == null) return '';
  if (meters < .9) return 'less than a meter';
  if (meters < 1.5) return 'about one meter';
  if (meters < 7.5) return 'about ${meters.round()} meters';
  return 'far away';
}

/// Coarse distance step used to decide whether a scene changed enough to be
/// spoken again.
int distanceBucket(double? meters) {
  if (meters == null) return -1;
  if (meters < .9) return 0;
  if (meters < 1.5) return 1;
  if (meters < 7.5) return meters.round();
  return 8;
}

/// Things on the ground that can trip or drop the user rank ahead of
/// furniture at the same distance.
const groundHazards = {'pothole', 'stairs', 'speed breaker', 'open drain'};

/// Openings the user could fall into: always spoken with a caution, at any
/// distance, and the path is not called clear for a while after one.
const dropHazards = {'open drain'};

bool isDropHazard(String label) => dropHazards.contains(label.toLowerCase());

/// Nearest first. Objects without a distance come last, largest first.
List<SceneObject> nearestFirst(Iterable<SceneObject> objects) {
  final sorted = objects.toList();
  sorted.sort((a, b) {
    final da = a.meters, db = b.meters;
    if (da != null && db != null) {
      final byBucket = distanceBucket(da).compareTo(distanceBucket(db));
      if (byBucket != 0) return byBucket;
      final ha = groundHazards.contains(a.label.toLowerCase()) ? 0 : 1;
      final hb = groundHazards.contains(b.label.toLowerCase()) ? 0 : 1;
      if (ha != hb) return ha.compareTo(hb);
      return da.compareTo(db);
    }
    if (da != null) return -1;
    if (db != null) return 1;
    return b.area.compareTo(a.area);
  });
  return sorted;
}

/// "Door straight ahead · about 2 meters" for the on-screen list.
String describeLine(SceneObject object, double frameWidth) {
  final where = sidePhrase(sideOf(object, frameWidth));
  final distance = distancePhrase(object.meters);
  return distance.isEmpty
      ? '${object.label} $where'
      : '${object.label} $where · $distance';
}

/// One-line status: "2 objects, Door closest · about 2 meters".
String statusLine(List<SceneObject> nearest) {
  if (nearest.isEmpty) return 'Path is clear';
  final first = nearest.first;
  final distance = distancePhrase(first.meters);
  final tail = distance.isEmpty ? '' : ' · $distance';
  if (nearest.length == 1) return '${first.label} detected$tail';
  return '${nearest.length} objects, ${first.label} closest$tail';
}

String _plural(String label) {
  final lower = label.toLowerCase();
  if (lower == 'person') return 'people';
  if (lower == 'stairs' || lower.endsWith('s')) return lower;
  if (lower.endsWith('ch') || lower.endsWith('x')) return '${lower}es';
  return '${lower}s';
}

/// What the voice says: the nearest objects, merged when the same kind of
/// thing is on the same side ("Two chairs on your left, about one meter").
String spokenSummary(List<SceneObject> nearest, double frameWidth,
    {int limit = 2}) {
  if (nearest.isEmpty) return '';
  final groups = <String, List<SceneObject>>{};
  for (final object in nearest) {
    final key = '${object.label}|${sideOf(object, frameWidth).name}';
    groups.putIfAbsent(key, () => []).add(object);
  }
  final parts = <String>[];
  var cautioned = false;
  for (final group in groups.values.take(limit)) {
    final first = group.first;
    final where = sidePhrase(sideOf(first, frameWidth));
    final count = group.length;
    final name = count == 1
        ? first.label
        : '${count < _numberWords.length ? _numberWords[count] : '$count'} '
            '${_plural(first.label)}';
    final distance = distancePhrase(first.meters);
    final close = first.meters != null && first.meters! < .9;
    final sentence = '${name[0].toUpperCase()}${name.substring(1)} $where'
        '${distance.isEmpty ? '' : ', $distance'}';
    final caution =
        !cautioned && ((close && parts.isEmpty) || isDropHazard(first.label));
    cautioned |= caution;
    parts.add(caution ? 'Caution. $sentence' : sentence);
  }
  return '${parts.join('. ')}.';
}

/// Identifies a scene for the "do not repeat yourself" check: what is where
/// and roughly how far, ignoring small changes.
String sceneKey(List<SceneObject> nearest, double frameWidth, {int limit = 2}) {
  return nearest
      .take(limit)
      .map((o) =>
          '${o.label}@${sideOf(o, frameWidth).name}#${distanceBucket(o.meters)}')
      .join('|');
}

/// Attaches camera distances to detections given as plain boxes.
SceneObject rangedObject({
  required String label,
  required double confidence,
  required double left,
  required double top,
  required double right,
  required double bottom,
  required double frameWidth,
  required double frameHeight,
  DistanceEstimator estimator = const DistanceEstimator(),
}) {
  final range = estimator.estimate(
      label: label,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      frameWidth: frameWidth,
      frameHeight: frameHeight);
  return SceneObject(
      label: label,
      confidence: confidence,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      meters: range?.meters);
}
