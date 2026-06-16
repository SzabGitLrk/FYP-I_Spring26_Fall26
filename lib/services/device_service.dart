import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceService {
  final SupabaseClient _client = Supabase.instance.client;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<String> getDeviceId() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return androidInfo.id;
    } else {
      final iosInfo = await _deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? '';
    }
  }

  Future<void> registerDevice(String userId) async {
    final deviceId = await getDeviceId();
    if (deviceId.isEmpty) return;

    final existing = await _client
        .from('user_devices')
        .select()
        .eq('device_id', deviceId)
        .maybeSingle();

    final now = DateTime.now().toIso8601String();
    final email = _client.auth.currentUser?.email ?? '';

    if (existing != null) {
      await _client
          .from('user_devices')
          .update({
            'user_id': userId,
            'last_seen': now,
            'email': email,
          })
          .eq('device_id', deviceId);
    } else {
      await _client.from('user_devices').insert({
        'user_id': userId,
        'device_id': deviceId,
        'onesignal_id': deviceId,
        'email': email,
        'last_seen': now,
      });
    }
  }

  Future<bool> verifyDevice(String userId) async {
    final deviceId = await getDeviceId();

    final response = await _client
        .from('user_devices')
        .select()
        .eq('user_id', userId)
        .eq('device_id', deviceId)
        .maybeSingle();

    return response != null;
  }
}
