import 'package:shared_preferences/shared_preferences.dart';

class CameraSettings {
  final Uri streamUri;
  final bool usePhoneCamera;

  CameraSettings({required this.streamUri, this.usePhoneCamera = false});

  String get cameraIp => streamUri.host;

  /// Builds the standard Arduino CameraWebServer endpoint for an IPv4 address.
  static CameraSettings fromIp(String value, {bool usePhoneCamera = false}) =>
      CameraSettings(
          streamUri: streamUriForIp(value), usePhoneCamera: usePhoneCamera);

  static Uri streamUriForIp(String value) {
    final ip = value.trim();
    final octets = ip.split('.');
    if (octets.length != 4 ||
        octets.any((octet) {
          final number = int.tryParse(octet);
          return octet.isEmpty ||
              !RegExp(r'^\d{1,3}$').hasMatch(octet) ||
              number == null ||
              number > 255;
        })) {
      throw const FormatException(
          'Enter a valid IPv4 address, for example 192.168.43.204.');
    }
    return Uri(scheme: 'http', host: ip, port: 81, path: '/stream');
  }

  /// Accept a hotspot IP, a camera base URL, or a complete stream URL.
  static Uri parseAddress(String value) {
    final text = value.trim();
    if (text.isEmpty || RegExp(r'\s').hasMatch(text)) {
      throw const FormatException('Enter a camera IP or HTTP stream URL.');
    }
    final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('Enter a valid HTTP camera address.');
    }
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(port: uri.hasPort ? uri.port : 81, path: '/stream');
    }
    return uri;
  }

  Uri get statusUri => Uri(
      scheme: streamUri.scheme,
      host: streamUri.host,
      port: streamUri.scheme == 'https' ? 443 : 80,
      path: '/status');

  static Future<CameraSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('camera_ip');
    final savedStreamUrl = prefs.getString('camera_stream_url');
    if (savedIp == null && savedStreamUrl == null) {
      throw const FormatException(
          'ESP32 camera IP is not configured. Open Camera settings and enter the current IP shown in Serial Monitor.');
    }
    return CameraSettings(
      streamUri: savedIp == null
          ? parseAddress(savedStreamUrl!)
          : streamUriForIp(savedIp),
      usePhoneCamera: prefs.getBool('camera_use_phone') ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('camera_stream_url', streamUri.toString()) ||
        !await prefs.setString('camera_ip', cameraIp) ||
        !await prefs.setBool('camera_use_phone', usePhoneCamera)) {
      throw StateError('Could not save camera settings.');
    }
  }
}
