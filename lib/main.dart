import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:university_point_locator/screens/role_router.dart';
import 'package:university_point_locator/services/notification_service.dart';
import 'package:university_point_locator/screens/student/profile_screen.dart';
import 'package:university_point_locator/screens/driver/trip_history.dart';
import 'package:university_point_locator/config/app_config.dart';

// Global navigator key for notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 Starting app...');

  try {
    // Initialize Supabase with PKCE for better security
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    debugPrint('✅ Supabase initialized!');

    // Initialize local notifications (mobile only)
    if (!kIsWeb) {
      final notificationService = NotificationService();
      await notificationService.initialize();
      debugPrint('✅ Local notifications initialized!');
    } else {
      debugPrint('🌐 Web detected - skipping notifications');
    }

    // Optional: Listen to auth changes for debugging
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        debugPrint('🔐 Auth: ${data.event} - User: ${session.user.email}');
      } else {
        debugPrint('🔐 Auth: ${data.event} - No session');
      }
    });
  } catch (e) {
    debugPrint('❌ Initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'University Point Locator - Larkana',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // For notifications
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(elevation: 4, centerTitle: true),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const RoleRouter(), // Clean role-based routing
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
