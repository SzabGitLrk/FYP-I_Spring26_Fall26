import 'package:flutter/material.dart';

/// EYRIS Design System
///
/// Central place for all colors, spacing, text styles, and component styles.
/// Import this everywhere instead of hardcoding colors:
///   import '../theme/app_theme.dart';
/// Then use: AppColors.background, AppText.heading, AppSpacing.md, etc.

class AppColors {
  AppColors._();

  // Core backgrounds
  static const Color background = Color(0xFF0A0F1E); // deep navy
  static const Color surface = Color(0xFF121A2F); // card navy
  static const Color surfaceLight = Color(0xFF1B2540); // elevated card
  static const Color surfaceBorder = Color(0x1AFFFFFF); // white @ 10%

  // Brand / accent
  static const Color primary = Color(0xFF3B82F6); // blue
  static const Color primaryDark = Color(0xFF2563EB);
  static const Color accent = Color(0xFF6366F1); // indigo

  // Semantic
  static const Color success = Color(0xFF36D399); // green
  static const Color warning = Color(0xFFFFC857); // amber
  static const Color danger = Color(0xFFFF5C6C); // red
  static const Color info = Color(0xFF38BDF8); // sky

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9); // near-white
  static const Color textSecondary = Color(0xFF94A3B8); // slate
  static const Color textMuted = Color(0xFF64748B); // dim slate

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0A0F1E), Color(0xFF0D1428)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

class AppText {
  AppText._();

  static const TextStyle display = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 34,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
  );

  static const TextStyle heading = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle subheading = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySecondary = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 14,
  );

  static const TextStyle label = TextStyle(
    color: AppColors.textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle button = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );
}

/// Reusable decorations
class AppDecorations {
  AppDecorations._();

  static BoxDecoration card = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: AppColors.surfaceBorder),
  );

  static BoxDecoration cardElevated = BoxDecoration(
    color: AppColors.surfaceLight,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: AppColors.surfaceBorder),
    boxShadow: const [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration pill(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      );
}

/// Global ThemeData used by MaterialApp.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppText.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
