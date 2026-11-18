import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import '../services/speech_hub.dart';
import '../services/yolo_detection_service.dart';
import '../services/distance_estimator.dart';
import '../services/scene_describer.dart';
import '../services/alert_service.dart';
import '../services/camera_settings.dart';
import '../services/camera_adjustments.dart';
import '../services/camera_route_observer.dart';
import '../services/mjpeg_stream.dart';
import '../services/sensor_telemetry_service.dart';
import '../widgets/camera_settings_dialog.dart';
import '../widgets/camera_adjustments_sheet.dart';
import 'home_screen.dart';

Uint8List _decodeJpegToPng(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) throw const FormatException('Invalid JPEG frame.');
  return Uint8List.fromList(img.encodePng(decoded));
}

List<int> _readJpegSize(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) throw const FormatException('Invalid JPEG frame.');
  return [decoded.width, decoded.height];
}

/// A camera frame decoded for the models: RGBA pixels of a downscaled copy
/// ([width] x [height], same proportions as the frame) plus the size of the
/// frame itself.
class _DecodedFrame {
  const _DecodedFrame(this.rgba, this.width, this.height, this.frameWidth,
      this.frameHeight);
  final Uint8List rgba;
  final int width;
  final int height;
  final int frameWidth;
  final int frameHeight;
}

/// Native (Skia) JPEG decode in ONE pass, downscaled so the long side is
/// [target] pixels (the largest model input). The frame keeps its
/// proportions: the models were trained on undistorted photos, and
/// stretching a tall phone frame into a square makes doors look like tables.
/// Returns null if the frame is unusable.
Future<_DecodedFrame?> _decodeFrame(Uint8List jpegBytes, int target) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    final buf = await ui.ImmutableBuffer.fromUint8List(jpegBytes);
    buffer = buf;
    descriptor = await ui.ImageDescriptor.encoded(buf);
    final encodedWidth = descriptor.width;
    final encodedHeight = descriptor.height;
    if (encodedWidth <= 0 || encodedHeight <= 0) return null;
    final longSide =
        encodedWidth > encodedHeight ? encodedWidth : encodedHeight;
    final scale = longSide > target ? target / longSide : 1.0;
    codec = await descriptor.instantiateCodec(
        targetWidth: (encodedWidth * scale).round().clamp(1, encodedWidth),
        targetHeight: (encodedHeight * scale).round().clamp(1, encodedHeight));
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    if (data == null || data.lengthInBytes != width * height * 4) return null;
    final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // The decoder turns a rotated (EXIF) photo upright, so take the frame's
    // real proportions from the decoded pixels.
    final upright = (width >= height) == (encodedWidth >= encodedHeight);
    return _DecodedFrame(rgba, width, height,
        upright ? encodedWidth : encodedHeight,
        upright ? encodedHeight : encodedWidth);
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// YUV420_888 CameraImage planes -> RGBA scaled to [target] x [target] in a
/// single pass (bilinear luma, nearest chroma; BT.601 full range, identical
/// coefficients to the old converter). Replaces the YUV -> JPEG (Dart encode)
/// -> JPEG decode -> resize round trip that cost several hundred ms per frame.
Uint8List? _yuvToRgba(Map<String, dynamic> p) {
  final y = p['y'] as Uint8List;
  final u = p['u'] as Uint8List;
  final v = p['v'] as Uint8List;
  final sw = p['width'] as int;
  final sh = p['height'] as int;
  final tw = p['targetWidth'] as int;
  final th = p['targetHeight'] as int;
  final rowStrideY = p['rowStrideY'] as int;
  final rowStrideU = p['rowStrideU'] as int;
  final rowStrideV = p['rowStrideV'] as int;
  final pixelStrideU = p['pixelStrideU'] as int;
  final pixelStrideV = p['pixelStrideV'] as int;
  if (sw < 2 || sh < 2 || tw < 1 || th < 1) return null;
  final out = Uint8List(tw * th * 4);
  final xRatio = sw / tw;
  final yRatio = sh / th;
  for (var ty = 0; ty < th; ty++) {
    final fy = (ty + 0.5) * yRatio - 0.5;
    var y0 = fy.floor();
    if (y0 < 0) y0 = 0;
    if (y0 > sh - 1) y0 = sh - 1;
    var y1 = y0 + 1;
    if (y1 > sh - 1) y1 = sh - 1;
    final dy = (fy - y0).clamp(0.0, 1.0);
    final yRow0 = y0 * rowStrideY;
    final yRow1 = y1 * rowStrideY;
    final uRow = (y0 >> 1) * rowStrideU;
    final vRow = (y0 >> 1) * rowStrideV;
    for (var tx = 0; tx < tw; tx++) {
      final fx = (tx + 0.5) * xRatio - 0.5;
      var x0 = fx.floor();
      if (x0 < 0) x0 = 0;
      if (x0 > sw - 1) x0 = sw - 1;
      var x1 = x0 + 1;
      if (x1 > sw - 1) x1 = sw - 1;
      final dx = (fx - x0).clamp(0.0, 1.0);
      final yTop = y[yRow0 + x0];
      final yTop1 = y[yRow0 + x1];
      final yBot = y[yRow1 + x0];
      final yBot1 = y[yRow1 + x1];
      final top = yTop + (yTop1 - yTop) * dx;
      final bottom = yBot + (yBot1 - yBot) * dx;
      final luma = top + (bottom - top) * dy;
      final uu = u[uRow + ((x0 >> 1) * pixelStrideU)] - 128;
      final vv = v[vRow + ((x0 >> 1) * pixelStrideV)] - 128;
      final r = (luma + 1.402 * vv).clamp(0, 255).toInt();
      final g = (luma - 0.344136 * uu - 0.714136 * vv).clamp(0, 255).toInt();
      final b = (luma + 1.772 * uu).clamp(0, 255).toInt();
      final o = (ty * tw + tx) * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = 255;
    }
  }
  return out;
}

/// Uniformity of a frame: low variance = blank wall/door close-up.
/// Runs in compute isolate; 32x32 grayscale is enough and cheap.
double _frameUniformityVariance(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return double.infinity;
  final small = img.copyResize(decoded, width: 32, height: 32);
  final gray = img.grayscale(small);
  final bytes = gray.getBytes();
  double mean = 0;
  for (final b in bytes) {
    mean += b;
  }
  mean /= bytes.length;
  double variance = 0;
  for (final b in bytes) {
    final d = b - mean;
    variance += d * d;
  }
  return variance / bytes.length;
}

/// True when an RGBA frame is too dark to see anything in: dim on average
/// and with almost nothing bright in it. In such frames the models only
/// make things up (a person and a wall in a black ESP32 frame were seen).
/// Measured on the client's ESP32 video: dark frames had a mean of 23-45
/// with at most 5% of pixels above 90; usable dim rooms a mean of 90+.
const double _darkMeanLuma = 50;

