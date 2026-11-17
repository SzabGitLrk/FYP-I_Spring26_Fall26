import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android battery-optimisation exemption for THIS app - the missing piece
/// behind every "the bus stopped updating mid-drive" field report. Android
/// Doze (and the OEM battery killers layered on top of it, e.g. Realme)
/// freezes the driver's foreground-service GPS stream mid-trip unless the
/// app sits on the battery-optimisation allowlist, and nothing in the
/// system UI ever surfaces that to the driver.
///
/// Non-Android platforms report exempt (`true`) so they can never show a
/// banner or dialog that does not apply to them.
class BatteryOptimization {
  BatteryOptimization._();

  static const MethodChannel _channel =
      MethodChannel('com.example.university_point_locator/battery');

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// Whether Android currently leaves this app's background work alone.
  ///
  /// An unknown state (channel error on an odd OEM build) reports exempt,
  /// not deficient: the goal is reliable tracking, not an immortal banner
  /// the driver cannot clear. Real devices implement the check correctly.
  static Future<bool> isExempt() async {
    if (!_android) return true;
    try {
      final ignoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ignoring ?? true;
    } on PlatformException catch (e) {
      debugPrint('[battery] exemption check failed: $e');
      return true;
    } on MissingPluginException catch (e) {
      debugPrint('[battery] channel not registered: $e');
      return true;
    }
  }

  /// Opens the system exemption dialog, falling back (natively) to the
  /// allowlist settings screen. Returns false when the device offered
  /// neither - the caller keeps its hint up in that case.
  static Future<bool> requestExemption() async {
    if (!_android) return false;
    try {
      final opened =
          await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return opened ?? false;
    } on PlatformException catch (e) {
      debugPrint('[battery] exemption request failed: $e');
      return false;
    } on MissingPluginException catch (e) {
      debugPrint('[battery] channel not registered: $e');
      return false;
    }
  }
}
