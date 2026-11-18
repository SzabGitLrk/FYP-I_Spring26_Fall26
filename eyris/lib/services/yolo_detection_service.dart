import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import 'detection_models.dart';

// --- Latency tuning ---------------------------------------------------------
// tflite_flutter marshals a nested List<double> input one boxed element at a
// time (hundreds of ms per frame). A Uint8List of raw little-endian float32
// bytes hits the zero-conversion fast path and is memcpy'd across isolate
// ports. Same for outputs: a Uint8List output buffer is filled in place.
const bool useXnnPackDelegate = true; // falls back to plain CPU on failure
// Experimental only: GPU delegate + IsolateInterpreter (invoke on a worker
// thread) is not guaranteed safe with OpenGL-backed delegates.
const bool useGpuDelegate = false;

/// Grey used to pad a frame to the model's square input (Ultralytics' 114).
const double _padValue = 114 / 255;

class YoloDetection {
  final String label;
  final double confidence;
  final Rect boundingBox;

  /// Tag of the model that found it.
  final String source;

  /// True when the model is not confident enough to be believed alone: the
  /// box only counts if another model sees the same thing there.
  final bool needsBacking;

  /// True for a weak sighting (DetectorSpec.cautionThresholds): never
  /// reported or spoken, only a reason not to call the path clear.
  final bool hint;
  YoloDetection(
      {required this.label,
      required this.confidence,
      required this.boundingBox,
      this.source = '',
      this.needsBacking = false,
      this.hint = false});
  String getAlertMessage() => '$label detected ahead';
}

/// A box straight out of a model: class index, score and corners in the
/// model's input pixels.
class RawBox {
  const RawBox(this.classId, this.score, this.x1, this.y1, this.x2, this.y2);
  final int classId;
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// How a frame was fitted into a square model input: scaled by [scale], then
/// centred with [padX]/[padY] pixels of grey on each side.
class Letterbox {
  const Letterbox(this.scale, this.padX, this.padY, this.width, this.height);

  factory Letterbox.fit(int sourceWidth, int sourceHeight, int inputSize) {
    final scale =
        math.min(inputSize / sourceWidth, inputSize / sourceHeight);
    final width = math.max(1, (sourceWidth * scale).round());
    final height = math.max(1, (sourceHeight * scale).round());
    return Letterbox(scale, (inputSize - width) ~/ 2,
        (inputSize - height) ~/ 2, width, height);
  }

  final double scale;
  final int padX;
  final int padY;

  /// Size of the scaled frame inside the input.
  final int width;
  final int height;
}

/// Decodes a raw Ultralytics detection output: `[1, 4 + classes, N]` or
/// `[1, N, 4 + classes]`, each candidate being `[cx, cy, w, h, class
/// probabilities...]`. Boxes come back in input pixels.
///
/// With [allowedClasses] only those classes take part: an open-vocabulary
/// model scores every prompt on its own, so a prompt the app does not
/// report ("road") must not hide one it does ("road hump").
///
/// Returns null when the tensor does not have exactly [classCount] class
/// columns. That is how a labels file belonging to a different model is
/// caught instead of silently naming every object wrongly.
List<RawBox>? decodeRawYolo(
  Float32List data,
  List<int> shape, {
  required int classCount,
  required int inputSize,
  double minScore = 0.05,
  List<bool>? allowedClasses,
}) {
  if (shape.length != 3 || classCount < 1) return null;
  if (allowedClasses != null && allowedClasses.length != classCount) return null;
  final attributes = 4 + classCount;
  final bool attributesFirst;
  if (shape[1] == attributes && shape[2] != attributes) {
    attributesFirst = true;
  } else if (shape[2] == attributes && shape[1] != attributes) {
    attributesFirst = false;
  } else if (shape[1] == attributes && shape[2] == attributes) {
    attributesFirst = true;
  } else {
    return null;
  }
  final candidates = attributesFirst ? shape[2] : shape[1];
  if (data.length < attributes * candidates) return null;

  final boxes = <RawBox>[];
  for (var c = 0; c < candidates; c++) {
    var best = minScore;
    var classId = -1;
    if (attributesFirst) {
      for (var a = 4; a < attributes; a++) {
        if (allowedClasses != null && !allowedClasses[a - 4]) continue;
        final v = data[a * candidates + c];
        if (v > best) {
          best = v;
          classId = a - 4;
        }
      }
    } else {
      final base = c * attributes;
      for (var a = 4; a < attributes; a++) {
        if (allowedClasses != null && !allowedClasses[a - 4]) continue;
        final v = data[base + a];
        if (v > best) {
          best = v;
          classId = a - 4;
        }
      }
    }
    if (classId < 0) continue;
    double cx, cy, w, h;
    if (attributesFirst) {
      cx = data[c];
      cy = data[candidates + c];
      w = data[2 * candidates + c];
      h = data[3 * candidates + c];
    } else {
      final base = c * attributes;
      cx = data[base];
      cy = data[base + 1];
      w = data[base + 2];
      h = data[base + 3];
    }
    // TFLite exports report boxes as a fraction of the input size.
    if (cx.abs() <= 1.5 && cy.abs() <= 1.5 && w.abs() <= 1.5 && h.abs() <= 1.5) {
      cx *= inputSize;
      cy *= inputSize;
      w *= inputSize;
      h *= inputSize;
    }
    boxes.add(RawBox(
        classId, best, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2));
  }
  return boxes;
}

double boxIou(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.width <= 0 || intersection.height <= 0) return 0;
  final area = intersection.width * intersection.height;
  return area / (a.width * a.height + b.width * b.height - area);
}

