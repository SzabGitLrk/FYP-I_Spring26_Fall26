import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryPurple = Color(0xFF7B1FA2);
  static const Color accentOrange = Color(0xFFFF9800);

  static const Color firstStopGreen = Color(0xFF4CAF50);
  static const Color intermediateBlue = Color(0xFF2196F3);
  static const Color lastStopRed = Color(0xFFF44336);
  static const Color movingBusAzure = Color(0xFF00BCD4);
  static const Color stoppedBusViolet = Color(0xFF9C27B0);
  static const Color busActiveGreen = Color(0xFF4CAF50);

  static const Color sosRed = Color(0xFFD32F2F);
  static const Color warningOrange = Color(0xFFFF9800);

  static ThemeData studentTheme = ThemeData(
    primarySwatch: Colors.blue,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      elevation: 4,
      centerTitle: true,
      backgroundColor: primaryBlue,
      foregroundColor: Colors.white,
    ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  static ThemeData driverTheme = ThemeData(
    primarySwatch: Colors.green,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      elevation: 4,
      centerTitle: true,
      backgroundColor: primaryGreen,
      foregroundColor: Colors.white,
    ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  static ThemeData adminTheme = ThemeData(
    primarySwatch: Colors.purple,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      elevation: 4,
      centerTitle: true,
      backgroundColor: primaryPurple,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
  );
}
