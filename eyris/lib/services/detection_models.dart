/// Which frames a model runs on. The main model sees every frame; helper
/// models take turns so the phone never runs more than two at once.
enum ModelSlot { everyFrame, evenFrames, oddFrames }

/// One TFLite detector bundled with the app.
class DetectorSpec {
  const DetectorSpec({
    required this.tag,
    required this.asset,
    required this.labelsAsset,
    required this.names,
    required this.thresholds,
    this.backedThresholds = const {},
    this.defaultThreshold = 0.35,
    this.slot = ModelSlot.everyFrame,
    this.threads = 2,
    this.maxPerLabel = 3,
    this.listedOnly = false,
    this.alsoCompete = const {},
    this.soloLabels = const {},
    this.cautionThresholds = const {},
  });

  /// Short name used in log lines.
  final String tag;
  final String asset;

  /// The model's own class names, one per line, in the model's order.
  final String labelsAsset;

  /// Model class name (lower case) -> label shown and spoken by the app.
  /// Classes that are not listed are never reported. Some models carry
  /// extra classes (floor, ceiling, window...) only so that those surfaces
  /// are recognised as what they are instead of as furniture.
  final Map<String, String> names;

  /// Confidence from which this model is believed on its own word, per
  /// spoken label, measured on labelled photos with
  /// training/tune_precision.py. Labels not listed use [defaultThreshold].
  final Map<String, double> thresholds;

  /// Lower confidence that is enough when another model sees the same label
  /// in the same place. A label listed only here is never reported on this
  /// model's word alone.
  final Map<String, double> backedThresholds;
  final double defaultThreshold;
  final ModelSlot slot;
  final int threads;
  final int maxPerLabel;

  /// True for the open-vocabulary model, whose classes are text prompts
  /// scored independently: only the prompts in [names] take part. False for
  /// trained models, where the surroundings (floor, ceiling...) compete so
  /// that a ceiling is not reported as furniture.
  final bool listedOnly;

  /// With [listedOnly]: prompts that take part without being reported, so
  /// that a car is not called a truck just because "car" is another
  /// model's job.
  final Set<String> alsoCompete;

  /// With [listedOnly]: labels whose prompts are scored apart from all the
  /// others. A speed breaker is part of the road, so "car" or "wall" in
  /// the same spot would otherwise always win.
  final Set<String> soloLabels;

  /// For labels that are dangerous to miss: a box between this confidence
  /// and the reporting one is not reported or spoken (it would break the
  /// 9-in-10 rule), but it keeps the app from calling the path clear.
  final Map<String, double> cautionThresholds;

  double thresholdFor(String label) =>
      thresholds[label] ??
      (backedThresholds.containsKey(label) ? double.infinity : defaultThreshold);

  /// Confidence from which a box takes part in detection: reported alone
  /// ([thresholdFor]) or when another model backs it up.
  double backingFloorFor(String label) {
    final alone = thresholdFor(label);
    final backed = backedThresholds[label];
    return backed != null && backed < alone ? backed : alone;
  }

  /// Confidence below which a box of [label] is of no use at all: not
  /// reported, not backing another model, not a reason for caution.
  double floorFor(String label) {
    final floor = backingFloorFor(label);
    final caution = cautionThresholds[label];
    return caution != null && caution < floor ? caution : floor;
  }

  double get lowestThreshold {
    var lowest = defaultThreshold;
    for (final value in [
      ...thresholds.values,
      ...backedThresholds.values,
      ...cautionThresholds.values,
    ]) {
      if (value < lowest) lowest = value;
    }
    return lowest;
  }
}

/// Furniture that only exists indoors. A confident sighting rules out road
/// hazards (pothole, speed breaker, footpath) in the same frame.
const indoorLabels = {'Bed', 'Sofa', 'Table', 'Chair', 'Laptop', 'AC', 'Fan'};

