//main controller of flutter app,app start, Firebase, deep linking and navigation,offline map setup,app theme design
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'screens/splash_screen.dart';
import 'screens/tracking.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline Map Cache Initialize
  await FMTCObjectBoxBackend().initialise();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase Init Error: $e");
  }

  runApp(const ZaviraApp());
}

class ZaviraApp extends StatefulWidget {
  const ZaviraApp({super.key});

  @override
  State<ZaviraApp> createState() => _ZaviraAppState();
}

class _ZaviraAppState extends State<ZaviraApp> {

  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    initDeepLinks();
  }

  void initDeepLinks() async {

    // App opened from link
    final uri = await _appLinks.getInitialAppLink();
    if (uri != null) {
      handleLink(uri);
    }

    //  While app running
    _appLinks.uriLinkStream.listen((uri) {
      handleLink(uri);
    });
  }

  void handleLink(Uri uri) {
    if (uri.scheme == "zavira" && uri.host == "track") {

      double lat = double.parse(uri.queryParameters["lat"]!);
      double lng = double.parse(uri.queryParameters["lng"]!);

      Navigator.push(
        navigatorKey.currentContext!,
        MaterialPageRoute(
          builder: (_) => TrackingScreen(lat: lat, lng: lng),
        ),
      );
    }
  }

  final GlobalKey<NavigatorState> navigatorKey =
  GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Zavira',

      theme: ThemeData(
        primaryColor: const Color(0xFF395058),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF395058),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F4F1),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF395058),
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF395058),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),

      home: const SplashScreen(),
    );
  }
}