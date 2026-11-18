import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:eyris_app/services/detection_models.dart';
import 'package:eyris_app/services/distance_estimator.dart';
import 'package:eyris_app/services/scene_describer.dart';
import 'package:eyris_app/services/yolo_detection_service.dart';

/// Lays out [rows] (one list of attributes per candidate) the way a model
/// with shape `[1, attributes, candidates]` stores them.
Float32List _attributesFirst(List<List<double>> rows) {
  final candidates = rows.length, attributes = rows.first.length;
  final data = Float32List(candidates * attributes);
  for (var c = 0; c < candidates; c++) {
    for (var a = 0; a < attributes; a++) {
      data[a * candidates + c] = rows[c][a];
    }
  }
  return data;
}

YoloDetection _det(String label, double l, double t, double r, double b,
        [double confidence = .8]) =>
    YoloDetection(
        label: label,
        confidence: confidence,
        boundingBox: Rect.fromLTRB(l, t, r, b));

SceneObject _obj(String label, double l, double t, double r, double b,
        {double? meters}) =>
    SceneObject(
        label: label,
        confidence: .8,
        left: l,
        top: t,
        right: r,
        bottom: b,
        meters: meters);

void main() {
  group('decodeRawYolo', () {
    // [cx, cy, w, h, three class scores] in input pixels, 10 candidates.
    final rows = List.generate(10, (_) => <double>[0, 0, 0, 0, 0, 0, 0]);
    rows[3] = [160, 120, 100, 200, .10, .80, .30];
    rows[7] = [100, 100, 40, 40, .55, .05, .54];
    rows[9] = [50, 50, 10, 10, .04, .01, .02]; // below the floor

    test('reads both tensor layouts', () {
      final a = decodeRawYolo(_attributesFirst(rows), [1, 7, 10],
          classCount: 3, inputSize: 320);
      final b = decodeRawYolo(
          Float32List.fromList(rows.expand((r) => r).toList()), [1, 10, 7],
          classCount: 3, inputSize: 320);
      for (final boxes in [a!, b!]) {
        expect(boxes, hasLength(2));
        expect(boxes[0].classId, 1);
        expect(boxes[0].score, closeTo(.8, 1e-6));
        expect([boxes[0].x1, boxes[0].y1, boxes[0].x2, boxes[0].y2],
            [110, 20, 210, 220]);
        expect(boxes[1].classId, 0);
        expect([boxes[1].x1, boxes[1].y1, boxes[1].x2, boxes[1].y2],
            [80, 80, 120, 120]);
      }
    });

    test('scales boxes given as a fraction of the input', () {
      final boxes = decodeRawYolo(
          _attributesFirst([
            [.5, .5, .25, .5, .9, .1],
            [0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0],
          ]),
          [1, 6, 3],
          classCount: 2,
          inputSize: 320)!;
      expect(boxes.single.x1, closeTo(120, 1e-3));
      expect(boxes.single.y1, closeTo(80, 1e-3));
      expect(boxes.single.x2, closeTo(200, 1e-3));
      expect(boxes.single.y2, closeTo(240, 1e-3));
    });

    test('refuses a model whose class count differs from the labels', () {
      // The labels file lists 20 classes but the tensor has 3: decoding
      // anyway would put the wrong name on every object.
      expect(
          decodeRawYolo(_attributesFirst(rows), [1, 7, 10],
              classCount: 20, inputSize: 320),
          isNull);
      expect(
          decodeRawYolo(Float32List(4), [1, 7, 10],
              classCount: 3, inputSize: 320),
          isNull);
    });

    test('a two-class model is read as scores, not as a ready-made box', () {
      // The pothole model: [cx, cy, w, h, pothole, manhole].
      final boxes = decodeRawYolo(
          _attributesFirst([
            [100, 250, 60, 30, .10, .85],
            [0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0],
          ]),
          [1, 6, 3],
          classCount: 2,
          inputSize: 320)!;
      expect(boxes.single.classId, 1);
      expect(boxes.single.score, closeTo(.85, 1e-6));
      expect(boxes.single.x1, 70);
      expect(boxes.single.y2, 265);
    });
  });

  group('letterbox', () {
    test('keeps the proportions of a tall phone frame', () {
      final box = Letterbox.fit(256, 384, 384);
      expect(box.scale, 1);
      expect([box.width, box.height, box.padX, box.padY], [256, 384, 64, 0]);
      final wide = Letterbox.fit(640, 480, 320);
      expect(wide.scale, .5);
      expect([wide.width, wide.height, wide.padX, wide.padY], [320, 240, 0, 40]);
    });

    test('pads with grey and places the frame in the middle', () {
      // 2x4 frame (tall): left column red, right column blue.
      final rgba = Uint8List(2 * 4 * 4);
      for (var y = 0; y < 4; y++) {
        rgba.setAll((y * 2) * 4, [255, 0, 0, 255]);
        rgba.setAll((y * 2 + 1) * 4, [0, 0, 255, 255]);
      }
      for (final channelsFirst in [true, false]) {
        final t = letterboxToTensor(rgba, 2, 4, 4, channelsFirst);
        double at(int x, int y, int c) =>
            channelsFirst ? t[c * 16 + y * 4 + x] : t[(y * 4 + x) * 3 + c];
        expect(at(0, 0, 0), closeTo(114 / 255, 1e-6)); // padding
        expect(at(3, 3, 2), closeTo(114 / 255, 1e-6));
        expect(at(1, 2, 0), closeTo(1, 1e-6)); // red column
        expect(at(1, 2, 2), closeTo(0, 1e-6));
        expect(at(2, 1, 2), closeTo(1, 1e-6)); // blue column
        expect(at(2, 1, 0), closeTo(0, 1e-6));
      }
    });

    test('boxes come back in frame pixels', () {
      const spec = DetectorSpec(
          tag: 't',
          asset: '',
          labelsAsset: '',
          names: {'door': 'Door', 'table': 'Table'},
          thresholds: {'Door': .30, 'Table': .50});
      // A 480x720 frame handed to the model as a 256x384 copy, letterboxed
      // into 384x384 with 64 px of padding left and right.
      final letterbox = Letterbox.fit(256, 384, 384);
      final found = labelDetections(const [
        RawBox(0, .62, 64 + 64, 96, 64 + 192, 288), // door
        RawBox(1, .40, 100, 100, 200, 200), // table below its threshold
        RawBox(2, .90, 100, 100, 200, 200), // floor: never reported
        RawBox(0, .35, 64 + 66, 98, 64 + 190, 290), // same door again
      ],
          spec: spec,
          modelNames: ['door', 'table', 'floor'],
          letterbox: letterbox,
          frameWidth: 480,
          frameHeight: 720,
          frameScale: 480 / 256);
      expect(found, hasLength(1));
      expect(found.single.label, 'Door');
      expect(found.single.confidence, closeTo(.62, 1e-6));
      expect(found.single.boundingBox, const Rect.fromLTRB(120, 180, 360, 540));
    });
  });

  group('scene rules', () {
    test('drop detections that cannot be what they claim', () {
      final kept = applySceneRules([
        _det('Pothole', 100, 20, 200, 80), // on the ceiling
        _det('Pothole', 100, 600, 200, 660), // on the ground
        _det('Wall', 0, 0, 120, 720), // a strip of side wall
        _det('Wall', 20, 0, 470, 700), // fills the view
        _det('Speed breaker', 200, 500, 260, 700), // taller than wide
        _det('Speed breaker', 0, 380, 480, 720), // the whole road
        _det('Speed breaker', 20, 520, 460, 600),
        _det('Footpath', 0, 100, 480, 300), // up in the air
        _det('Door', 100, 100, 300, 600),
      ], 480, 720);
      expect(kept.map((d) => '${d.label}@${d.boundingBox.top.round()}'),
          ['Pothole@600', 'Wall@0', 'Speed breaker@520', 'Door@100']);
      expect(kept[1].boundingBox.left, 20);
    });

    test('no road hazards in a room with furniture', () {
      final kept = applySceneRules([
        _det('Sofa', 0, 300, 400, 600, .9),
        _det('Pothole', 100, 600, 200, 660),
        _det('Speed breaker', 20, 620, 460, 700),
        _det('Footpath', 0, 500, 480, 720),
      ], 480, 720);
      expect(kept.map((d) => d.label), ['Sofa']);
    });

    test('hazard model boxes are checked by shape only', () {
      YoloDetection hazard(String label, double l, double t, double r, double b) =>
          YoloDetection(
              label: label,
              confidence: .8,
              boundingBox: Rect.fromLTRB(l, t, r, b),
              source: hazardModel.tag);
      final road = applySceneRules([
        hazard('Pothole', 40, 300, 440, 700), // close up, fills the view
        hazard('Speed breaker', 0, 200, 480, 330), // ahead, upper half
        hazard('Speed breaker', 200, 400, 260, 700), // taller than wide
        hazard('Open drain', 60, 250, 420, 520), // any shape, any size
      ], 480, 720);
      expect(road.map((d) => '${d.label}@${d.boundingBox.top.round()}'),
          ['Pothole@300', 'Speed breaker@200', 'Open drain@250']);
      final room = applySceneRules([
        hazard('AC', 300, 100, 420, 600), // a standing unit
        hazard('AC', 0, 100, 480, 200), // wide: a wall unit
        hazard('Pothole', 40, 600, 140, 680), // not next to an AC indoors
        hazard('Open drain', 40, 600, 200, 700), // nor an open drain
      ], 480, 720);
      expect(room.map((d) => '${d.label}@${d.boundingBox.top.round()}'),
          ['AC@100']);
    });

    test('a model is believed alone only when it is confident', () {
      const spec = DetectorSpec(
          tag: 'scene',
          asset: '',
          labelsAsset: '',
          names: {'door': 'Door', 'tree': 'Tree', 'bed': 'Bed'},
          thresholds: {'Door': .60, 'Bed': .50},
          backedThresholds: {'Door': .30, 'Tree': .25});
      expect(spec.thresholdFor('Door'), .60);
      expect(spec.floorFor('Door'), .30);
      // Only a backed confidence: never reported on this model's word alone.
      expect(spec.thresholdFor('Tree'), double.infinity);
      expect(spec.floorFor('Tree'), .25);
      expect(spec.floorFor('Bed'), .50);
      expect(spec.lowestThreshold, .25);

      final found = labelDetections(const [
        RawBox(0, .70, 10, 10, 110, 310), // door, sure
        RawBox(0, .40, 200, 10, 300, 310), // door, needs backing
        RawBox(0, .20, 10, 320, 110, 380), // door, too weak for anything
        RawBox(1, .90, 150, 10, 190, 200), // tree, needs backing however sure
        RawBox(2, .45, 10, 200, 300, 380), // bed below its threshold
      ],
          spec: spec,
          modelNames: ['door', 'tree', 'bed'],
          letterbox: Letterbox.fit(384, 384, 384),
          frameWidth: 384,
          frameHeight: 384);
      expect(
          found.map((d) =>
              '${d.source} ${d.label} ${d.confidence} ${d.needsBacking}'),
          [
            'scene Tree 0.9 true',
            'scene Door 0.7 false',
            'scene Door 0.4 true',
          ]);
    });

    test('a weak open-drain box is kept only to hold back "Path clear"', () {
      const spec = DetectorSpec(
          tag: 'hazard',
          asset: '',
          labelsAsset: '',
          names: {'open drain': 'Open drain', 'pothole': 'Pothole'},
          thresholds: {'Open drain': .73, 'Pothole': .60},
          cautionThresholds: {'Open drain': .35});
      expect(spec.backingFloorFor('Open drain'), .73);
      expect(spec.floorFor('Open drain'), .35);
      expect(spec.floorFor('Pothole'), .60);
      expect(spec.lowestThreshold, .35);
      final found = labelDetections(const [
        RawBox(0, .80, 10, 10, 110, 110), // drain, reported
        RawBox(0, .50, 200, 10, 300, 110), // drain, weak
        RawBox(0, .30, 10, 200, 110, 300), // drain, too weak for anything
        RawBox(1, .50, 200, 200, 300, 300), // pothole below its threshold
      ],
          spec: spec,
          modelNames: ['open drain', 'pothole'],
          letterbox: Letterbox.fit(384, 384, 384),
          frameWidth: 384,
          frameHeight: 384);
      expect(found.map((d) => '${d.label} ${d.confidence} ${d.hint}'),
          ['Open drain 0.8 false', 'Open drain 0.5 true']);
      final frame = combineDetections(found, 384, 384);
      expect(frame.reported.map((d) => d.confidence), [.8]);
      expect(frame.weak.map((d) => d.confidence), [.5]);
      // A weak sighting never backs up another model's unsure box.
      final mixed = combineDetections([
        YoloDetection(
            label: 'Door',
            confidence: .4,
            boundingBox: const Rect.fromLTWH(0, 0, 100, 200),
            source: 'scene',
            needsBacking: true),
        YoloDetection(
            label: 'Door',
            confidence: .2,
            boundingBox: const Rect.fromLTWH(10, 0, 100, 200),
            source: 'world',
            needsBacking: true,
            hint: true),
      ], 480, 720);
      expect(mixed.reported, isEmpty);
    });

    test('an unsure box counts when another model sees the same thing', () {
      YoloDetection box(String source, String label, double left,
              {bool unsure = true}) =>
          YoloDetection(
              label: label,
              confidence: .3,
              boundingBox: Rect.fromLTWH(left, 100, 100, 200),
              source: source,
              needsBacking: unsure);
      final kept = confirmAcrossModels([
        box('scene', 'Door', 0), // backed by world, and backs it
        box('world', 'Door', 20),
        box('scene', 'Tree', 300), // nobody else sees it
        box('scene', 'Chair', 500), // same place, different label
        box('world', 'Table', 500),
        box('scene', 'Bed', 700), // only the same model again
        box('scene', 'Bed', 710),
        box('road', 'Person', 900), // too far from the other person
        box('world', 'Person', 1000),
        box('road', 'Car', 1200, unsure: false), // sure: needs nobody
      ]);
      expect(kept.map((d) => '${d.source} ${d.label}'),
          ['scene Door', 'world Door', 'road Car']);
    });

    test('merging keeps one box per object across models', () {
      final merged = mergeDetections([
        _det('Chair', 10, 10, 110, 210, .5),
        _det('Chair', 12, 12, 112, 212, .7),
        _det('Table', 10, 10, 110, 210, .6),
      ]);
      expect(merged.map((d) => '${d.label} ${d.confidence}'),
          ['Chair 0.7', 'Table 0.6']);
    });
  });

  group('what the user is told', () {
    test('sides', () {
      expect(sideOf(_obj('Chair', 0, 0, 60, 100), 480), Side.farLeft);
      expect(sideOf(_obj('Chair', 90, 0, 190, 100), 480), Side.left);
      expect(sideOf(_obj('Chair', 200, 0, 280, 100), 480), Side.ahead);
      expect(sideOf(_obj('Chair', 300, 0, 380, 100), 480), Side.right);
      expect(sideOf(_obj('Chair', 420, 0, 480, 100), 480), Side.farRight);
      // A wide object across the middle is ahead even if off-centre.
      expect(sideOf(_obj('Table', 0, 0, 320, 100), 480), Side.ahead);
    });

    test('distances', () {
      expect(distancePhrase(null), '');
      expect(distancePhrase(.6), 'less than a meter');
      expect(distancePhrase(1.2), 'about one meter');
      expect(distancePhrase(2.6), 'about 3 meters');
      expect(distancePhrase(12), 'far away');
    });

    test('nearest first, hazards before furniture at the same distance', () {
      final scene = nearestFirst([
        _obj('Sofa', 0, 0, 100, 100, meters: 3.1),
        _obj('Wall', 0, 0, 480, 720),
        _obj('Chair', 200, 0, 280, 100, meters: 1.9),
        _obj('Stairs', 200, 400, 280, 700, meters: 2.2),
      ]);
      expect(scene.map((o) => o.label), ['Stairs', 'Chair', 'Sofa', 'Wall']);
      expect(statusLine(scene),
          '4 objects, Stairs closest · about 2 meters');
      expect(describeLine(scene[2], 480), 'Sofa far left · about 3 meters');
      expect(statusLine(const []), 'Path is clear');
      expect(statusLine([scene[1]]), 'Chair detected · about 2 meters');
    });

    test('speech merges the same thing on the same side', () {
      final scene = nearestFirst([
        _obj('Table', 180, 0, 300, 100, meters: .7),
        _obj('Table', 200, 0, 280, 100, meters: .8),
        _obj('Door', 400, 0, 470, 300, meters: 3),
        _obj('Person', 0, 0, 40, 300, meters: 5),
      ]);
      expect(spokenSummary(scene, 480),
          'Caution. Two tables straight ahead, less than a meter. '
          'Door far right, about 3 meters.');
      expect(spokenSummary([_obj('Speed breaker', 40, 500, 440, 560, meters: 2)], 480),
          'Speed breaker straight ahead, about 2 meters.');
      expect(spokenSummary([_obj('Wall', 0, 0, 480, 720)], 480),
          'Wall straight ahead.');
    });

    test('an open drain is always spoken with a caution', () {
      expect(
          spokenSummary(
              [_obj('Open drain', 150, 450, 330, 600, meters: 3)], 480),
          'Caution. Open drain straight ahead, about 3 meters.');
      expect(
          spokenSummary([
            _obj('Person', 200, 0, 280, 300, meters: 2),
            _obj('Open drain', 0, 450, 100, 600, meters: 3),
          ], 480),
          'Person straight ahead, about 2 meters. '
          'Caution. Open drain far left, about 3 meters.');
      // One caution is enough for one sentence.
      expect(
          spokenSummary([
            _obj('Chair', 200, 0, 280, 300, meters: .6),
            _obj('Open drain', 0, 450, 100, 600, meters: 3),
          ], 480),
          'Caution. Chair straight ahead, less than a meter. '
          'Open drain far left, about 3 meters.');
      // At the same distance the drain is named before furniture.
      final scene = nearestFirst([
        _obj('Chair', 200, 0, 280, 300, meters: 2.1),
        _obj('Open drain', 150, 450, 330, 600, meters: 2.2),
      ]);
      expect(scene.map((o) => o.label), ['Open drain', 'Chair']);
      expect(isDropHazard('Open drain'), isTrue);
      expect(isDropHazard('Pothole'), isFalse);
    });

    test('a scene is only repeated when it changes', () {
      final a = [_obj('Door', 200, 0, 280, 300, meters: 3.0)];
      final b = [_obj('Door', 205, 0, 285, 300, meters: 3.2)];
      final c = [_obj('Door', 205, 0, 285, 300, meters: 1.2)];
      expect(sceneKey(a, 480), sceneKey(b, 480));
      expect(sceneKey(a, 480), isNot(sceneKey(c, 480)));
    });
  });

  group('camera distance', () {
    const estimator = DistanceEstimator();
    test('a door seen whole is ranged by its height', () {
      // 2 m door, 480x720 frame (focal ~518 px), box 345 px tall -> ~3 m.
      final range = estimator.estimate(
          label: 'Door',
          left: 180,
          top: 150,
          right: 300,
          bottom: 495,
          frameWidth: 480,
          frameHeight: 720)!;
      expect(range.meters, closeTo(3.0, .1));
      expect(range.approximate, isFalse);
    });

    test('ground hazards are ranged from where they meet the ground', () {
      final far = estimator.estimate(
          label: 'Speed breaker',
          left: 40,
          top: 430,
          right: 440,
          bottom: 470,
          frameWidth: 480,
          frameHeight: 720)!;
      final near = estimator.estimate(
          label: 'Speed breaker',
          left: 40,
          top: 600,
          right: 440,
          bottom: 690,
          frameWidth: 480,
          frameHeight: 720)!;
      expect(far.meters, greaterThan(near.meters));
      expect(near.meters, closeTo(1.9, .2));
      // Running off the bottom of the frame: right at the user's feet.
      final here = estimator.estimate(
          label: 'Footpath',
          left: 0,
          top: 400,
          right: 480,
          bottom: 720,
          frameWidth: 480,
          frameHeight: 720)!;
      expect(here.meters, lessThan(near.meters));
    });

    test('an open drain is ranged from its near edge, never by the sensor', () {
      final drain = estimator.estimate(
          label: 'Open drain',
          left: 100,
          top: 560,
          right: 380,
          bottom: 690,
          frameWidth: 480,
          frameHeight: 720)!;
      expect(drain.meters, closeTo(1.9, .2));
      expect(drain.method, CameraRangeMethod.groundPlane);
      // The ultrasonic beam passes over flat ground hazards.
      expect(DistanceEstimator.belowSensor,
          containsAll(['pothole', 'speed breaker', 'open drain']));
      expect(DistanceEstimator.belowSensor, isNot(contains('stairs')));
    });
  });

  for (final model in ['scene', 'hazard']) {
  test('decodes real $model-model output like the Python reference', () {
    // Written by training/export_scene.py: the TFLite model's raw output for
    // one validation photo and the detections an independent decoder finds.
    final meta = jsonDecode(
            File('test/fixtures/${model}_model_output.json').readAsStringSync())
        as Map<String, dynamic>;
    final bytes =
        File('test/fixtures/${model}_model_output.f32').readAsBytesSync();
    final data = Float32List.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
    final labels = (meta['labels'] as List).cast<String>();
    final shape = (meta['shape'] as List).cast<int>();
    final inputSize = meta['inputSize'] as int;
    final width = meta['sourceWidth'] as int;
    final height = meta['sourceHeight'] as int;
    final spec = DetectorSpec(
        tag: 'fixture',
        asset: '',
        labelsAsset: '',
        names: {for (final name in labels) name: name},
        thresholds: const {},
        defaultThreshold: (meta['threshold'] as num).toDouble());

    final boxes = decodeRawYolo(data, shape,
        classCount: labels.length, inputSize: inputSize)!;
    final found = labelDetections(boxes,
        spec: spec,
        modelNames: labels,
        letterbox: Letterbox.fit(width, height, inputSize),
        frameWidth: width,
        frameHeight: height);
    final expected = (meta['expected'] as List).cast<Map<String, dynamic>>();
    expect(found.map((d) => d.label), expected.map((e) => e['label']));
    for (var i = 0; i < expected.length; i++) {
      final box = (expected[i]['box'] as List).cast<num>();
      expect(found[i].confidence,
          closeTo((expected[i]['confidence'] as num).toDouble(), 1e-4));
      expect(found[i].boundingBox.left, closeTo(box[0], .6));
      expect(found[i].boundingBox.top, closeTo(box[1], .6));
      expect(found[i].boundingBox.right, closeTo(box[2], .6));
      expect(found[i].boundingBox.bottom, closeTo(box[3], .6));
    }
    expect(expected, isNotEmpty);
  });
  }

  group('bundled models', () {
    test('every model name the app uses exists in that model', () {
      for (final spec in detectorSpecs) {
        final file = File(spec.labelsAsset);
        expect(file.existsSync(), isTrue, reason: '${spec.labelsAsset} missing');
        final names = file
            .readAsLinesSync()
            .map((l) => l.trim().toLowerCase())
            .where((l) => l.isNotEmpty)
            .toList();
        expect(names.toSet(), hasLength(names.length),
            reason: 'duplicate names in ${spec.labelsAsset}');
        for (final entry in spec.names.entries) {
          expect(names, contains(entry.key),
              reason: '${spec.tag}: "${entry.key}" is not a class of the model');
          expect(allLabels, contains(entry.value));
        }
        for (final label in [
          ...spec.thresholds.keys,
          ...spec.backedThresholds.keys
        ]) {
          expect(spec.names.values, contains(label),
              reason: '${spec.tag}: threshold for unused label $label');
        }
        for (final label in spec.names.values) {
          expect(
              spec.thresholds.containsKey(label) ||
                  spec.backedThresholds.containsKey(label),
              isTrue,
              reason: '${spec.tag}: no measured threshold for $label');
        }
        for (final entry in spec.backedThresholds.entries) {
          expect(entry.value, lessThan(spec.thresholdFor(entry.key)),
              reason: '${spec.tag}: backed confidence for ${entry.key} must '
                  'be the lower one');
        }
        for (final entry in spec.cautionThresholds.entries) {
          expect(spec.names.values, contains(entry.key),
              reason: '${spec.tag}: caution for unused label ${entry.key}');
          expect(entry.value, lessThan(spec.backingFloorFor(entry.key)),
              reason: '${spec.tag}: caution for ${entry.key} must be the '
                  'lowest confidence');
        }
        expect(File(spec.asset).existsSync(), isTrue,
            reason: '${spec.asset} missing');
      }
    });

    test('every label is produced by some model', () {
      final produced = {
        for (final spec in detectorSpecs) ...spec.names.values,
      };
      expect(produced, containsAll(allLabels));
    });
  });
}
