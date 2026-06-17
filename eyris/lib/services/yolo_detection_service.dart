import 'package:flutter/foundation.dart'; // This covers both debugPrint and Uint8List
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class YoloDetection {
  final String label;
  final double confidence;
  final Rect boundingBox;
  YoloDetection({required this.label, required this.confidence, required this.boundingBox});
  String getAlertMessage() => "⚠️ $label detected ahead";
}

class YoloDetectionService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isLoaded = false;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yolov8n_float32.tflite');
      final labelsRaw = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelsRaw.trim().split('\n');
      _isLoaded = true;
      debugPrint("✅ YOLOv8n loaded on phone");
    } catch (e) {
      debugPrint("❌ Load error: $e");
    }
  }

  Future<List<YoloDetection>> detectImage(Uint8List imageBytes, int imageWidth, int imageHeight) async {
    if (!_isLoaded) return [];

    img.Image? original = img.decodeImage(imageBytes);
    if (original == null) return [];

    img.Image resized = img.copyResize(original, width: 320, height: 320);

    var input = List.filled(1 * 320 * 320 * 3, 0.0);
    int idx = 0;
    
    for (int y = 0; y < 320; y++) {
      for (int x = 0; x < 320; x++) {
        final pixel = resized.getPixel(x, y);
        input[idx++] = pixel.rNormalized.toDouble();
        input[idx++] = pixel.gNormalized.toDouble();
        input[idx++] = pixel.bNormalized.toDouble();
      }
    }
    var inputTensor = input.reshape([1, 320, 320, 3]);

    // Output shape [1, 300, 6]
    var output = List.filled(1 * 300 * 6, 0.0).reshape([1, 300, 6]);
    _interpreter?.run(inputTensor, output);

    List<YoloDetection> detections = [];
    for (var det in output[0]) {
      double confidence = det[4];
      if (confidence < 0.5) continue;
      int classId = det[5].toInt();
      if (classId >= _labels!.length) continue;

      double x1 = det[0] * imageWidth;
      double y1 = det[1] * imageHeight;
      double x2 = det[2] * imageWidth;
      double y2 = det[3] * imageHeight;
      Rect box = Rect.fromLTRB(x1, y1, x2, y2);

      detections.add(YoloDetection(
        label: _labels![classId],
        confidence: confidence,
        boundingBox: box,
      ));
    }
    return detections;
  }

  void dispose() => _interpreter?.close();
}