/// Turns raw boxes into labelled detections in frame pixels: applies the
/// model's name table and per-label thresholds, undoes the letterbox and
/// removes duplicate boxes of the same label.
List<YoloDetection> labelDetections(
  List<RawBox> boxes, {
  required DetectorSpec spec,
  required List<String> modelNames,
  required Letterbox letterbox,
  required int frameWidth,
  required int frameHeight,
  double frameScale = 1,
}) {
  final found = <YoloDetection>[];
  for (final box in boxes) {
    if (box.classId >= modelNames.length) continue;
    final label = spec.names[modelNames[box.classId]];
    if (label == null) continue; // not a class the app reports
    if (box.score < spec.floorFor(label)) continue;
    // Input pixels -> pixels of the frame handed to the model -> frame.
    final k = frameScale / letterbox.scale;
    final rect = Rect.fromLTRB(
      ((box.x1 - letterbox.padX) * k).clamp(0, frameWidth).toDouble(),
      ((box.y1 - letterbox.padY) * k).clamp(0, frameHeight).toDouble(),
      ((box.x2 - letterbox.padX) * k).clamp(0, frameWidth).toDouble(),
      ((box.y2 - letterbox.padY) * k).clamp(0, frameHeight).toDouble(),
    );
    if (rect.width <= 2 || rect.height <= 2) continue;
    found.add(YoloDetection(
        label: label,
        confidence: box.score,
        boundingBox: rect,
        source: spec.tag,
        needsBacking: box.score < spec.thresholdFor(label),
        hint: box.score < spec.backingFloorFor(label)));
  }
  found.sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <YoloDetection>[];
  final perLabel = <String, int>{};
  for (final detection in found) {
    if ((perLabel[detection.label] ?? 0) >= spec.maxPerLabel) continue;
    final duplicate = kept.any((other) =>
        other.label == detection.label &&
        boxIou(other.boundingBox, detection.boundingBox) > 0.5);
    if (duplicate) continue;
    kept.add(detection);
    perLabel[detection.label] = (perLabel[detection.label] ?? 0) + 1;
  }
  return kept;
}

/// Overlap from which two models count as seeing the same object.
const double backingIou = 0.4;

/// Keeps what a model is sure of, plus the less confident boxes that a
/// different model also found in the same place under the same label. Two
/// models agreeing are right far more often than either one alone.
List<YoloDetection> confirmAcrossModels(List<YoloDetection> all) => [
      for (final detection in all)
        if (!detection.needsBacking ||
            all.any((other) =>
                other.source != detection.source &&
                other.label == detection.label &&
                boxIou(other.boundingBox, detection.boundingBox) >= backingIou))
          detection,
    ];