/// Every label the app can report.
const allLabels = [
  'Person', 'Car', 'Bike', 'Truck', 'Bus', 'Pothole', 'Tree', 'Pole',
  'Traffic sign', 'Chair', 'Table', 'Door', 'Stairs', 'Wall', 'Bed', 'Sofa',
  'Bottle', 'Dustbin', 'Backpack', 'Laptop',
  // Added on client request. "AC" covers standing units (hazard model) and
  // wall units (scene model). "Open drain": open manholes, missing or broken
  // drain slabs, open drain channels (hazard model).
  'Speed breaker', 'Footpath', 'AC', 'Fan', 'Open drain',
];

// A label may come from several models. Every confidence below was picked by
// training/tune_precision.py so that at least 9 of 10 reported objects are
// right on labelled test photos, through the phone camera and through
// imitated ESP32 frames alike (training/accuracy_report.json). Door, AC,
// Fan and Speed breaker could not be settled that way for the first three
// models; their values and the reasons are in training/manual_thresholds.json.
// Pothole, speed breaker and standing AC now come mainly from the hazard
// model, measured by training/hazard_eval.py (training/hazard_report.json).

/// Main model: YOLOv8s trained on fully labelled indoor and street scenes
/// (ADE20K). Source for the building itself: wall, door, stairs, footpath.
const sceneModel = DetectorSpec(
  tag: 'scene',
  asset: 'assets/models/eyris_scene.tflite',
  labelsAsset: 'assets/models/labels_scene.txt',
  slot: ModelSlot.everyFrame,
  threads: 4,
  names: {
    'person': 'Person',
    'bus': 'Bus',
    'pole': 'Pole',
    'table': 'Table',
    'door': 'Door',
    'stairs': 'Stairs',
    'wall': 'Wall',
    'bed': 'Bed',
    'sofa': 'Sofa',
    'bottle': 'Bottle',
    'bag': 'Backpack',
    'footpath': 'Footpath',
    'air conditioner': 'AC',
    'fan': 'Fan',
  },
  thresholds: {
    'AC': 0.25,
    'Bed': 0.60,
    'Bus': 0.48,
    'Door': 0.60,
    'Fan': 0.30,
    'Footpath': 0.26,
    'Person': 0.66,
    'Sofa': 0.47,
    'Stairs': 0.47,
    'Wall': 0.72,
  },
  backedThresholds: {
    'Backpack': 0.22,
    'Bottle': 0.60,
    'Pole': 0.60,
    'Stairs': 0.35,
    'Table': 0.50,
  },
);

/// Open-vocabulary helper (YOLO-World, classes are text prompts): people,
/// vehicles, furniture and small objects, where it measured best.
const worldModel = DetectorSpec(
  tag: 'world',
  asset: 'assets/models/eyris_world.tflite',
  labelsAsset: 'assets/models/labels_world.txt',
  slot: ModelSlot.oddFrames,
  listedOnly: true,
  soloLabels: {'Speed breaker'},
  names: {
    'person': 'Person',
    'car': 'Car',
    'motorcycle': 'Bike',
    'bicycle': 'Bike',
    'truck': 'Truck',
    'bus': 'Bus',
    'pole': 'Pole',
    'utility pole': 'Pole',
    'street light': 'Pole',
    'lamp post': 'Pole',
    'traffic sign': 'Traffic sign',
    'road sign': 'Traffic sign',
    'stop sign': 'Traffic sign',
    'traffic light': 'Traffic sign',
    'chair': 'Chair',
    'table': 'Table',
    'desk': 'Table',
    'dining table': 'Table',
    'stairs': 'Stairs',
    'staircase': 'Stairs',
    'steps': 'Stairs',
    'bed': 'Bed',
    'sofa': 'Sofa',
    'couch': 'Sofa',
    'bottle': 'Bottle',
    'dustbin': 'Dustbin',
    'trash can': 'Dustbin',
    'garbage bin': 'Dustbin',
    'backpack': 'Backpack',
    'handbag': 'Backpack',
    'suitcase': 'Backpack',
    'laptop': 'Laptop',
    'speed bump': 'Speed breaker',
    'speed breaker': 'Speed breaker',
    'road hump': 'Speed breaker',
  },
  // The AC prompts fire on windows, cabinets and doors, so they are no
  // longer reported; they still compete so those are not called furniture.
  alsoCompete: {
    'tree', 'palm tree', 'tree trunk', 'door', 'closed door', 'doorway',
    'wall', 'air conditioner', 'floor standing air conditioner',
    'tower air conditioner',
  },
  thresholds: {
    'Backpack': 0.55,
    'Bed': 0.64,
    'Bike': 0.55,
    'Bottle': 0.74,
    'Bus': 0.79,
    'Car': 0.46,
    'Chair': 0.47,
    'Laptop': 0.49,
    'Person': 0.21,
    'Speed breaker': 0.20,
    'Table': 0.55,
    'Traffic sign': 0.75,
    'Truck': 0.65,
  },
  backedThresholds: {
    'Backpack': 0.18,
    'Bottle': 0.15,
    'Car': 0.26,
    'Dustbin': 0.50,
    'Laptop': 0.12,
    'Pole': 0.22,
    'Sofa': 0.26,
    'Stairs': 0.26,
    'Table': 0.22,
  },
);

