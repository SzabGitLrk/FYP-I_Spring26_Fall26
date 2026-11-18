import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eyris_app/services/camera_settings.dart';
import 'package:eyris_app/services/mjpeg_stream.dart';
import 'package:eyris_app/services/speech_hub.dart';
import 'package:eyris_app/services/yolo_detection_service.dart';
import 'package:eyris_app/services/camera_route_observer.dart';
import 'package:eyris_app/services/camera_adjustments.dart';
import 'package:eyris_app/screens/camera_screen.dart';
import 'package:eyris_app/widgets/camera_settings_dialog.dart';
import 'package:eyris_app/widgets/camera_adjustments_sheet.dart';

const testStreamAddress = 'http://10.105.21.204:81/stream';

class CameraClient extends http.BaseClient {
  final chunks = StreamController<List<int>>();
  int status = 200;
  String contentType = 'multipart/x-mixed-replace; boundary=camera';
  bool closed = false;
  Uri? requested;
  Completer<http.StreamedResponse>? pending;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested = request.url;
    return pending?.future ??
        http.StreamedResponse(chunks.stream, status,
            headers: {'content-type': contentType});
  }

  @override
  void close() {
    closed = true;
  }
}

class TestDetector extends YoloDetectionService {
  int frames = 0;
  @override
  bool get isLoaded => true;
  @override
  Future<void> loadModel() async {}
  @override
  Future<List<YoloDetection>> detectImage(Uint8List bytes, int width,
      int height,
      {Uint8List? rgbaInput, int? rgbaWidth, int? rgbaHeight}) async {
    frames++;
    expect(width, 16);
    expect(height, 12);
    return [];
  }

  @override
  void dispose() {}
}

class FixedDetector extends YoloDetectionService {
  FixedDetector(this.result);
  final List<YoloDetection> result;
  int frames = 0;
  @override
  bool get isLoaded => true;
  @override
  Future<void> loadModel() async {}
  @override
  Future<List<YoloDetection>> detectImage(Uint8List bytes, int width,
      int height,
      {Uint8List? rgbaInput, int? rgbaWidth, int? rgbaHeight}) async {
    frames++;
    return result;
  }

  @override
  void dispose() {}
}