/// Checks that depend on where a box sits in the view. They remove the
/// detections that cannot be what their label says: a "pothole" on the
/// ceiling, a sliver of side wall reported as a wall in the way.
List<YoloDetection> applySceneRules(
    List<YoloDetection> detections, int frameWidth, int frameHeight) {
  final frameArea = frameWidth * frameHeight.toDouble();
  final strongIndoor = detections.any(
      (d) => indoorLabels.contains(d.label) && d.confidence >= 0.60);
  final kept = <YoloDetection>[];
  for (final d in detections) {
    final box = d.boundingBox;
    final area = box.width * box.height;
    final centerY = (box.top + box.bottom) / 2;
    if (d.source == hazardModel.tag) {
      // The hazard model was trained on these objects from up close and
      // far away, so position rules would only lose real ones. Only the
      // shape is checked: a speed breaker is a strip across the road, a
      // standing AC is taller than wide.
      if (d.label != 'AC' && strongIndoor) continue;
      if (d.label == 'Speed breaker' && box.width < box.height) continue;
      if (d.label == 'AC' && box.height < box.width) continue;
      kept.add(d);
      continue;
    }
    switch (d.label) {
      case 'Pothole':
        // Potholes are small, low in the frame, and not in a living room.
        if (strongIndoor) continue;
        if (area > frameArea * 0.30) continue;
        if (box.height > frameHeight * 0.60) continue;
        if (centerY < frameHeight * 0.50) continue;
        break;
      case 'Speed breaker':
        // A strip across the road: on the ground, wider than tall, and
        // small. The model also answers "speed breaker" for the road
        // itself, with a box over the whole carriageway: on plain-road
        // photos that was more than half of all frames.
        if (strongIndoor) continue;
        if (centerY < frameHeight * 0.45) continue;
        if (box.width < box.height) continue;
        if (area > frameArea * 0.20) continue;
        if (box.height > frameHeight * 0.35) continue;
        break;
      case 'Footpath':
        if (strongIndoor) continue;
        if (box.bottom < frameHeight * 0.55) continue;
        break;
      case 'Wall':
        // Every room has walls. Only a wall across the middle of the view
        // that fills much of it is an obstacle worth reporting.
        if (area < frameArea * 0.30) continue;
        if (box.left > frameWidth * 0.40 || box.right < frameWidth * 0.60) {
          continue;
        }
        break;
    }
    kept.add(d);
  }
  return kept;
}

/// What one frame comes to: the objects to report, and the weak sightings
/// that only hold back "Path clear". Weak sightings never back up another
/// model and are never reported, but the same scene rules apply to them.
({List<YoloDetection> reported, List<YoloDetection> weak}) combineDetections(
    List<YoloDetection> seen, int frameWidth, int frameHeight) {
  final ruled = applySceneRules([
    ...confirmAcrossModels([for (final d in seen) if (!d.hint) d]),
    for (final d in seen)
      if (d.hint) d,
  ], frameWidth, frameHeight);
  return (
    reported: mergeDetections([for (final d in ruled) if (!d.hint) d]),
    weak: [for (final d in ruled) if (d.hint) d],
  );
}

/// Merges detections of several models: same label and overlapping boxes
/// count once, the more confident one wins. Capped so a flood can never
/// reach the screen or the voice.
List<YoloDetection> mergeDetections(List<YoloDetection> all, {int limit = 12}) {
  final sorted = [...all]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <YoloDetection>[];
  for (final detection in sorted) {
    if (kept.length >= limit) break;
    final duplicate = kept.any((other) =>
        other.label == detection.label &&
        boxIou(other.boundingBox, detection.boundingBox) > 0.5);
    if (!duplicate) kept.add(detection);
  }
  return kept;
}