/// Road model (YOLOv8s trained on road photos, RDD2022 + Open Images): the
/// pothole and tree source, and a second opinion on what the others see.
const roadModel = DetectorSpec(
  tag: 'road',
  asset: 'assets/models/eyris_road.tflite',
  labelsAsset: 'assets/models/labels_road.txt',
  slot: ModelSlot.evenFrames,
  names: {
    'person': 'Person',
    'car': 'Car',
    'motorcycle': 'Bike',
    'bicycle': 'Bike',
    'bus': 'Bus',
    'tree': 'Tree',
    'pole': 'Pole',
    'traffic sign': 'Traffic sign',
    'stairs': 'Stairs',
    'sofa': 'Sofa',
    'bottle': 'Bottle',
    'dustbin': 'Dustbin',
    'bag': 'Backpack',
    'laptop': 'Laptop',
    'pothole': 'Pothole',
  },
  thresholds: {
    'Backpack': 0.40,
    'Bike': 0.59,
    'Bus': 0.81,
    'Car': 0.62,
    'Person': 0.44,
    'Pothole': 0.77,
    'Traffic sign': 0.85,
    'Tree': 0.69,
  },
  backedThresholds: {
    'Bottle': 0.60,
    'Car': 0.40,
    'Dustbin': 0.12,
    'Laptop': 0.50,
    'Pole': 0.40,
    'Sofa': 0.50,
    'Stairs': 0.08,
  },
);

/// Hazard model (YOLOv8s trained on labelled photos of potholes, speed
/// bumps, floor-standing ACs and open drains): the objects the other models
/// could not find. Confidences from training/hazard_eval.py, which runs the
/// app's pipeline through the phone camera and imitated ESP32 frames.
const hazardModel = DetectorSpec(
  tag: 'hazard',
  asset: 'assets/models/eyris_hazard.tflite',
  labelsAsset: 'assets/models/labels_hazard.txt',
  slot: ModelSlot.evenFrames,
  names: {
    'pothole': 'Pothole',
    'speed breaker': 'Speed breaker',
    'standing ac': 'AC',
    'open drain': 'Open drain',
  },
  // Right of reported, phone / ESP32 frames (training/hazard_report.json):
  // open drain 93% / 94% at 0.73, found 63% / 55%. Speed breaker 96% / 95%,
  // found 87% / 85%. Pothole 91% / 92% on road photos, found 41% / 36%,
  // as in 1.0.5; closed manhole covers are still sometimes taken for
  // potholes (19 of 221 cover photos, against 39 with the 1.0.5 model).
  // Standing AC: 4 of 11 test photos found, none wrong; too few photos to
  // call the percentage measured.
  thresholds: {
    'Pothole': 0.60,
    'Speed breaker': 0.35,
    'AC': 0.60,
    'Open drain': 0.73,
  },
  // A weaker open-drain box (from 0.35) is not named, but the path is not
  // called clear: then 74-76% of drains hold back "Path clear", and a box
  // shows up on 0.7-0.8% of test photos without one (training/drain_caution.py).
  cautionThresholds: {'Open drain': 0.35},
);

const detectorSpecs = [sceneModel, worldModel, roadModel, hazardModel];