bool _rgbaTooDark(Uint8List? rgba) {
  if (rgba == null || rgba.length < 4096) return false;
  final pixels = rgba.length ~/ 4;
  final step = pixels >= 1024 ? pixels ~/ 1024 : 1;
  var count = 0, bright = 0;
  var sum = 0.0;
  for (var i = 0; i < pixels; i += step) {
    final o = i * 4;
    final luma = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
    sum += luma;
    if (luma > 90) bright++;
    count++;
  }
  return count > 0 && sum / count < _darkMeanLuma && bright < count * 0.05;
}

/// Same uniformity measure for an RGBA buffer (stream frames have no JPEG).
double _rgbaUniformityVariance(Uint8List? rgba) {
  if (rgba == null || rgba.length < 4096) return double.infinity;
  final pixels = rgba.length ~/ 4;
  final step = pixels >= 1024 ? pixels ~/ 1024 : 1;
  var count = 0;
  var mean = 0.0;
  final lumas = <double>[];
  for (var i = 0; i < pixels; i += step) {
    final o = i * 4;
    final luma = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
    lumas.add(luma);
    mean += luma;
    count++;
  }
  if (count == 0) return double.infinity;
  mean /= count;
  var variance = 0.0;
  for (final luma in lumas) {
    final d = luma - mean;
    variance += d * d;
  }
  return variance / count;
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.streamFactory, this.detectionService});
  final MjpegStream Function()? streamFactory;
  final YoloDetectionService? detectionService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, RouteAware {
  CameraSettings? _settings;
  MjpegStream? _stream;
  ui.Image? _streamImage;
  Size _frameSize = Size.zero;
  String? _connectionError;
  String? _modelError;
  bool _connecting = true;
  bool _active = true;
  bool _routeVisible = true;
  bool _editing = false;
  int _generation = 0;
  DateTime _lastDetection = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _phoneClosing;
  CameraAdjustments _adjustments = const CameraAdjustments();
  CameraController? _controller;
  late final YoloDetectionService _detectionService;
  final AlertService _alertService = AlertService();
  final SpeechHub _speech = SpeechHub.instance;
  bool _detectionTtsReady = false;
  // What was last spoken (objects, sides and rough distances), so the same
  // scene is not repeated on every frame.
  String? _lastSceneKey;
  DateTime _lastDetectionAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPathClearAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastVisibleDetectionAt;
  // Keep the last valid sensor sample visible across brief packet gaps.
  static const Duration _telemetryMaxAge = Duration(seconds: 3);
  // Long enough for a sentence to finish before the next one starts.
  static const Duration _announcementCooldown = Duration(milliseconds: 2500);
  static const Duration _repeatSameScene = Duration(seconds: 8);
  static const Duration _pathClearCooldown = Duration(seconds: 6);
  final SensorTelemetryService _telemetryService = SensorTelemetryService();
  StreamSubscription<SensorTelemetry>? _telemetrySubscription;
  Timer? _telemetryRetryTimer;
  bool _telemetryStartInFlight = false;
  Timer? _telemetryFreshnessTimer;
  Timer? _telemetryUiTimer;
  Timer? _distancePollTimer;
  SensorTelemetry? _telemetry;
  final http.Client _distanceHttpClient = http.Client();
  bool _distancePollInFlight = false;
  DateTime _lastDistancePollDiagnostic = DateTime.fromMillisecondsSinceEpoch(0);
  Uri? _distanceEndpoint;
  bool _closeDistanceBeepActive = false;
  // An open drain was in view: beep once when it appears, and do not call
  // the path clear for a while after, since a missed frame or a turn of the
  // head is not proof that it is gone.
  DateTime? _lastDropHazardAt;
  bool _dropHazardBeepActive = false;
  static const Duration _dropHazardMemory = Duration(seconds: 4);
  // A weak open-drain sighting (not named) in 2 of the last 3 analysed
  // frames also holds back "Path clear".
  DateTime? _lastWeakDropAt;
  final List<bool> _recentWeakDrop = [];
  static const MethodChannel _beepChannel =
  MethodChannel('com.example.eyris_app/warning_beep');
  static const double _visionCloseMeters = 1.5;
  static const double _visionClearMeters = 1.8;
  static const double _wallBlockedMeters = 0.8;
  int _emptyStreak = 0;
  bool _uniformWallActive = false;
  // Nothing recognised, but the view is a plain surface with little detail:
  // too close to something to say the path is clear.
  bool _pathUnclear = false;
  // The ESP32 camera gives flatter, lower-contrast frames than a phone: a
  // heap of clothes in a dim room measured as "uniform" and was called a
  // wall. It needs a plainer view to say "Wall"; between the two limits it
  // says "Path unclear" (never "Path clear", so the unclear limit stays).
  double get _uniformWallVariance => _isEspCamera ? 300 : 500;
  DateTime _lastUnclearAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _unclearCooldown = Duration(seconds: 6);
  static const double _unclearPathVariance = 2000;
  // The last frame was too dark to see anything in.
  bool _tooDark = false;
  DateTime _lastDarkAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _darkCooldown = Duration(seconds: 8);

  List<YoloDetection> _detections = [];
  // Rolling per-frame label sets (last 3). A label needs 2-of-3 sightings
  // before it shows/announces, so a one-frame hallucination never speaks.
  final List<List<String>> _recentLabelHistory = [];
  bool _isModelLoaded = false;
  bool _flashOn = false;
  bool _isDetecting = false;
  Timer? _detectionTimer;
  Timer? _streamWatchdog;
  bool _streaming = false;
  DateTime _lastStreamFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _streamFailures = 0;
  // Stream capture is primary: takePicture() runs a full AF/AE precapture
  // sequence before every shutter (STATE_WAITING_PRECAPTURE_* in logcat) and
  // swung 250ms -> 3.1s with "Metering timeout" once inference loaded the
  // CPU. Image-stream frames are already in memory: no shutter, no
  // precapture, no JPEG. takePicture remains as the watchdog fallback below.
  static const bool _streamCaptureEnabled = false;
  // Warmup: the first frames after camera start are torn/partial and crash
  // the TFLite reshape node (0-element buffers). Discard first 3 silently.
  int _warmupSkips = 3;

  // Track last saved alert to avoid duplicate saves
  String _lastSavedAlert = "";
  DateTime _lastSavedTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _detectionService = widget.detectionService ?? YoloDetectionService();
    WidgetsBinding.instance.addObserver(this);
    _initializeDetectionTts();
    _startTelemetry();
    _loadModel();
    _loadAdjustments();
    _startCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) cameraRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _pauseCamera();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _resumeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      _resumeCamera();
    } else {
      _pauseCamera();
    }
  }

  void _pauseCamera() {
    _stopCamera();
    unawaited(_speech.stopDetection());
    if (mounted) {
      setState(() {
        _connecting = true;
        _detections = [];
      });
    }
  }

  void _resumeCamera() {
    if (mounted && _active && _routeVisible && !_editing) _startCamera();
  }

  void _stopCamera() {
    _generation++;
    _warmupSkips = 3;
    _streamFailures = 0;
    _streaming = false;
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    _distancePollTimer?.cancel();
    _distancePollTimer = null;
    _distanceEndpoint = null;
    _stream?.close();
    _stream = null;
    _detectionTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) _phoneClosing = controller.dispose();
    final image = _streamImage;
    _streamImage = null;
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
    _flashOn = false;
  }

  Future<void> _editSettings() async {
    _editing = true;
    _pauseCamera();
    await showCameraSettings(context);
    _editing = false;
    _resumeCamera();
  }

  Future<void> _startTelemetry() async {
    _telemetrySubscription = _telemetryService.stream.listen((reading) {
      if (!mounted) return;
      _telemetry = reading;
      if (reading.distanceMeters < 0.50 && !_closeDistanceBeepActive) {
        _closeDistanceBeepActive = true;
        unawaited(_playWarningBeep());
      } else if (reading.distanceMeters >= 0.60) {
        _closeDistanceBeepActive = false;
      }
      if (_telemetryUiTimer?.isActive != true) {
        _telemetryUiTimer = Timer(const Duration(milliseconds: 120), () {
          if (mounted) {
            setState(() {});
            unawaited(_announceScene());
          }
        });
      }
    });
    await _ensureTelemetryListening();
    _telemetryRetryTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_telemetryService.isListening) unawaited(_ensureTelemetryListening());
    });
    _telemetryFreshnessTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (!mounted || _telemetry == null) return;
        if (DateTime.now().difference(_telemetry!.receivedAt) >
            _telemetryMaxAge) {
          setState(() {
            _telemetry = null;
            _closeDistanceBeepActive = false;
          });
          unawaited(_announceScene());
        }
      },
    );
  }

  Future<void> _ensureTelemetryListening() async {
    if (_telemetryStartInFlight || _telemetryService.isListening) return;
    _telemetryStartInFlight = true;
    try {
      await _telemetryService.start();
      debugPrint('[distance] ESP32 UDP receiver ready on port 4567');
    } catch (error) {
      debugPrint('[distance] ESP32 UDP receiver start failed: $error');
    } finally {
      _telemetryStartInFlight = false;
    }
  }

  bool get _isEspCamera => _settings?.usePhoneCamera == false;

  SensorTelemetry? get _freshTelemetry {
    final reading = _telemetry;
    if (!_isEspCamera ||
        reading == null ||
        DateTime.now().difference(reading.receivedAt) > _telemetryMaxAge) {
      return null;
    }
    return reading;
  }

  Future<void> _initializeDetectionTts() async {
    try {
      await _speech.ensureReady();
      _detectionTtsReady = true;
      debugPrint('[detection] Distance-aware voice alerts ready');
      unawaited(_announceScene());
    } catch (error) {
      debugPrint('[detection] Could not initialize voice alerts: $error');
    }
  }

  /// Detections as the user should hear about them: nearest first, each
  /// with a distance when one can be estimated. With the ESP32 the
  /// ultrasonic reading replaces the camera estimate for whatever is
  /// straight ahead.
  List<SceneObject> get _scene {
    final visible = _visibleDetections;
    if (visible.isEmpty || _frameSize.isEmpty) return const [];
    final estimator = DistanceEstimator(
        focalFactor: _isEspCamera
            ? DistanceEstimator.espFocalFactor
            : DistanceEstimator.phoneFocalFactor);
    var objects = nearestFirst([
      for (final d in visible)
        rangedObject(
            label: d.label,
            confidence: d.confidence,
            left: d.boundingBox.left,
            top: d.boundingBox.top,
            right: d.boundingBox.right,
            bottom: d.boundingBox.bottom,
            frameWidth: _frameSize.width,
            frameHeight: _frameSize.height,
            estimator: estimator)
    ]);
    final reading = _freshTelemetry;
    if (reading != null) {
      // Not for a pothole or an open drain: the sensor looks over them.
      final index = objects.indexWhere((o) =>
          sideOf(o, _frameSize.width) == Side.ahead &&
          !DistanceEstimator.belowSensor.contains(o.label.toLowerCase()));
      if (index >= 0) {
        final o = objects[index];
        objects[index] = SceneObject(
            label: o.label,
            confidence: o.confidence,
            left: o.left,
            top: o.top,
            right: o.right,
            bottom: o.bottom,
            meters: reading.distanceMeters);
        objects = nearestFirst(objects);
      }
    }
    return objects;
  }

  /// Distance to the nearest thing in the way: the sensor when it is fresh,
  /// otherwise the camera estimate of the nearest object.
  double? get _nearestMeters {
    final scene = _scene;
    final camera = scene.isEmpty ? null : scene.first.meters;
    final sensor = _freshTelemetry?.distanceMeters;
    if (sensor != null && (camera == null || sensor < camera)) return sensor;
    return camera;
  }

  Future<void> _announceScene() async {
    if (!_detectionTtsReady || !mounted) return;
    final scene = _scene;
    if (scene.isEmpty) return;
    final key = sceneKey(scene, _frameSize.width);
    final now = DateTime.now();
    final sinceLast = now.difference(_lastDetectionAnnouncement);
    if (key == _lastSceneKey && sinceLast < _repeatSameScene) return;
    // Something new within arm's reach, or an open drain anywhere in view,
    // interrupts; anything else waits for the current sentence to finish.
    final nearest = scene.first.meters;
    final urgent = key != _lastSceneKey &&
        ((nearest != null && nearest < .9) ||
            scene.take(2).any((o) => isDropHazard(o.label)));
    if (!urgent && sinceLast < _announcementCooldown) return;

    final message = spokenSummary(scene, _frameSize.width);
    _lastSceneKey = key;
    _lastDetectionAnnouncement = now;
    debugPrint('[detection] Voice alert: $message');
    try {
      // Only something new within reach cuts a route instruction off; a
      // routine scene update waits for the instruction to finish.
      await _speech.speakDetection(message,
          priority: urgent ? SpeechPriority.urgent : SpeechPriority.normal);
    } catch (error) {
      debugPrint('[detection] Voice alert failed: $error');
    }
  }

  /// Says "Path clear" once when the view empties, never while a blank
  /// surface is right in front of the lens.
  Future<void> _announcePathClear() async {
    if (!_detectionTtsReady || !mounted || _uniformWallActive) return;
    if (_dropHazardRecent || _tooDark) return;
    final sensor = _freshTelemetry?.distanceMeters;
    if (sensor != null && sensor < _visionClearMeters) return;
    final now = DateTime.now();
    if (now.difference(_lastPathClearAnnouncement) < _pathClearCooldown) return;
    if (now.difference(_lastDetectionAnnouncement) < _announcementCooldown) {
      return;
    }
    _lastPathClearAnnouncement = now;
    _lastSceneKey = null;
    try {
      await _speech.speakDetection('Path clear',
          priority: SpeechPriority.low);
    } catch (_) {}
  }

  String _detectionStatusText() {
    final scene = _scene;
    if (scene.isEmpty) {
      if (_tooDark) return 'Too dark to see, move slowly';
      if (_isEspCamera && _freshTelemetry == null) {
        return 'Waiting for sensor distance data';
      }
      return _pathUnclear || _dropHazardRecent
          ? 'Path unclear, move slowly'
          : 'Path is clear';
    }
    return statusLine(scene);
  }

  /// Nothing can be seen: forget what was seen before (it may no longer be
  /// there) and say so, instead of reporting objects or a clear path.
  void _onDarkFrame() {
    _recentLabelHistory.clear();
    _recentWeakDrop.clear();
    if (mounted) {
      setState(() {
        _tooDark = true;
        _detections = [];
        _uniformWallActive = false;
        _pathUnclear = false;
      });
    }
    _lastSceneKey = null;
    final now = DateTime.now();
    if (!_detectionTtsReady ||
        now.difference(_lastDarkAnnouncement) < _darkCooldown) {
      return;
    }
    _lastDarkAnnouncement = now;
    debugPrint('[detection] Frame too dark to see');
    unawaited(_speech.speakDetection('Too dark to see, move slowly.',
        priority: SpeechPriority.normal));
  }

  static bool _within(DateTime? at, Duration span) =>
      at != null && DateTime.now().difference(at) < span;

  bool get _dropHazardRecent =>
      _within(_lastDropHazardAt, _dropHazardMemory) ||
      _within(_lastWeakDropAt, _dropHazardMemory);

  /// Remembers when an open drain was last in view and beeps once when one
  /// comes into view. A weak sighting [weak] (not named) in 2 of the last 3
  /// analysed frames holds back "Path clear" too, and when nothing else is
  /// in view the app says "Path unclear" instead.
  void _trackDropHazards(
      List<YoloDetection> detections, List<YoloDetection> weak) {
    final now = DateTime.now();
    final named = detections.any((d) => isDropHazard(d.label));
    if (named) {
      _lastDropHazardAt = now;
      if (!_dropHazardBeepActive) {
        _dropHazardBeepActive = true;
        unawaited(_playWarningBeep());
      }
    } else if (!_dropHazardRecent) {
      _dropHazardBeepActive = false;
    }
    _recentWeakDrop.add(weak.any((d) => isDropHazard(d.label)));
    if (_recentWeakDrop.length > 3) _recentWeakDrop.removeAt(0);
    if (!named && _recentWeakDrop.where((w) => w).length >= 2) {
      _lastWeakDropAt = now;
      if (detections.isEmpty) unawaited(_announceUnclear('weak open drain'));
    }
  }

  /// "Path unclear ahead, move slowly", at most every [_unclearCooldown].
  Future<void> _announceUnclear(String why) async {
    final now = DateTime.now();
    if (!_detectionTtsReady ||
        now.difference(_lastUnclearAnnouncement) < _unclearCooldown) {
      return;
    }
    _lastUnclearAnnouncement = now;
    debugPrint('[detection] Unclear path ($why)');
    try {
      await _speech.speakDetection('Path unclear ahead, move slowly.');
    } catch (_) {}
  }

  /// Kills one-frame hallucinations: a label must appear in 2 of the last 3
  /// frames to count, unless it is confidently detected (>= 0.78). First two
  /// frames pass straight through so app start is never silent.
  List<YoloDetection> _confirmDetections(List<YoloDetection> input) {
    final labels = input.map((d) => d.label).toSet().toList();
    _recentLabelHistory.add(labels);
    if (_recentLabelHistory.length > 3) _recentLabelHistory.removeAt(0);
    if (input.isEmpty || _recentLabelHistory.length < 2) return input;
    final counts = <String, int>{};
    for (final frame in _recentLabelHistory) {
      for (final label in frame) {
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }
    return input
        .where((d) =>
    (counts[d.label] ?? 0) >= 2 || d.confidence >= 0.78)
        .toList();
  }

  /// Detections, plus a synthetic one when YOLO names nothing: "Obstacle"
  /// when the sensor sees something very close, "Wall" when the phone
  /// camera stares at a blank uniform surface (wall/closed door) with no
  /// sensor to help.
  List<YoloDetection> get _visibleDetections {
    if (_detections.isNotEmpty) return _detections;
    final reading = _freshTelemetry;
    if (reading != null &&
        reading.distanceMeters < _wallBlockedMeters &&
        !_frameSize.isEmpty) {
      // The sensor knows that something is there, not what: it may as well
      // be a person or a pole, so it is not called a wall.
      return [
        YoloDetection(
            label: 'Obstacle',
            confidence: 0.6,
            boundingBox: Rect.fromLTWH(
                0, 0, _frameSize.width, _frameSize.height))
      ];
    }
    if (_uniformWallActive && !_frameSize.isEmpty) {
      return [
        YoloDetection(
            label: 'Wall',
            confidence: 0.5,
            boundingBox: Rect.fromLTWH(
                0, 0, _frameSize.width, _frameSize.height))
      ];
    }
    return _detections;
  }

  void _maybeVisionBeep() {
    final meters = _nearestMeters;
    if (meters == null) return;
    if (meters < _visionCloseMeters && !_closeDistanceBeepActive) {
      _closeDistanceBeepActive = true;
      unawaited(_playWarningBeep());
    } else if (meters >= _visionClearMeters) {
      _closeDistanceBeepActive = false;
    }
  }

  Color _distanceColor(double meters) {
    if (meters <= 2) return const Color(0xFFDC2626);
    if (meters <= 3) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }

  Future<void> _loadModel() async {
    try {
      await _detectionService.loadModel();
      if (!mounted) return;
      setState(() {
        _isModelLoaded = _detectionService.isLoaded;
        if (!_isModelLoaded) _modelError = 'AI model unavailable';
      });
    } catch (_) {
      if (mounted) setState(() => _modelError = 'AI model unavailable');
    }
  }

  Future<void> _loadAdjustments() async {
    final settings = await CameraAdjustments.load();
    if (mounted) setState(() => _adjustments = settings);
  }

  Future<void> _editAdjustments() async {
    final updated = await showCameraAdjustments(context, _adjustments);
    if (updated == null || !mounted) return;
    setState(() => _adjustments = updated);
    await updated.save();
  }

  Future<void> _requestAndroidLocalNetworkPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      // Android 16 can opt apps into local-network protections. On that OS,
      // Nearby devices is the compatibility permission for target SDK 36.
      if (android.version.sdkInt >= 36) {
        final current = await Permission.nearbyWifiDevices.status;
        if (!current.isGranted && current.isDenied) {
          await Permission.nearbyWifiDevices.request();
        }
      }
    } catch (error) {
      debugPrint('Could not check Android local-network permission: $error');
    }
  }

  Future<void> _startCamera() async {
    _stopCamera();
    final generation = _generation;
    bool current() =>
        mounted &&
            generation == _generation &&
            _active &&
            _routeVisible &&
            !_editing;
    if (!current()) return;
    setState(() {
      _connecting = true;
      _connectionError = null;
      _detections = [];
    });
    try {
      final settings = await CameraSettings.load();
      if (!current()) return;
      _settings = settings;
      if (!settings.usePhoneCamera) _startDistancePolling(settings);
      if (!settings.usePhoneCamera) {
        await _requestAndroidLocalNetworkPermission();
        if (!current()) return;
      }
      if (settings.usePhoneCamera) {
        await _phoneClosing;
        if (!current()) return;
        final cameras =
        await availableCameras().timeout(const Duration(seconds: 10));
        if (!current()) return;
        if (cameras.isEmpty) throw StateError('No phone camera available.');
        // medium (480p) instead of low (320x240): the 384px world model was
        // being fed UPSCALED 240p frames; 480p gives real detail for small /
        // distant objects and the native decode downscales for free.
        final controller = CameraController(cameras.first, ResolutionPreset.medium,
            enableAudio: false);
        _controller = controller;
        await controller.initialize().timeout(const Duration(seconds: 15));
        if (!current()) return;
        try {
          await controller.setFlashMode(FlashMode.off);
          // Locked focus skips the ~500ms autofocus lock on every takePicture.
          // Distances come from detection box size / sensor, not camera focus.
          await controller.setFocusMode(FocusMode.locked);
          // NOTE: exposure is intentionally NOT locked. AE precapture waits
          // for CONTROL_AE_STATE to leave LOCKED (3); with ExposureMode.locked
          // it stays stuck and takePicture burns the full ~3s "Metering timeout
          // waiting for pre-capture to start" before every slow frame. Auto
          // exposure lets precapture converge (STATE 5) and shutter in ~250ms.
        } catch (_) {}
        if (!current()) return;
        setState(() => _connecting = false);
        _startDetection();
      } else {
        var processingFrame = false;
        Uint8List? latestPendingFrame;
        final stream = widget.streamFactory?.call() ?? MjpegStream();
        _stream = stream;
        Future<void> drainLatestFrames() async {
          while (current() && latestPendingFrame != null) {
            final bytes = latestPendingFrame!;
            latestPendingFrame = null;
            ui.Codec? codec;
            try {
              final pngBytes = await compute(_decodeJpegToPng, bytes,
                  debugLabel: 'decode-mjpeg-frame');
              codec = await ui.instantiateImageCodec(pngBytes);
              final frame = await codec.getNextFrame();
              if (!current()) {
                frame.image.dispose();
                continue;
              }
              final old = _streamImage;
              setState(() {
                _streamImage = frame.image;
                _frameSize = Size(frame.image.width.toDouble(),
                    frame.image.height.toDouble());
                _connecting = false;
              });
              if (old != null) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => old.dispose());
              }
              // Offered every frame: _detectFrame itself keeps to one
              // detection at a time and at most two a second. Offering only
              // every 4th frame left boxes on screen for seconds when the
              // ESP32's frame rate drops in dim light.
              unawaited(_detectFrame(bytes, generation,
                  imageWidth: frame.image.width,
                  imageHeight: frame.image.height));
            } catch (_) {
              if (current()) {
                _failCamera('Camera sent an invalid JPEG frame. Tap Retry.');
              }
            } finally {
              codec?.dispose();
            }
          }
          processingFrame = false;
          if (latestPendingFrame != null && current()) {
            processingFrame = true;
            unawaited(drainLatestFrames());
          }
        }

        void acceptLatestFrame(Uint8List bytes) {
          if (!current()) return;
          latestPendingFrame = bytes;
          if (processingFrame) return;
          processingFrame = true;
          unawaited(drainLatestFrames());
        }

        await stream.start(settings.streamUri, onFrame: acceptLatestFrame,
            onError: (error) {
              if (current()) {
                _failCamera(error is TimeoutException
                    ? 'Camera timed out. Check the hotspot and camera IP.'
                    : 'Cannot play ESP32 stream at ${settings.streamUri}. Check the phone and ESP32 are on the same hotspot and confirm the IP. If Android reports Operation not permitted, allow Nearby devices/local network access.\n$error');
              }
            });
      }
    } catch (error) {
      if (current()) {
        _failCamera(
            'Cannot start camera. Check settings and permissions.\n$error');
      }
    }
  }

  void _startDistancePolling(CameraSettings settings) {
    final source = settings.streamUri;
    final endpoint = Uri(
        scheme: source.scheme, host: source.host, port: 80, path: '/distance');
    _distanceEndpoint = endpoint;
    debugPrint('[camera] Configured stream ${settings.streamUri}; '
        'distance endpoint $endpoint');
    debugPrint(
        '[distance] Polling ESP32 endpoint $endpoint every 200 ms; UDP port ${_telemetryService.port}');

    Future<void> poll() async {
      if (!mounted || _distancePollInFlight || _distanceEndpoint != endpoint) {
        return;
      }
      _distancePollInFlight = true;
      try {
        final response = await _distanceHttpClient.get(endpoint,
            headers: const {
              'Accept': 'application/json'
            }).timeout(const Duration(milliseconds: 600));
        if (response.statusCode != 200 || _distanceEndpoint != endpoint) {
          if (_distanceEndpoint == endpoint) {
            _logDistancePollDiagnostic(
                'GET $endpoint returned HTTP ${response.statusCode}: ${response.body}');
          }
          return;
        }
        // Keep a throttled sample of the exact sensor packet for field debugging.
        _logDistancePollDiagnostic('Raw /distance packet: ${response.body}');
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          _logDistancePollDiagnostic(
              '/distance returned non-JSON object: ${response.body}');
          return;
        }
        double? number(Object? value) => value is num
            ? value.toDouble()
            : double.tryParse('$value');

        final cmValue = number(decoded['distanceCm']);
        final metersValue = number(decoded['distanceMeters']);
        final legacyValue = number(decoded['distance']);
        bool valid(double? value) =>
            value != null && value.isFinite && value > 0;
        final centimeters = valid(cmValue)
            ? cmValue!.round()
            : valid(metersValue)
            ? (metersValue! * 100).round()
            : valid(legacyValue)
            ? legacyValue!.round()
            : null;
        if (decoded['available'] == true && centimeters == null) {
          _logDistancePollDiagnostic(
              '/distance reports available but has no valid reading: ${response.body}');
        }
        if (centimeters != null && centimeters > 0) {
          _telemetryService.addHttpDistanceCentimeters(centimeters);
        } else {
          _logDistancePollDiagnostic(
              '/distance has no positive sensor reading: ${response.body}');
        }
      } catch (error) {
        _logDistancePollDiagnostic('GET $endpoint failed: $error');
        // UDP remains active; the HTTP fallback retries on the next tick.
      } finally {
        _distancePollInFlight = false;
      }
    }

    _distancePollTimer?.cancel();
    _distancePollTimer = Timer.periodic(
        const Duration(milliseconds: 200), (_) => unawaited(poll()));
    unawaited(poll());
  }

  void _logDistancePollDiagnostic(String message) {
    final now = DateTime.now();
    if (now.difference(_lastDistancePollDiagnostic) <
        const Duration(seconds: 3)) return;
    _lastDistancePollDiagnostic = now;
    debugPrint('[distance] $message');
  }

  Future<void> _playWarningBeep() async {
    try {
      await _beepChannel.invokeMethod<void>('playWarningBeep');
    } catch (error) {
      debugPrint('Could not play warning beep: $error');
    }
  }

  void _failCamera(String message) {
    _stopCamera();
    if (mounted) {
      setState(() {
        _connectionError = message;
        _connecting = false;
        _detections = [];
      });
    }
  }

  // Save alert with cooldown (avoid saving same alert multiple times)
  Future<void> _saveAlert(String message, String type) async {
    if (_lastSavedAlert == message &&
        DateTime.now().difference(_lastSavedTime).inSeconds < 5) {
      return;
    }
    _lastSavedAlert = message;
    _lastSavedTime = DateTime.now();
    await _alertService.saveAlert(message, type);
  }

  Future<void> _startDetection() async {
    // Stream capture is primary (no AF/AE precapture, no JPEG round trip).
    // takePicture is the watchdog fallback if the stream yields nothing.
    if (!_streamCaptureEnabled) {
      _startTakePictureTimer(_generation);
      return;
    }
    final generation = _generation;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      // Stream capture: frames are already in memory, so the camera
      // autofocus/shutter round-trip of takePicture() is gone. IMPORTANT:
      // startImageStream must be awaited so a session-config failure is
      // caught here, not as an unhandled async error.
      debugPrint('[cam] Starting image stream capture');
      await controller.startImageStream((CameraImage image) {
        if (!mounted || generation != _generation || _isDetecting) return;
        if (DateTime.now().difference(_lastDetection).inMilliseconds < 90) {
          return;
        }
        _handleStreamFrame(image, generation);
      });
      _streaming = true;
      _lastStreamFrameAt = DateTime.now();
      _streamWatchdog?.cancel();
      _streamWatchdog = Timer.periodic(
          const Duration(milliseconds: 600), (_) async {
        if (!mounted || generation != _generation || !_streaming) {
          _streamWatchdog?.cancel();
          return;
        }
        final idleMs = DateTime.now().difference(_lastStreamFrameAt);
        if (idleMs.inMilliseconds < 3000) return;
        debugPrint('[cam] Stream produced no usable frames for '
            '${idleMs.inSeconds}s; switching to takePicture');
        _streaming = false;
        _streamWatchdog?.cancel();
        try {
          await controller.stopImageStream();
        } catch (_) {}
        _startTakePictureTimer(generation);
      });
    } catch (error) {
      _streamFailures++;
      final usable = mounted &&
          generation == _generation &&
          _active &&
          _routeVisible &&
          !_editing;
      if (usable && _streamFailures <= 1) {
        debugPrint('[cam] Stream fail ($error); re-init camera attempt');
        await _startCamera();
      } else {
        debugPrint('[cam] Streaming unsupported; using takePicture timer');
        _startTakePictureTimer(generation);
      }
    }
  }

  Future<void> _handleStreamFrame(CameraImage image, int generation) async {
    try {
      final stopwatch = Stopwatch()..start();
      if (image.planes.length >= 3) {
        // Any 3-plane frame on Android is YUV_420_888 (some devices report
        // the group as yuv422 although the layout is 4:2:0). Convert
        // straight to model-sized RGBA: no JPEG encode, no JPEG decode.
        final target = _detectionService.mainInputSize;
        final longSide =
            image.width > image.height ? image.width : image.height;
        final scale = longSide > target ? target / longSide : 1.0;
        final targetWidth = (image.width * scale).round().clamp(1, image.width);
        final targetHeight =
            (image.height * scale).round().clamp(1, image.height);
        final rgba = await compute(
            _yuvToRgba,
            {
              'y': image.planes[0].bytes,
              'u': image.planes[1].bytes,
              'v': image.planes[2].bytes,
              'width': image.width,
              'height': image.height,
              'targetWidth': targetWidth,
              'targetHeight': targetHeight,
              'rowStrideY': image.planes[0].bytesPerRow,
              'rowStrideU': image.planes[1].bytesPerRow,
              'rowStrideV': image.planes[2].bytesPerRow,
              'pixelStrideU': image.planes[1].bytesPerPixel,
              'pixelStrideV': image.planes[2].bytesPerPixel,
            },
            debugLabel: 'stream-yuv2rgba');
        if (!mounted || generation != _generation) return;
        _lastStreamFrameAt = DateTime.now();
        _frameSize = Size(image.width.toDouble(), image.height.toDouble());
        if (rgba == null) return;
        debugPrint(
            '[cam] frame ${image.width}x${image.height} yuv2rgba=${rgba.length}B prep=${stopwatch.elapsedMilliseconds}ms');
        await _detectFrame(null, generation,
            rgbaInput: rgba,
            rgbaWidth: targetWidth,
            rgbaHeight: targetHeight,
            imageWidth: image.width,
            imageHeight: image.height);
      } else if (image.format.group == ImageFormatGroup.jpeg ||
          image.planes.length == 1) {
        final bytes = image.planes.first.bytes;
        if (!mounted || generation != _generation) return;
        _lastStreamFrameAt = DateTime.now();
        _frameSize = Size(image.width.toDouble(), image.height.toDouble());
        await _detectFrame(bytes, generation,
            imageWidth: image.width, imageHeight: image.height);
      } else {
        debugPrint('[cam] Unsupported stream format group=${image.format.group} '
            'planes=${image.planes.length}; skipping frame');
      }
    } catch (error) {
      debugPrint('[cam] Stream frame error: $error');
    }
  }

  void _startTakePictureTimer(int generation) {
    var capturing = false;
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
          final controller = _controller;
          if (controller == null ||
              !controller.value.isInitialized ||
              capturing ||
              _isDetecting) {
            return;
          }
          capturing = true;
          try {
            final captureSw = Stopwatch()..start();
            // Bound a stuck AE precapture (seen: 3.1s + "Metering timeout"
            // storms when inference starves the camera threads). A timed-out
            // shutter just skips the frame; the next tick retries. Stream
            // capture is primary now, so this timer is fallback-only.
            final image = await controller
                .takePicture()
                .timeout(const Duration(seconds: 6));
            final bytes = await image
                .readAsBytes()
                .timeout(const Duration(seconds: 3));
            captureSw.stop();
            if (captureSw.elapsedMilliseconds > 1500) {
              debugPrint(
                  '[cam] SLOW capture=${captureSw.elapsedMilliseconds}ms bytes=${bytes.length} (precapture stall; stream capture avoids this)');
            } else {
              debugPrint(
                  '[cam] capture=${captureSw.elapsedMilliseconds}ms bytes=${bytes.length}');
            }
            if (!mounted || generation != _generation) return;
            // Frame dimensions + RGBA decode now happen once inside _detectFrame
            // (native codec); no separate Dart JPEG size read per frame.
            await _detectFrame(bytes, generation);
          } on TimeoutException catch (error) {
            // Stuck precapture: skip the frame, keep last detections on
            // screen. Never surface per-frame errors as _modelError.
            debugPrint('[cam] capture timeout, frame skipped: $error');
          } catch (error) {
            debugPrint('[cam] Frame capture failed, skipped: $error');
          } finally {
            capturing = false;
          }
        });
  }

  Future<void> _detectFrame(Uint8List? jpegBytes, int generation,
      {Uint8List? rgbaInput,
        int rgbaWidth = 0,
        int rgbaHeight = 0,
        int? imageWidth,
        int? imageHeight}) async {
    if (!_isModelLoaded ||
        _isDetecting ||
        DateTime.now().difference(_lastDetection).inMilliseconds < 500) {
      return;
    }
    if (_warmupSkips > 0) {
      _warmupSkips--;
      return;
    }
    _lastDetection = DateTime.now();
    _isDetecting = true;
    try {
      final detectSw = Stopwatch()..start();
      var width = imageWidth ?? 0;
      var height = imageHeight ?? 0;
      var rgba = rgbaInput;
      var rgbaW = rgbaWidth;
      var rgbaH = rgbaHeight;
      if (rgba == null && jpegBytes != null) {
        // One native decode per frame, downscaled to the largest model
        // input. All models share this buffer (each letterboxes it to its
        // own input size inside the service).
        final target = _detectionService.mainInputSize;
        final decoded = await _decodeFrame(jpegBytes, target);
        if (decoded != null) {
          rgba = decoded.rgba;
          rgbaW = decoded.width;
          rgbaH = decoded.height;
          width = decoded.frameWidth;
          height = decoded.frameHeight;
        } else {
          // Native decode failed (torn frame?) — fall back to the old
          // Dart path just to learn the size; the service then decodes
          // the JPEG itself. Skip the frame if even that fails.
          try {
            final dimensions = await compute(_readJpegSize, jpegBytes,
                debugLabel: 'read-camera-frame-size');
            width = dimensions[0];
            height = dimensions[1];
          } catch (_) {
            debugPrint('[cam] Frame decode failed, skipped');
            return;
          }
        }
      }
      if (width <= 0 || height <= 0) return;
      _frameSize = Size(width.toDouble(), height.toDouble());
      if (_rgbaTooDark(rgba)) {
        _onDarkFrame();
        return;
      }
      if (_tooDark && mounted) setState(() => _tooDark = false);
      final detections = await _detectionService.detectImage(
        jpegBytes ?? Uint8List(0),
        width,
        height,
        rgbaInput: rgba,
        rgbaWidth: rgba == null ? null : rgbaW,
        rgbaHeight: rgba == null ? null : rgbaH,
      );
      detectSw.stop();
      debugPrint('[cam] detection=${detectSw.elapsedMilliseconds}ms');
      if (!mounted || generation != _generation) return;
      final confirmed = _confirmDetections(detections);
      _trackDropHazards(confirmed, _detectionService.weakSightings);
      setState(() {
        _detections = confirmed;
        _modelError = null;
      });
      final visible = _visibleDetections;
      if (visible.isNotEmpty) {
        _emptyStreak = 0;
        if (_uniformWallActive) _uniformWallActive = false;
        _pathUnclear = false;
        _lastVisibleDetectionAt = DateTime.now();
        _maybeVisionBeep();
        unawaited(_announceScene());
      } else {
        // Phone with no sensor: blank uniform frames in a row = wall/door.
        if (_freshTelemetry == null) {
          _emptyStreak++;
          if (_emptyStreak >= 2) {
            try {
              final variance = rgba == null && jpegBytes != null
                  ? await compute(_frameUniformityVariance, jpegBytes,
                  debugLabel: 'frame-uniformity')
                  : _rgbaUniformityVariance(rgba);
              final uniform = variance < _uniformWallVariance;
              final unclear = !uniform && variance < _unclearPathVariance;
              if ((uniform != _uniformWallActive ||
                      unclear != _pathUnclear) &&
                  mounted) {
                setState(() {
                  _uniformWallActive = uniform;
                  _pathUnclear = unclear;
                });
              }
              if (!uniform && !unclear && _emptyStreak == 2) {
                // A detailed view with nothing recognised in it.
                unawaited(_announcePathClear());
              }
              if (uniform) {
                _lastVisibleDetectionAt = DateTime.now();
                _maybeVisionBeep();
                unawaited(_announceScene());
              } else if (_emptyStreak >= 8 &&
                  variance < _unclearPathVariance) {
                // Textured wall/door/pole: something is there but unnamed.
                // Never name it — safe generic slow-down warning only.
                await _announceUnclear(
                    'variance=${variance.toStringAsFixed(0)}');
              }
            } catch (_) {}
          }
        } else {
          _emptyStreak = 0;
          _uniformWallActive = false;
          _pathUnclear = false;
        }
        if (_lastVisibleDetectionAt != null &&
            DateTime.now().difference(_lastVisibleDetectionAt!) >
                const Duration(seconds: 2)) {
          _lastSceneKey = null;
          _lastVisibleDetectionAt = null;
        }
      }
      final scene = _scene;
      if (_detections.isNotEmpty && scene.isNotEmpty) {
        if (mounted && generation == _generation) {
          final nearest = scene.first;
          unawaited(_saveAlert(
              '${nearest.label} ${sidePhrase(sideOf(nearest, _frameSize.width))}',
              'obstacle'));
        }
      }
    } catch (error) {
      // Per-frame failures (torn JPEG, TFLite hiccup) must never wipe the
      // last good detections or flip the status card to "Detection
      // unavailable" — that flickered on every bad frame. Just skip.
      debugPrint('[yolo] Detection failed for frame, skipped: $error');
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final newMode = _flashOn ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newMode);
      if (mounted && _controller != null) setState(() => _flashOn = !_flashOn);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraRouteObserver.unsubscribe(this);
    _stopCamera();
    _detectionService.dispose();
    _telemetryFreshnessTimer?.cancel();
    _telemetryRetryTimer?.cancel();
    _telemetryUiTimer?.cancel();
    _telemetrySubscription?.cancel();
    _telemetryService.dispose();
    unawaited(_speech.stopDetection());
    _distanceHttpClient.close();
    super.dispose();
  }

  /// What is in view, nearest first: "Door straight ahead · about 2 meters".
  Widget _buildDistanceCard(SensorTelemetry? reading) {
    final scene = _scene;
    final nearest = _nearestMeters;
    final sensorBlocked =
        reading != null && reading.distanceMeters < _visionClearMeters;
    final clear = scene.isEmpty &&
        !_pathUnclear &&
        !sensorBlocked &&
        !_dropHazardRecent &&
        !_tooDark;
    final color = clear
        ? const Color(0xFF22C55E)
        : nearest == null
            ? const Color(0xFFF59E0B)
            : _distanceColor(nearest);
    final lines = <String>[
      for (final object in scene.take(4))
        describeLine(object, _frameSize.width),
      if (scene.isEmpty)
        clear
            ? 'Path clear'
            : sensorBlocked
                ? 'Obstacle ahead · ${distancePhrase(reading.distanceMeters)}'
                : _tooDark
                    ? 'Too dark to see · move slowly'
                    : 'Path unclear · move slowly',
      if (reading != null)
        'Sensor: ${(reading.distanceMeters * 100).round()} cm'
      else if (_isEspCamera)
        'Sensor distance unavailable',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(clear ? Icons.check_circle_outline : Icons.social_distance,
            color: color, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text(line,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("EYRIS Camera"),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            final homeState =
            context.findAncestorStateOfType<HomeScreenState>();
            if (homeState != null) {
              homeState.changeTab(0);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: 'Camera adjustments',
              onPressed: _editAdjustments),
          IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Camera settings',
              onPressed: _editSettings),
          // Flash / torch toggle
          IconButton(
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: _flashOn ? Colors.amber : Colors.white,
            ),
            onPressed: _settings?.usePhoneCamera == true ? _toggleFlash : null,
            tooltip: _settings?.usePhoneCamera == true
                ? 'Flash'
                : 'Flash is available with the phone camera',
          ),
          // View alert history
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: () {
              final homeState =
              context.findAncestorStateOfType<HomeScreenState>();
              if (homeState != null) {
                homeState.changeTab(3);
              } else {
                Navigator.pushNamed(context, '/alerts');
              }
            },
            tooltip: "Alert History",
          ),
        ],
      ),
      body: _connecting || _connectionError != null
          ? Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_connecting)
                  const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                Text(_connectionError ?? 'Connecting to camera...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15)),
                if (_connectionError != null)
                  TextButton(
                      onPressed: _resumeCamera, child: const Text('Retry')),
                TextButton(
                    onPressed: _editSettings,
                    child: const Text('Camera settings')),
              ])))
          : Stack(
        children: [
          Positioned.fill(
              child: LayoutBuilder(builder: (context, constraints) {
                final phone = _settings?.usePhoneCamera == true;
                final aspect = phone && _controller != null
                    ? (_controller!.value.deviceOrientation ==
                    DeviceOrientation.portraitUp ||
                    _controller!.value.deviceOrientation ==
                        DeviceOrientation.portraitDown
                    ? 1 / _controller!.value.aspectRatio
                    : _controller!.value.aspectRatio)
                    : (_frameSize.isEmpty ? 4 / 3 : _frameSize.aspectRatio);
                return Center(
                    child: AspectRatio(
                        aspectRatio: aspect,
                        child: Stack(fit: StackFit.expand, children: [
                          ColorFiltered(
                            colorFilter:
                            ColorFilter.matrix(_adjustments.colorMatrix),
                            child: phone && _controller != null
                                ? CameraPreview(_controller!)
                                : RawImage(
                                image: _streamImage, fit: BoxFit.contain),
                          ),
                          CustomPaint(
                              painter: DetectionPainter(
                                  _visibleDetections, _frameSize)),
                        ])));
              })),
          // Object count indicator
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_rounded,
                    color: _visibleDetections.isEmpty
                        ? Colors.white70
                        : Colors.amber,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${_visibleDetections.length} object${_visibleDetections.length == 1 ? '' : 's'}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Fused sensor + camera distance, works on phone and ESP32.
          Positioned(
            top: 70,
            left: 16,
            right: 16,
            child: _buildDistanceCard(_freshTelemetry),
          ),
          // Status indicator
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: (_modelError != null || !_isModelLoaded
                    ? Colors.grey
                    : _scene.isEmpty
                    ? (_pathUnclear
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF16A34A))
                    : _distanceColor(_nearestMeters ?? 2.5))
                    .withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _modelError != null || !_isModelLoaded
                          ? Icons.info_outline
                          : _scene.isNotEmpty
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _modelError != null || !_isModelLoaded
                          ? (_modelError ?? 'Loading AI model...')
                          : _detectionStatusText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<YoloDetection> detections;
  final Size frameSize;
  DetectionPainter(this.detections, this.frameSize);

  @override
  void paint(Canvas canvas, Size size) {
    if (frameSize.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / frameSize.width, size.height / frameSize.height);
    for (var d in detections) {
      final paint = Paint()
        ..color = d.confidence > 0.5 ? Colors.red : Colors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRect(d.boundingBox, paint);

      final textSpan = TextSpan(
        text: "${d.label} ${(d.confidence * 100).toInt()}%",
        style: const TextStyle(
            color: Colors.white, fontSize: 12, backgroundColor: Colors.black54),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(d.boundingBox.left, d.boundingBox.top - 18));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant old) => true;
}