/// RGBA frame -> flat float32 tensor ([0,1]) letterboxed into a square
/// [size] x [size] input, NCHW or NHWC. Runs in a compute isolate; the
/// Float32List result crosses the port as one memcpy.
Float32List letterboxToTensor(Uint8List rgba, int sw, int sh, int size,
    bool channelsFirst) {
  final count = size * size;
  final pixels = Float32List(count * 3)
    ..fillRange(0, count * 3, _padValue);
  if (sw < 1 || sh < 1 || rgba.length < sw * sh * 4) return pixels;
  final box = Letterbox.fit(sw, sh, size);
  final xRatio = sw / box.width;
  final yRatio = sh / box.height;
  for (var y = 0; y < box.height; y++) {
    final fy = (y + 0.5) * yRatio - 0.5;
    var y0 = fy.floor();
    if (y0 < 0) y0 = 0;
    if (y0 > sh - 1) y0 = sh - 1;
    final y1 = y0 + 1 > sh - 1 ? sh - 1 : y0 + 1;
    final dy = (fy - y0).clamp(0.0, 1.0);
    final row0 = y0 * sw;
    final row1 = y1 * sw;
    final outRow = (y + box.padY) * size + box.padX;
    for (var x = 0; x < box.width; x++) {
      final fx = (x + 0.5) * xRatio - 0.5;
      var x0 = fx.floor();
      if (x0 < 0) x0 = 0;
      if (x0 > sw - 1) x0 = sw - 1;
      final x1 = x0 + 1 > sw - 1 ? sw - 1 : x0 + 1;
      final dx = (fx - x0).clamp(0.0, 1.0);
      final i00 = (row0 + x0) * 4;
      final i01 = (row0 + x1) * 4;
      final i10 = (row1 + x0) * 4;
      final i11 = (row1 + x1) * 4;
      final w00 = (1 - dx) * (1 - dy), w01 = dx * (1 - dy);
      final w10 = (1 - dx) * dy, w11 = dx * dy;
      final r = (rgba[i00] * w00 +
              rgba[i01] * w01 +
              rgba[i10] * w10 +
              rgba[i11] * w11) /
          255.0;
      final g = (rgba[i00 + 1] * w00 +
              rgba[i01 + 1] * w01 +
              rgba[i10 + 1] * w10 +
              rgba[i11 + 1] * w11) /
          255.0;
      final b = (rgba[i00 + 2] * w00 +
              rgba[i01 + 2] * w01 +
              rgba[i10 + 2] * w10 +
              rgba[i11 + 2] * w11) /
          255.0;
      final p = outRow + x;
      if (channelsFirst) {
        pixels[p] = r;
        pixels[count + p] = g;
        pixels[count * 2 + p] = b;
      } else {
        final o = p * 3;
        pixels[o] = r;
        pixels[o + 1] = g;
        pixels[o + 2] = b;
      }
    }
  }
  return pixels;
}

/// compute() entry point. Takes an RGBA buffer, or as a fallback the raw
/// JPEG bytes when the native decode failed upstream.
Map<String, Object> _prepareInput(Map<String, Object> args) {
  final size = args['size'] as int;
  final channelsFirst = args['channelsFirst'] as bool;
  var rgba = args['rgba'] as Uint8List?;
  var width = args['rgbaWidth'] as int? ?? 0;
  var height = args['rgbaHeight'] as int? ?? 0;
  if (rgba == null || width <= 0 || height <= 0) {
    final bytes = args['bytes'] as Uint8List?;
    final frame = bytes == null ? null : img.decodeImage(bytes);
    if (frame == null) {
      return {'pixels': Float32List(0), 'width': 0, 'height': 0};
    }
    rgba = frame.getBytes(order: img.ChannelOrder.rgba);
    width = frame.width;
    height = frame.height;
  }
  return {
    'pixels': letterboxToTensor(rgba, width, height, size, channelsFirst),
    'width': width,
    'height': height,
  };
}

/// Tiny FIFO async mutex (no packages). Serializes TFLite invokes so a
/// torn frame or lifecycle race can never interleave two runs on one
/// interpreter: that interleaving segfaults the JNI runtime (seen).
class _Mutex {
  Future<void>? _tail;
  Future<T> run<T>(Future<T> Function() task) async {
    final prev = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    try {
      if (prev != null) await prev;
      return await task();
    } finally {
      completer.complete();
    }
  }
}

