import 'package:flutter/material.dart';
import '../services/camera_settings.dart';

Future<CameraSettings?> showCameraSettings(BuildContext context) =>
    showDialog<CameraSettings>(
        context: context, builder: (_) => const _CameraSettingsDialog());

class _CameraSettingsDialog extends StatefulWidget {
  const _CameraSettingsDialog();
  @override
  State<_CameraSettingsDialog> createState() => _CameraSettingsDialogState();
}

class _CameraSettingsDialogState extends State<_CameraSettingsDialog> {
  final _ip = TextEditingController();
  bool _phone = false;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await CameraSettings.load();
      if (!mounted) return;
      _ip.text = settings.cameraIp;
      setState(() {
        _phone = settings.usePhoneCamera;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      _ip.clear();
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      final settings = CameraSettings.fromIp(_ip.text, usePhoneCamera: _phone);
      setState(() => _loading = true);
      await settings.save();
      if (mounted) Navigator.pop(context, settings);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is FormatException
              ? error.message
              : 'Could not save camera settings.';
        });
      }
    }
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Camera settings'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use phone camera'),
              value: _phone,
              onChanged:
                  _loading ? null : (value) => setState(() => _phone = value)),
          TextField(
              controller: _ip,
              enabled: !_loading,
              keyboardType: TextInputType.number,
              autocorrect: false,
              decoration: InputDecoration(
                  labelText: 'ESP32 camera IP address',
                  hintText: '192.168.43.204',
                  helperText: 'Stream: http://<IP>:81/stream',
                  errorText: _error)),
          const SizedBox(height: 12),
          const Text(
              'Keep the phone and ESP32 on the same Wi-Fi or phone hotspot. Apply the new IP after the camera reconnects.'),
        ])),
        actions: [
          TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: _loading ? null : _save,
              child: Text(_loading ? 'Loading...' : 'Apply')),
        ],
      );
}
