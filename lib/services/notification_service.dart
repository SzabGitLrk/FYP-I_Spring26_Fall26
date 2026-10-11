import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Function(Map<String, dynamic>)? onNotificationOpened;

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && onNotificationOpened != null) {
          try {
            final data = Map<String, dynamic>.from(
              jsonDecode(response.payload!),
            );
            onNotificationOpened!(data);
          } catch (e) {
            // Never silently drop a tap: at least leave a trace to debug by.
            debugPrint('[notif] bad payload: $e');
          }
        }
      },
    );

    await _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  /// Verifies that the OS will actually deliver this app's notifications,
  /// requesting the permission first if it has never been asked for.
  ///
  /// Returns true when notifications can be shown, false when the user has
  /// blocked them (or the status could not be verified). Callers MUST NOT
  /// persist an alert subscription when this returns false - the UI would
  /// claim an alert is armed that can never fire.
  ///
  /// Additive on purpose: [initialize], [showBusArrivalNotification] and
  /// [showSOSNotification] keep their existing signatures for other screens.
  Future<bool> ensurePermission() async {
    // No plugin implementation exists on web (main.dart skips init there).
    if (kIsWeb) return true;
    try {
      // resolvePlatformSpecificImplementation matches on the target platform,
      // so a null here simply means "not this OS" - no dart:io import needed.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final enabled = await android.areNotificationsEnabled();
        if (enabled == true) return true;
        final granted = await android.requestNotificationsPermission();
        if (granted != true) {
          debugPrint(
            '[notif] android notifications blocked '
            '(enabled: $enabled, granted: $granted)',
          );
        }
        return granted == true;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final permissions = await ios.checkPermissions();
        if (permissions?.isEnabled == true) return true;
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted != true) {
          debugPrint('[notif] ios notifications blocked (granted: $granted)');
        }
        return granted == true;
      }

      // Desktop / unsupported platform: no OS permission model to consult.
      return true;
    } catch (e) {
      // Never crash a toggle over the permission probe - but also never claim
      // a permission that could not be verified.
      debugPrint('[notif] permission check failed: $e');
      return false;
    }
  }

  Future<void> showBusArrivalNotification({
    required String stopName,
    required int etaMinutes,
    required int stopId,
    required int routeId,
    int busId = 0,
  }) async {
    // No plugin implementation exists on web (main.dart skips init there);
    // calling anyway would raise an unhandled MissingPluginException.
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'bus_arrival',
      'Bus Arrival Alerts',
      channelDescription: 'Notifications when a bus is approaching your stop',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      // stopId*1000+busId: Android keeps one slot per id, so the old
      // stopId-only id made a second bus's alert REPLACE the first one
      // instead of stacking. Stays far below 2^31 for realistic ids.
      stopId * 1000 + busId,
      '🚌 Bus approaching $stopName',
      etaMinutes == 0
          ? 'The bus is at the stop now'
          : 'Arriving in approximately $etaMinutes minutes',
      details,
      payload: '{"stop_id":$stopId,"route_id":$routeId}',
    );
  }

  Future<void> showSOSNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'sos_alerts',
      'SOS Emergency Alerts',
      channelDescription: 'Emergency SOS alerts',
      importance: Importance.high,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      999,
      '🆘 SOS Alert Sent!',
      'Help is on the way. Your location has been shared.',
      details,
    );
  }
}