class _LoadedModel {
  _LoadedModel(this.spec);
  final DetectorSpec spec;
  Interpreter? interpreter;
  IsolateInterpreter? isolate;
  List<int> inputShape = const [];
  List<int> outputShape = const [];
  List<String> names = const [];
  List<bool>? allowedClasses;
  List<bool>? soloClasses;
  bool channelsFirst = false;
  int inputSize = 0;
  // Each interpreter has its own lock, so different models run in parallel.
  final _Mutex lock = _Mutex();
  // What this model saw the last time it ran. A helper model skips every
  // other frame; its detections are carried over so they do not flicker.
  List<YoloDetection> lastDetections = const [];
  int lastFrame = -1;
  DateTime lastReload = DateTime.fromMillisecondsSinceEpoch(0);
  bool reloading = false;
  // Set when a working model failed mid-run and should be rebuilt. A model
  // that is missing or does not match its labels is never retried.
  bool needsReload = false;

  bool get loaded => interpreter != null && isolate != null;

  void close() {
    try {
      isolate?.close();
    } catch (_) {}
    isolate = null;
    try {
      interpreter?.close();
    } catch (_) {}
    interpreter = null;
  }
}

class YoloDetectionService {
  YoloDetectionService({List<DetectorSpec>? specs})
      : _models = [for (final spec in specs ?? detectorSpecs) _LoadedModel(spec)];

  final List<_LoadedModel> _models;
  int _frameCounter = 0;
  bool _disposed = false;
  List<YoloDetection> _weakSightings = const [];

  bool get isLoaded => _models.any((m) => m.loaded);

  /// Weak sightings of the last [detectImage] (see [combineDetections]).
  List<YoloDetection> get weakSightings => _weakSightings;

  /// Largest model input. The camera screen decodes each frame once to about
  /// this size and every model letterboxes that shared buffer.
  int get mainInputSize {
    var size = 0;
    for (final model in _models) {
      if (model.loaded && model.inputSize > size) size = model.inputSize;
    }
    return size > 0 ? size : 384;
  }

  Future<Interpreter> _createInterpreter(String asset, int threads) async {
    if (useGpuDelegate) {
      try {
        final options = InterpreterOptions()..addDelegate(GpuDelegateV2());
        final interpreter = await Interpreter.fromAsset(asset, options: options);
        debugPrint('[tflite] $asset -> gpu delegate');
        return interpreter;
      } catch (error) {
        debugPrint('[tflite] GPU delegate failed for $asset: $error');
      }
    }
    // XNNPACK: usually the fastest CPU path for float32 convnets. Falls
    // through to plain CPU when the model contains an op it does not take.
    if (useXnnPackDelegate) {
      try {
        final options = InterpreterOptions()
          ..addDelegate(XNNPackDelegate(
              options: XNNPackDelegateOptions(numThreads: threads)));
        final interpreter = await Interpreter.fromAsset(asset, options: options);
        debugPrint('[tflite] $asset -> xnnpack x$threads');
        return interpreter;
      } catch (error) {
        debugPrint('[tflite] XNNPACK failed for $asset: $error');
      }
    }
    try {
      final options = InterpreterOptions()..threads = threads;
      final interpreter = await Interpreter.fromAsset(asset, options: options);
      debugPrint('[tflite] $asset -> cpu x$threads');
      return interpreter;
    } catch (_) {}
    return await Interpreter.fromAsset(asset);
  }

  Future<void> loadModel() async {
    for (final model in _models) {
      if (_disposed) return;
      await _load(model);
    }
    debugPrint('[yolo] models ready: '
        '${_models.where((m) => m.loaded).map((m) => '${m.spec.tag}@${m.inputSize}').join(', ')}');
  }