/// Names nothing, but has a weak open-drain sighting in every frame.
class WeakDrainDetector extends FixedDetector {
  WeakDrainDetector() : super(const []);
  @override
  List<YoloDetection> get weakSightings => [
        YoloDetection(
            label: 'Open drain',
            confidence: .5,
            boundingBox: const Rect.fromLTRB(100, 400, 380, 600),
            source: 'hazard',
            hint: true),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final spoken = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SpeechHub.instance.resetForTest();
    spoken.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return 1;
    });
  });

  test('normalizes hotspot IP and retains explicit stream path and port',
      () async {
    expect(CameraSettings.parseAddress('10.105.21.204').toString(),
        testStreamAddress);
    expect(CameraSettings.parseAddress('http://10.0.0.2').toString(),
        'http://10.0.0.2:81/stream');
    expect(
        CameraSettings.parseAddress('http://camera.local:82/live').toString(),
        'http://camera.local:82/live');
    for (final invalid in [
      '',
      'ftp://camera/stream',
      'http://',
      'not an ip',
      'http://camera:99999/stream'
    ]) {
      expect(() => CameraSettings.parseAddress(invalid), throwsFormatException);
    }
    final settings = CameraSettings(
        streamUri: CameraSettings.parseAddress('10.0.0.9'),
        usePhoneCamera: true);
    await settings.save();
    final restored = await CameraSettings.load();
    expect(restored.streamUri, settings.streamUri);
    expect(restored.usePhoneCamera, isTrue);
    expect(restored.statusUri.toString(), 'http://10.0.0.9/status');
    expect(CameraSettings.streamUriForIp('192.168.43.204').toString(),
        'http://192.168.43.204:81/stream');
    for (final invalidIp in [
      '192.168.43',
      '192.168.43.256',
      'abc.1.2.3',
      '192.168. 1.1'
    ]) {
      expect(() => CameraSettings.streamUriForIp(invalidIp),
          throwsFormatException);
    }
  });

  test('camera adjustments persist, reset, and provide visual matrices',
      () async {
    const defaults = CameraAdjustments();
    expect(defaults.colorMatrix, hasLength(20));
    final changed = defaults.copyWith(
        brightness: .5,
        contrast: .25,
        saturation: -.5,
        filter: CameraFilter.sepia);
    expect(changed.colorMatrix, isNot(defaults.colorMatrix));
    await changed.save();
    final restored = await CameraAdjustments.load();
    expect(restored.brightness, .5);
    expect(restored.contrast, .25);
    expect(restored.saturation, -.5);
    expect(restored.filter, CameraFilter.sepia);
  });

  test('parses multipart frames split at every possible chunk boundary', () {
    final jpeg = img.encodeJpg(img.Image(width: 16, height: 12));
    final data = [
      ...ascii.encode('--camera\r\nContent-Type: image/jpeg\r\n\r\n'),
      ...jpeg,
      ...ascii.encode('\r\n--camera\r\n\r\n'),
      ...jpeg
    ];
    for (var split = 0; split <= data.length; split++) {
      final parser = JpegFrameParser(maxFrameBytes: jpeg.length + 4);
      final frames = [
        ...parser.add(data.sublist(0, split)),
        ...parser.add(data.sublist(split))
      ];
      expect(frames, [jpeg, jpeg]);
    }
    final parser = JpegFrameParser(maxFrameBytes: 5);
    expect(() => parser.add([255, 216, 0, 0, 0, 0]).toList(),
        throwsFormatException);
  });

  test('stream emits frames and cancels its subscription on close', () async {
    final client = CameraClient();
    final service = MjpegStream(client: client);
    final frames = <Uint8List>[];
    final errors = <Object>[];
    await service.start(Uri.parse(testStreamAddress),
        onFrame: frames.add, onError: errors.add);
    client.chunks.add([255, 216, 1, 255, 217]);
    // Frames are parsed on a background isolate, so they arrive a moment later.
    for (var i = 0; i < 100 && frames.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(frames.single, [255, 216, 1, 255, 217]);
    service.close();
    expect(client.closed, isTrue);
    expect(client.chunks.hasListener, isFalse);
    client.chunks.add([255, 216, 2, 255, 217]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(frames.length, 1);
    expect(errors, isEmpty);
    await client.chunks.close();
  });

  test('rejects HTTP errors and non-MJPEG pages', () async {
    for (final status in [404, 200]) {
      final client = CameraClient()
        ..status = status
        ..contentType = 'text/html';
      final errors = <Object>[];
      await MjpegStream(client: client).start(
          Uri.parse(testStreamAddress),
          onFrame: (_) => fail('Unexpected frame'),
          onError: errors.add);
      expect(errors, hasLength(1));
      expect(client.closed, isTrue);
    }
  });

  test('times out when headers or complete JPEG frames never arrive', () async {
    final headersClient = CameraClient()
      ..pending = Completer<http.StreamedResponse>();
    final errors = <Object>[];
    await MjpegStream(
            client: headersClient,
            connectionTimeout: const Duration(milliseconds: 20))
        .start(Uri.parse(testStreamAddress),
            onFrame: (_) {}, onError: errors.add);
    expect(errors.single, isA<TimeoutException>());
    expect(headersClient.closed, isTrue);
    final client = CameraClient();
    final timedOut = Completer<Object>();
    await MjpegStream(
            client: client, frameTimeout: const Duration(milliseconds: 20))
        .start(Uri.parse(testStreamAddress),
            onFrame: (_) {}, onError: timedOut.complete);
    client.chunks.add(ascii.encode('--camera\r\n'));
    expect(await timedOut.future, isA<TimeoutException>());
    expect(client.closed, isTrue);
    await client.chunks.close();
  });

  test('disconnect is reported once and closes the HTTP client', () async {
    final client = CameraClient();
    final errors = <Object>[];
    await MjpegStream(client: client).start(
        Uri.parse(testStreamAddress),
        onFrame: (_) {},
        onError: errors.add);
    await client.chunks.close();
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    expect(client.closed, isTrue);
  });

  testWidgets('settings dialog persists a changed hotspot address',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showCameraSettings(context),
                    child: const Text('Settings'))))));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10.0.0.7');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect((await CameraSettings.load()).streamUri.toString(),
        'http://10.0.0.7:81/stream');
  });

  testWidgets('camera adjustment sheet resets and applies a filter',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showCameraAdjustments(
                        context,
                        const CameraAdjustments(
                            brightness: .5, filter: CameraFilter.warm)),
                    child: const Text('Adjust'))))));
    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    expect(find.text('Brightness  0.5'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.tap(find.text('High Contrast'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'camera renders a JPEG, detects it, pauses and reconnects on resume',
      (tester) async {
    SharedPreferences.setMockInitialValues({'camera_ip': '10.105.21.204'});
    final clients = <CameraClient>[];
    final detector = TestDetector();
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [cameraRouteObserver],
        home: CameraScreen(
            detectionService: detector,
            streamFactory: () {
              final client = CameraClient();
              clients.add(client);
              return MjpegStream(client: client);
            })));
    // Settings, permissions, the frame parser and the decoder all complete
    // on real asynchronous work, so give them time until [done] holds.
    Future<void> settle(bool Function() done, {void Function()? each}) async {
      for (var i = 0; i < 120 && !done(); i++) {
        each?.call();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.pump();
    expect(find.text('Connecting to camera...'), findsOneWidget);
    await settle(() => clients.isNotEmpty && clients.single.requested != null);
    expect(clients.single.requested.toString(), testStreamAddress);
    // Detection samples the stream (not every frame, and not the first
    // ones after start-up), so keep frames coming until one is analysed.
    final jpeg = img.encodeJpg(img.Image(width: 16, height: 12));
    await settle(() => detector.frames > 0,
        each: () => clients.single.chunks.add(jpeg));
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(detector.frames, greaterThan(0));
    // No sensor packets yet: the app must not claim the path is clear.
    expect(find.text('Path is clear'), findsNothing);
    expect(find.text('Waiting for sensor distance data'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(clients.first.closed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await settle(() => clients.length == 2);
    expect(clients, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(clients.last.closed, isTrue);
    for (final client in clients) {
      unawaited(client.chunks.close());
    }
  });

  testWidgets('camera tells where each object is and how far',
      (tester) async {
    SharedPreferences.setMockInitialValues({'camera_ip': '10.105.21.204'});
    final client = CameraClient();
    // 480x640 frame: a door straight ahead and a chair at the far left.
    final detector = FixedDetector([
      YoloDetection(
          label: 'Door',
          confidence: .8,
          boundingBox: const Rect.fromLTRB(180, 100, 300, 560)),
      YoloDetection(
          label: 'Chair',
          confidence: .7,
          boundingBox: const Rect.fromLTRB(10, 400, 100, 600)),
    ]);
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [cameraRouteObserver],
        home: CameraScreen(
            detectionService: detector,
            streamFactory: () => MjpegStream(client: client))));
    // Grey, not black: a black frame is too dark to look at (next test).
    final jpeg = img.encodeJpg(
        img.Image(width: 480, height: 640)..clear(img.ColorRgb8(128, 128, 128)));
    for (var i = 0; i < 160 && (detector.frames == 0 || spoken.isEmpty); i++) {
      if (client.requested != null) client.chunks.add(jpeg);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(detector.frames, greaterThan(0));
    for (var i = 0;
        i < 40 && find.textContaining('Door closest').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('2 objects, Door closest \u00B7 about 3 meters'),
        findsOneWidget);
    expect(find.text('Door straight ahead \u00B7 about 3 meters'),
        findsOneWidget);
    expect(find.text('Chair far left \u00B7 about 3 meters'), findsOneWidget);
    expect(
        spoken,
        contains('Door straight ahead, about 3 meters. '
            'Chair far left, about 3 meters.'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    unawaited(client.chunks.close());
  });

  testWidgets('a black frame is not looked at, and the path is not clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({'camera_ip': '10.105.21.204'});
    final client = CameraClient();
    // In black ESP32 frames the models made up a person and a wall.
    final detector = FixedDetector([
      YoloDetection(
          label: 'Person',
          confidence: .64,
          boundingBox: const Rect.fromLTRB(100, 200, 250, 600)),
    ]);
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [cameraRouteObserver],
        home: CameraScreen(
            detectionService: detector,
            streamFactory: () => MjpegStream(client: client))));
    final jpeg = img.encodeJpg(img.Image(width: 480, height: 640));
    for (var i = 0;
        i < 160 && find.text('Too dark to see, move slowly').evaluate().isEmpty;
        i++) {
      if (client.requested != null) client.chunks.add(jpeg);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Too dark to see, move slowly'), findsOneWidget);
    expect(find.text('Too dark to see · move slowly'), findsOneWidget);
    expect(detector.frames, 0);
    expect(find.textContaining('Person'), findsNothing);
    expect(find.text('Path clear'), findsNothing);
    expect(spoken, contains('Too dark to see, move slowly.'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    unawaited(client.chunks.close());
  });

  testWidgets('a weak open-drain sighting keeps the path from being clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({'camera_ip': '10.105.21.204'});
    final client = CameraClient();
    final detector = WeakDrainDetector();
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [cameraRouteObserver],
        home: CameraScreen(
            detectionService: detector,
            streamFactory: () => MjpegStream(client: client))));
    // A detailed view: with nothing named in it the app says "Path clear".
    final random = math.Random(1);
    final frame = img.Image(width: 480, height: 640);
    for (final pixel in frame) {
      final v = random.nextInt(256);
      pixel
        ..r = v
        ..g = v
        ..b = v;
    }
    final jpeg = img.encodeJpg(frame);
    for (var i = 0;
        i < 160 && !spoken.contains('Path unclear ahead, move slowly.');
        i++) {
      if (client.requested != null) client.chunks.add(jpeg);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    // The sentence can arrive in the same microtask flush as the state
    // change, after this pump's frame: draw one more.
    await tester.pump();
    expect(spoken, contains('Path unclear ahead, move slowly.'));
    expect(spoken, isNot(contains('Path clear')));
    expect(find.text('Path unclear · move slowly'), findsOneWidget);
    expect(find.text('Path clear'), findsNothing);
    expect(find.textContaining('Open drain'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    unawaited(client.chunks.close());
  });
}