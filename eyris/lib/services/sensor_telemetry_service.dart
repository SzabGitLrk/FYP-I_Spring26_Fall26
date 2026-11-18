import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SensorTelemetry {
  const SensorTelemetry({
    required this.distanceMeters,
    this.objectName = 'Obstacle',
    this.receivedFromHttp = false,
    required this.receivedAt,
  });

  final double distanceMeters;
  final String objectName;
  final bool receivedFromHttp;
  final DateTime receivedAt;
}

/// Receives ESP32-S3 range readings on the phone hotspot's local network.
/// UDP datagrams from the ESP32 are received on port 4567.
/// Payload examples: {"distanceMeters":1.2}, {"distanceCm":120}, or `120`.
/// Firmware should send meters to the phone hotspot/gateway IP at port 4567.
class SensorTelemetryService {
  SensorTelemetryService({this.port = 4567});
  final int port;
  final _controller = StreamController<SensorTelemetry>.broadcast();
  static const _multicastChannel =
      MethodChannel('com.example.eyris_app/wifi_multicast_lock');
  RawDatagramSocket? _udp;
  bool _multicastLockHeld = false;
  Stream<SensorTelemetry> get stream => _controller.stream;
  bool get isListening => _udp != null;

  Future<void> start() async {
    if (isListening) return;
    RawDatagramSocket? udp;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _multicastChannel.invokeMethod<void>('acquire');
          _multicastLockHeld = true;
        } catch (error) {
          debugPrint('Could not acquire Android Wi-Fi multicast lock: $error');
        }
      }
      udp = await RawDatagramSocket.bind(InternetAddress('0.0.0.0'), port,
          reuseAddress: true, reusePort: false);
      _udp = udp;
      debugPrint('[distance] UDP listener bound to 0.0.0.0:$port');
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        while (true) {
          final datagram = udp!.receive();
          if (datagram == null) break;
          debugPrint(
              '[distance] UDP ${datagram.address.address}:${datagram.port} '
              '-> $port: ${utf8.decode(datagram.data, allowMalformed: true).trim()}');
          _parse(utf8.decode(datagram.data, allowMalformed: true));
        }
      }, onError: (Object error, StackTrace stackTrace) {
        debugPrint('[distance] UDP socket error on port $port: $error');
      }, onDone: () {
        debugPrint('[distance] UDP listener closed on port $port');
        _udp = null;
      });
    } catch (error, stackTrace) {
      udp?.close();
      _udp = null;
      await _releaseMulticastLock();
      debugPrint('[distance] Could not bind UDP port $port: $error\n$stackTrace');
      rethrow;
    }
  }

  void _parse(String payload) {
    final text = payload.trim();
    if (RegExp(r'^\d+$').hasMatch(text)) {
      final centimeters = int.tryParse(text);
      if (centimeters != null && centimeters > 0) {
        debugPrint(
            '[distance] Parsed integer payload as centimeters: $centimeters');
        _publish(centimeters / 100.0);
      }
      return;
    }
    try {
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      final map = decoded is Map ? decoded : <String, dynamic>{};
      final metersValue = map['distanceMeters'] ?? map['depth'];
      final centimetersValue =
          map['distanceCm'] ?? (metersValue == null ? map['distance'] : null);
      final meters = metersValue is num
          ? metersValue.toDouble()
          : double.tryParse('$metersValue');
      final centimeters = centimetersValue is num
          ? centimetersValue.toDouble()
          : double.tryParse('$centimetersValue');
      final validMeters = meters != null && meters.isFinite && meters > 0
          ? meters
          : null;
      final validCentimeters = centimeters != null &&
              centimeters.isFinite &&
              centimeters > 0
          ? centimeters
          : null;
      final distance = validMeters ??
          (validCentimeters == null ? double.nan : validCentimeters / 100.0);
      if (distance.isFinite && distance > 0) {
        debugPrint('[distance] Parsed UDP JSON as '
            '${validMeters != null ? 'meters' : 'centimeters'}: '
            '${validMeters ?? validCentimeters}');
        _publish(distance,
            objectName: '${map['objectName'] ?? map['label'] ?? 'Obstacle'}');
      } else {
        debugPrint(
            '[distance] Ignoring JSON without a positive distance: $text');
      }
    } catch (_) {
      final distance = double.tryParse(payload.trim());
      if (distance != null && distance.isFinite && distance > 0) {
        debugPrint('[distance] Parsed fallback payload as meters: $distance');
        _publish(distance);
      } else {
        debugPrint('[distance] Ignoring invalid payload: $text');
      }
    }
  }

  void addHttpDistanceCentimeters(int centimeters) {
    if (centimeters <= 0) return;
    debugPrint('[distance] HTTP /distance reading: $centimeters cm '
        '(${(centimeters / 100).toStringAsFixed(2)} m)');
    _publish(centimeters / 100.0, receivedFromHttp: true);
  }

  void _publish(double distanceMeters,
      {String objectName = 'Obstacle', bool receivedFromHttp = false}) {
    debugPrint('[distance] Published ${distanceMeters.toStringAsFixed(2)} m '
        'from ${receivedFromHttp ? 'HTTP' : 'UDP'}');
    _controller.add(SensorTelemetry(
      distanceMeters: distanceMeters,
      objectName: objectName,
      receivedFromHttp: receivedFromHttp,
      receivedAt: DateTime.now(),
    ));
  }

  Future<void> _releaseMulticastLock() async {
    if (!_multicastLockHeld) return;
    _multicastLockHeld = false;
    try {
      await _multicastChannel.invokeMethod<void>('release');
    } catch (error) {
      debugPrint('Could not release Android Wi-Fi multicast lock: $error');
    }
  }

  Future<void> dispose() async {
    _udp?.close();
    await _releaseMulticastLock();
    await _controller.close();
    _udp = null;
  }
}