  Future<void> _load(_LoadedModel model) async {
    final spec = model.spec;
    // Check the bundle first so a missing file logs one quiet line instead
    // of a delegate error.
    try {
      await rootBundle.load(spec.asset);
    } catch (_) {
      debugPrint('[${spec.tag}] ${spec.asset} is not bundled, skipped');
      return;
    }
    try {
      final rawNames = await rootBundle.loadString(spec.labelsAsset);
      final names = rawNames
          .split(RegExp(r'\r?\n'))
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();
      final interpreter = await _createInterpreter(spec.asset, spec.threads);
      if (_disposed) {
        interpreter.close();
        return;
      }
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      final inShape = input.shape;
      final outShape = output.shape;
      final nhwc = inShape.length == 4 && inShape[3] == 3;
      final nchw = inShape.length == 4 && inShape[1] == 3 && !nhwc;
      final size = nchw ? inShape[3] : (nhwc ? inShape[2] : 0);
      final square = nchw ? inShape[2] == size : (nhwc && inShape[1] == size);
      final attributes = 4 + names.length;
      String? problem;
      if (!square || size <= 0) {
        problem = 'input $inShape is not a square RGB image';
      } else if (input.type != TensorType.float32 ||
          output.type != TensorType.float32) {
        problem = 'tensors are not float32';
      } else if (outShape.length != 3 ||
          (outShape[1] != attributes && outShape[2] != attributes)) {
        // The labels file and the model disagree. Guessing here is what
        // makes an app call every door a table, so refuse the model.
        problem = 'output $outShape does not have ${names.length} classes '
            'like ${spec.labelsAsset}';
      }
      if (problem != null) {
        debugPrint('[${spec.tag}] NOT LOADED: $problem');
        interpreter.close();
        return;
      }
      model.interpreter = interpreter;
      model.inputShape = inShape;
      model.outputShape = outShape;
      model.names = names;
      bool solo(String name) => spec.soloLabels.contains(spec.names[name]);
      model.allowedClasses = spec.listedOnly
          ? [
              for (final name in names)
                !solo(name) &&
                    (spec.names.containsKey(name) ||
                        spec.alsoCompete.contains(name))
            ]
          : null;
      model.soloClasses = spec.listedOnly && names.any(solo)
          ? [for (final name in names) solo(name)]
          : null;
      model.channelsFirst = nchw;
      model.inputSize = size;
      model.isolate =
          await IsolateInterpreter.create(address: interpreter.address);
      debugPrint('[${spec.tag}] loaded ${spec.asset}: input=$inShape '
          'output=$outShape classes=${names.length}');
    } catch (error) {
      model.close();
      debugPrint('[${spec.tag}] unavailable: $error');
    }
  }

  /// A failed invoke can leave the native interpreter unusable; reusing it
  /// segfaults (Pixel 7a seen). Rebuild it, at most every 10 seconds.
  Future<void> _reloadLater(_LoadedModel model) async {
    if (_disposed || model.reloading || !model.needsReload) return;
    if (DateTime.now().difference(model.lastReload) <
        const Duration(seconds: 10)) {
      return;
    }
    model.reloading = true;
    model.lastReload = DateTime.now();
    try {
      model.close();
      await _load(model);
      if (model.loaded) model.needsReload = false;
    } finally {
      model.reloading = false;
    }
  }

  /// Raw float32 output buffer for a float32 tensor of [shape]. The
  /// interpreter fills it in place.
  Uint8List _outputBytes(List<int> shape) =>
      Uint8List(shape.reduce((a, b) => a * b) * 4);

