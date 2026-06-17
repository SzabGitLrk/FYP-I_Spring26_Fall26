import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/yolo_detection_service.dart';
import '../services/alert_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  final YoloDetectionService _detectionService = YoloDetectionService();
  final FlutterTts _flutterTts = FlutterTts();
  final AlertService _alertService = AlertService(); // ✅ Alert service added
  
  List<YoloDetection> _detections = [];
  bool _isModelLoaded = false;
  Timer? _detectionTimer;
  String _lastSpoken = "";
  DateTime _lastSpokenTime = DateTime.now();
  
  // Track last saved alert to avoid duplicate saves
  String _lastSavedAlert = "";
  DateTime _lastSavedTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initTTS();
    _initCameraAndModel();
  }

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
  }

  // Speak method with cooldown
  Future<void> _speak(String text) async {
    if (_lastSpoken == text && DateTime.now().difference(_lastSpokenTime).inSeconds < 3) return;
    _lastSpoken = text;
    _lastSpokenTime = DateTime.now();
    await _flutterTts.speak(text);
  }
  
  // Save alert with cooldown (avoid saving same alert multiple times)
  Future<void> _saveAlert(String message, String type) async {
    if (_lastSavedAlert == message && DateTime.now().difference(_lastSavedTime).inSeconds < 5) return;
    _lastSavedAlert = message;
    _lastSavedTime = DateTime.now();
    await _alertService.saveAlert(message, type);
  }

  Future<void> _initCameraAndModel() async {
    await _detectionService.loadModel();
    
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.medium);
    await _controller!.initialize();
    
    setState(() {
      _isModelLoaded = true;
    });
    
    _startDetection();
  }

  void _startDetection() {
    _detectionTimer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      if (_controller == null || !_controller!.value.isInitialized) return;
      
      try {
        final image = await _controller!.takePicture();
        final bytes = await image.readAsBytes();
        final width = _controller!.value.previewSize!.width.toInt();
        final height = _controller!.value.previewSize!.height.toInt();
        
        final detections = await _detectionService.detectImage(bytes, width, height);
        
        setState(() {
          _detections = detections;
        });
        
        // Voice alert and save to history for detected objects
        if (detections.isNotEmpty) {
          // Pick the highest confidence detection
          final best = detections.reduce((a, b) => a.confidence > b.confidence ? a : b);
          if (best.confidence > 0.3) {
            // Speak the alert
            _speak(best.getAlertMessage());
            // ✅ Save alert to history
            _saveAlert(best.getAlertMessage(), "obstacle");
          }
        }
      } catch (e) {
        debugPrint("Detection error: $e");
      }
    });
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _controller?.dispose();
    _detectionService.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isModelLoaded || _controller == null) {
      return Scaffold(
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text("Loading model..."),
          ],
        )),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("EYRIS Camera"),
        backgroundColor: Colors.black,
        actions: [
          // ✅ Button to view alert history
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/alerts');
            },
            tooltip: "Alert History",
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          CustomPaint(
            painter: DetectionPainter(_detections),
            size: Size.infinite,
          ),
          // Object count indicator
          Positioned(
            top: 20,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Objects: ${_detections.length}",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          // Status indicator
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _detections.isNotEmpty ? Icons.warning_amber : Icons.check_circle,
                    color: _detections.isNotEmpty ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _detections.isNotEmpty 
                          ? "${_detections.length} obstacle(s) detected"
                          : "No obstacles detected",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
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
  DetectionPainter(this.detections);
  
  @override
  void paint(Canvas canvas, Size size) {
    for (var d in detections) {
      final paint = Paint()
        ..color = d.confidence > 0.5 ? Colors.red : Colors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRect(d.boundingBox, paint);
      
      final textSpan = TextSpan(
        text: "${d.label} ${(d.confidence * 100).toInt()}%",
        style: const TextStyle(color: Colors.white, fontSize: 12, backgroundColor: Colors.black54),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(d.boundingBox.left, d.boundingBox.top - 18));
    }
  }
  
  @override
  bool shouldRepaint(covariant old) => true;
}