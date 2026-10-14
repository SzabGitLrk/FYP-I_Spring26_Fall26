import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Function(Map<String, dynamic>)? onNotificationOpened;

  /// True only after [initialize] succeeded on a platform that can actually
  /// deliver notifications. [ensurePermission] consults this so a toggle never
  /// claims an alert is armed on web/desktop or when init failed.
  bool _initialized = false;

  /// True on platforms that ship a real notifications implementation here
  /// (Android / iOS / macOS / Linux). Web is excluded (main.dart skips init),
  /// and Windows has no registered plugin instance in this project, so calling
  /// into it would hit an unset `static late` platform instance and throw.
  static bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  void _dispatchPayload(String? payload) {
    if (payload == null || onNotificationOpened == null) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload));
      onNotificationOpened!(data);
    } catch (e) {
      // Never silently drop a tap: at least leave a trace to debug by.
      debugPrint('[notif] bad payload: $e');
    }
  }

  Future<void> initialize() async {
    if (!_supportedPlatform) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    // flutter_local_notifications throws if macOS/Linux are targeted without
    // their settings; the project ships macos/ and linux/ folders, so supply
    // them rather than letting init throw (main.dart swallows that throw and
    // notifications would silently never work there).
    const macSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) =>
          _dispatchPayload(response.payload),
    );

    // Handle a tap that COLD-STARTED the app: onDidReceiveNotificationResponse
    // only fires while the app is running, so without this the payload of a
    // tap that launched the app from terminated was discarded.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.didNotificationLaunchApp == true
          ? launch?.notificationResponse?.payload
          : null;
      if (payload != null) {
        // Defer to the next frame so any screen that assigns
        // onNotificationOpened has had a chance to register.
        WidgetsBinding.instance.addPostFrameCallback((_) => _dispatchPayload(payload));
      }
    } catch (e) {
      debugPrint('[notif] launch-details lookup failed: $e');
    }

    await _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

    _initialized = true;
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
    // No plugin implementation exists on web / Windows here, and init is a
    // no-op there - returning true would arm an alert that can never fire.
    if (!_supportedPlatform || !_initialized) return false;
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

      // macOS / Linux use the Darwin/Linux permission model; the platform
      // instance exists there (we supplied settings above). Treat "resolved
      // some other implementation" as not verifiable rather than claiming it.
      return false;
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
    if (!_supportedPlatform) return;
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

    try {
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
    } catch (e) {
      // Callers are fire-and-forget (map_screen); an unhandled async throw
      // here would surface as a zone error. Log instead of crashing.
      debugPrint('[notif] bus-arrival show failed: $e');
    }
  }

  Future<void> showSOSNotification() async {
    // Same platform guard as ensurePermission/showBusArrivalNotification:
    // the unawaited calls from map_screen/driver_dashboard would otherwise
    // raise an unhandled MissingPluginException on web.
    if (!_supportedPlatform) return;
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

    try {
      await _plugin.show(
        999,
        '🆘 SOS Alert Sent!',
        'Help is on the way. Your location has been shared.',
        details,
      );
    } catch (e) {
      debugPrint('[notif] sos show failed: $e');
    }
  }
}