  /// Detects objects in one frame. [imageWidth] x [imageHeight] is the size
  /// of the camera frame and the coordinate space of the returned boxes.
  /// [rgbaInput] is that frame, usually downscaled, keeping its proportions.
  Future<List<YoloDetection>> detectImage(
    Uint8List imageBytes,
    int imageWidth,
    int imageHeight, {
    Uint8List? rgbaInput,
    int? rgbaWidth,
    int? rgbaHeight,
  }) async {
    _weakSightings = const [];
    for (final model in _models) {
      if (!model.loaded) unawaited(_reloadLater(model));
    }
    if (!isLoaded) return [];
    // The main model runs on every frame; the helpers take turns. Running
    // everything on every frame saturated the phone's CPU and starved the
    // camera threads.
    _frameCounter++;
    final turn = (_frameCounter & 1) == 0 ? ModelSlot.evenFrames : ModelSlot.oddFrames;
    final active = _models
        .where((m) =>
            m.loaded &&
            (m.spec.slot == ModelSlot.everyFrame || m.spec.slot == turn))
        .toList();
    final stopwatch = Stopwatch()..start();
    final results = await Future.wait(active.map((model) => _run(
        model, imageBytes, imageWidth, imageHeight,
        rgbaInput: rgbaInput, rgbaWidth: rgbaWidth, rgbaHeight: rgbaHeight)));
    for (var i = 0; i < active.length; i++) {
      active[i].lastDetections = results[i];
      active[i].lastFrame = _frameCounter;
    }
    final carried = _models
        .where((m) => !active.contains(m) && m.lastFrame == _frameCounter - 1)
        .expand((m) => m.lastDetections);
    final frame = combineDetections(
        [...results.expand((r) => r), ...carried], imageWidth, imageHeight);
    final kept = frame.reported;
    _weakSightings = frame.weak;
    debugPrint('[yolo] ${stopwatch.elapsedMilliseconds}ms '
        '${[for (var i = 0; i < active.length; i++) '${active[i].spec.tag}=${results[i].length}'].join(' ')}'
        '${kept.isEmpty ? '' : ' -> ${kept.map((d) => '${d.label} ${d.confidence.toStringAsFixed(2)}').join(', ')}'}'
        '${frame.weak.isEmpty ? '' : ' weak: ${frame.weak.map((d) => '${d.label} ${d.confidence.toStringAsFixed(2)}').join(', ')}'}');
    return kept;
  }

  Future<List<YoloDetection>> _run(
      _LoadedModel model, Uint8List imageBytes, int imageWidth, int imageHeight,
      {Uint8List? rgbaInput, int? rgbaWidth, int? rgbaHeight}) async {
    final spec = model.spec;
    try {
      final isolate = model.isolate;
      if (isolate == null) return [];
      final prepared = await compute(_prepareInput, {
        // Only ship the JPEG across the port when there is no RGBA buffer.
        if (rgbaInput == null) 'bytes': imageBytes,
        if (rgbaInput != null) 'rgba': rgbaInput,
        if (rgbaWidth != null) 'rgbaWidth': rgbaWidth,
        if (rgbaHeight != null) 'rgbaHeight': rgbaHeight,
        'size': model.inputSize,
        'channelsFirst': model.channelsFirst,
      }, debugLabel: 'prepare-${spec.tag}');
      final pixels = prepared['pixels'] as Float32List;
      final sourceWidth = prepared['width'] as int;
      final sourceHeight = prepared['height'] as int;
      // Guard: a torn frame must never reach the interpreter.
      if (sourceWidth <= 0 ||
          pixels.length != model.inputShape.reduce((a, b) => a * b)) {
        debugPrint('[${spec.tag}] frame could not be prepared, skipped');
        return [];
      }
      final input =
          pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);
      final output = _outputBytes(model.outputShape);
      try {
        await model.lock.run(() => isolate.run(input, output));
      } catch (error) {
        debugPrint('[${spec.tag}] invoke failed: $error');
        model.close();
        model.needsReload = true;
        return [];
      }
      final flat = Float32List.view(
          output.buffer, output.offsetInBytes, output.lengthInBytes ~/ 4);
      final boxes = decodeRawYolo(flat, model.outputShape,
          classCount: model.names.length,
          inputSize: model.inputSize,
          minScore: spec.lowestThreshold,
          allowedClasses: model.allowedClasses);
      if (boxes == null) return [];
      final soloClasses = model.soloClasses;
      if (soloClasses != null) {
        // Second look for the labels that must not be out-voted.
        boxes.addAll(decodeRawYolo(flat, model.outputShape,
                classCount: model.names.length,
                inputSize: model.inputSize,
                minScore: spec.lowestThreshold,
                allowedClasses: soloClasses) ??
            const []);
      }
      return labelDetections(boxes,
          spec: spec,
          modelNames: model.names,
          letterbox: Letterbox.fit(sourceWidth, sourceHeight, model.inputSize),
          frameWidth: imageWidth,
          frameHeight: imageHeight,
          // The buffer handed to the models is a downscaled copy of the frame.
          frameScale: imageWidth / sourceWidth);
    } catch (error) {
      debugPrint('[${spec.tag}] unexpected error: $error');
      return [];
    }
  }

  void dispose() {
    _disposed = true;
    for (final model in _models) {
      model.close();
    }
  }
}
