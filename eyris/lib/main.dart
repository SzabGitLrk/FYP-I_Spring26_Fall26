import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/alerts_screen.dart';   // ✅ Import AlertsScreen for navigation
import 'package:flutter/services.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('login') ?? false;
  
  runApp(EyrisApp(isLoggedIn: isLoggedIn));
}

class EyrisApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const EyrisApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EYRIS',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0A0F1E),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
      // ✅ Optional: Named routes for direct navigation
      routes: {
        '/alerts': (context) => const AlertsScreen(),
      },
    );
  }
}

class GraphService {
  static const platform = MethodChannel('graphhopper_channel');

  static Future initGraph() async {
    return await platform.invokeMethod("initGraph");
  }

  static Future<List> getRoute() async {
    final result = await platform.invokeMethod("getRoute", {
      "startLat": 24.8607,
      "startLng": 67.0011,
      "endLat": 24.8820,
      "endLng": 67.0670,
    });

    return result;
  }
}
