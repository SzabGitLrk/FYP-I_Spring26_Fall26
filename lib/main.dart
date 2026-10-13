import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:university_point_locator/screens/role_router.dart';
import 'package:university_point_locator/services/notification_service.dart';
import 'package:university_point_locator/screens/student/profile_screen.dart';
import 'package:university_point_locator/screens/driver/trip_history.dart';
import 'package:university_point_locator/config/app_config.dart';
import 'package:university_point_locator/utils/app_theme.dart';

// Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Driver trip tracking runs a location-typed foreground service; register
  // the plugin's isolate port before any screen can start the service.
  FlutterForegroundTask.initCommunicationPort();
  debugPrint('🚀 Starting app...');

  var initialized = false;
  try {
    // Initialize Supabase with PKCE for better security
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    initialized = true;
    debugPrint('✅ Supabase initialized!');
  } catch (e) {
    debugPrint('❌ Initialization error: $e');
  }

  if (initialized) {
    // Own try/catch: a notification-plugin failure must not skip the auth
    // listener below (it used to, silently leaving taps unhandled).
    // Initialize local notifications (mobile only) AFTER the first frame:
    // initialize() awaits the Android 13+ POST_NOTIFICATIONS prompt, and
    // awaiting that inside main() held the whole UI behind the static
    // launch window until the user answered. Arming a specific alert is
    // still gated by NotificationService.ensurePermission at each site.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!kIsWeb) {
          await NotificationService().initialize();
          debugPrint('✅ Local notifications initialized!');
        } else {
          debugPrint('🌐 Web detected - skipping notifications');
        }
      } catch (e) {
        debugPrint('❌ Notification init failed: $e');
      }
    });

    // Optional: Listen to auth changes for debugging
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        final session = data.session;
        if (session != null) {
          // No PII in logs: debugPrint is NOT stripped in release builds, and
          // every e-mail here was readable by anyone plugging in a phone.
          // The user id correlates just as well.
          debugPrint('🔐 Auth: ${data.event} - User: ${session.user.id}');
        } else {
          debugPrint('🔐 Auth: ${data.event} - No session');
        }
      },
      // gotrue pushes auth failures (token refresh, network) onto this same
      // stream; without a handler every refresh failure became an unhandled
      // async exception in release.
      onError: (Object e) => debugPrint('🔐 Auth stream error: $e'),
    );
  }

  runApp(MyApp(canStart: initialized));
}

/// Shown when Supabase could not initialize (storage failure, corrupt
/// persisted session). RoleRouter's first statement would otherwise throw
/// an unhandled SupabaseException: a white screen with no explanation.
class _StartupFailedScreen extends StatelessWidget {
  const _StartupFailedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Could not start: unable to reach the server.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => main(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.canStart = true});

  /// False when [Supabase.initialize] failed: rendering [RoleRouter] would
  /// throw on its first line, so the app starts into a retry screen instead.
  final bool canStart;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'University Point Locator - Larkana',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // For notifications
      theme: AppTheme.light,
      home: canStart ? const RoleRouter() : const _StartupFailedScreen(),
      routes: {
        '/profile': (context) => const ProfileScreen(),
        '/history': (context) => const TripHistory(),
        // Add more routes as needed
        // '/driver/trips': (context) => const DriverTripsScreen(),
        // '/admin': (context) => const AdminDashboard(),
      },
    );
  }
}
