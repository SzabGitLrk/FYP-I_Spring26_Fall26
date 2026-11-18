import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/alerts_screen.dart';
import 'services/camera_route_observer.dart';

void main() {
  // Both ensureInitialized AND runApp must run in the SAME zone, otherwise
  // BindingBase.debugCheckZone throws "Zone mismatch" (seen on Pixel 7a).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('login') ?? false;
    runApp(EyrisApp(isLoggedIn: isLoggedIn));
  }, (error, stack) {
    debugPrint('[Global] Unhandled exception: $error');
    debugPrint('[Global] Stack: $stack');
    // Silently log to prevent crashes from propagating
  });
}

class EyrisApp extends StatelessWidget {
  final bool isLoggedIn;

  const EyrisApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EYRIS',
      navigatorObservers: [cameraRouteObserver],
      theme: AppTheme.dark,
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
      routes: {
        '/alerts': (context) => const AlertsScreen(),
      },
    );
  }
}
