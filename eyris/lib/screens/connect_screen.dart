import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'home_screen.dart';
import '../services/camera_settings.dart';
import '../widgets/camera_settings_dialog.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  static const String deviceName = 'EYRIS Smart Glasses';
  static const String deviceId = 'ESP32-CAM-001';
  http.Client? _statusClient;
  int _connectionGeneration = 0;

  bool isConnected = false;
  bool isConnecting = false;
  String signal = 'N/A';

  Timer? statusTimer;

  // Voice feedback
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTTS();
  }

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    _connectionGeneration++;
    _statusClient?.close();
    _flutterTts.stop();
    super.dispose();
  }

  /// Embedded as a tab inside HomeScreen → switch back to tab 0.
  void _goBackToHome() {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    if (homeState != null) {
      homeState.changeTab(0);
    } else {
      Navigator.maybePop(context);
    }
  }

  // CONNECT LOGIC WITH VOICE FEEDBACK
  Future<void> connectSmartGlasses() async {
    final generation = ++_connectionGeneration;
    setState(() {
      isConnecting = true;
      signal = 'Checking...';
    });

    _speak("Connecting to smart glasses");

    try {
      final hardwareReady = await checkHardware();

      if (!mounted || generation != _connectionGeneration) return;

      if (!hardwareReady) {
        _speak("Hardware not responding. Check if glasses are powered on");
        throw Exception('Hardware not responding');
      }

      setState(() {
        isConnected = true;
        isConnecting = false;
        signal = 'Good';
      });

      startStatusCheck();
      _speak("Glasses connected successfully");
      showMessage('Smart glasses connected.');
    } catch (e) {
      if (!mounted || generation != _connectionGeneration) return;
      _speak("Connection failed. Please check your glasses and try again");
      setDisconnected();
      showMessage('Connection failed. Hardware check karein.');
    }
  }

  Future<void> disconnectSmartGlasses() async {
    _connectionGeneration++;
    statusTimer?.cancel();
    _statusClient?.close();
    _speak("Disconnecting smart glasses");
    setDisconnected();
    _speak("Device disconnected");
    showMessage('Device disconnected.');
  }

  Future<bool> checkHardware() async {
    final client = http.Client();
    _statusClient?.close();
    _statusClient = client;
    try {
      final settings = await CameraSettings.load();
      if (!mounted) return false;
      final response = await client
          .get(settings.statusUri)
          .timeout(const Duration(seconds: 4));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
      if (identical(_statusClient, client)) _statusClient = null;
    }
  }

  void startStatusCheck() {
    statusTimer?.cancel();

    statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final generation = _connectionGeneration;
      final alive = await checkHardware();

      if (!mounted || generation != _connectionGeneration) return;

      if (!alive) {
        _speak("Glasses disconnected. Connection lost");
        setDisconnected();
        statusTimer?.cancel();
        showMessage('Device lost connection');
      }
    });
  }

  void setDisconnected() {
    if (!mounted) return;

    setState(() {
      isConnected = false;
      isConnecting = false;
      signal = 'N/A';
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = isConnecting
        ? 'Connecting...'
        : isConnected
            ? 'Connected'
            : 'Disconnected';

    final statusColor = isConnected
        ? const Color(0xFF36D399)
        : isConnecting
            ? const Color(0xFFFFC857)
            : const Color(0xFFFF5C6C);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        title: const Text(
          "Device Connection",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0A0F1E),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Camera settings',
              onPressed: () async {
                await disconnectSmartGlasses();
                if (!context.mounted) return;
                await showCameraSettings(context);
              })
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _goBackToHome,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // STATUS BAR
            Container(
              height: 70,
              width: double.infinity,
              color: statusColor.withValues(alpha: 0.15),
              child: Center(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            const Spacer(),

            // DEVICE INFO
            Icon(
              Icons.bluetooth_searching,
              size: 80,
              color: statusColor.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 15),
            Text(
              deviceName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "ID: $deviceId",
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),

            const Spacer(),

            // BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isConnected ? Colors.redAccent : Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  onPressed: isConnecting
                      ? null
                      : isConnected
                          ? disconnectSmartGlasses
                          : connectSmartGlasses,
                  child: Text(
                    isConnecting
                        ? "Connecting..."
                        : isConnected
                            ? "Disconnect"
                            : "Connect Device",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}
