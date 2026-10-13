import 'package:flutter/material.dart';
// Scoped import: `CupertinoPageTransitionsBuilder` (a smooth slide transition
// that reads well on both platforms) is defined in cupertino/route.dart and is
// not re-exported by material.dart. `show` avoids any material/cupertino clash.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

/// Central Material 3 design system for the whole app.
///
/// Every screen pulls its colors, typography, and component shapes from here
/// so the product reads as one cohesive app instead of per-screen styling.
/// Role accent colors (student blue / driver green / admin purple) are applied
/// by each screen's own `AppBar`; everything else — buttons, inputs, cards,
/// dialogs, snackbars, chips, page transitions — derives from a single seeded
/// [ColorScheme], which is what gives the app a consistent, modern "SaaS" feel.
class AppTheme {
  AppTheme._();

  // ---- Brand palette -------------------------------------------------
  static const Color seed = Color(0xFF1565C0); // brand blue
  static const Color primaryBlue = seed;
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryPurple = Color(0xFF7B1FA2);
  static const Color accentOrange = Color(0xFFFF9800);

  // ---- Semantic / domain colors (map markers, statuses, SOS) ---------
  static const Color firstStopGreen = Color(0xFF4CAF50);
  static const Color intermediateBlue = Color(0xFF2196F3);
  static const Color lastStopRed = Color(0xFFF44336);
  static const Color movingBusAzure = Color(0xFF00BCD4);
  static const Color stoppedBusViolet = Color(0xFF9C27B0);
  static const Color busActiveGreen = Color(0xFF4CAF50);
  static const Color sosRed = Color(0xFFD32F2F);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color successGreen = Color(0xFF2E7D32);

  // ---- Shape & spacing scale -----------------------------------------
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  /// Standard vertical rhythm between cards / form fields.
  static const double gap = 12;

  /// Shared, smooth page transition (shared-axis style) used app-wide so
  /// navigation never feels like the default jarring Material push.
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  );

  /// The single light theme. Built from [seed] so every tonal color (surface,
  /// primary, container, outline) is derived automatically and stays in sync.
  static ThemeData get light {
    final ColorScheme scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final bool isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      pageTransitionsTheme: _pageTransitions,
      splashFactory: InkRipple.splashFactory,

      // ---- Typography: a clean, readable scale -----------------------
      textTheme: _textTheme(scheme),

      // ---- App bar: flat M3 surface, role-tinted by each screen ------
      appBarTheme: AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      // ---- Cards: soft, rounded, low elevation -----------------------
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),

      // ---- Primary (filled) buttons -----------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      // ---- Secondary (outlined) buttons -------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      // ---- Tertiary (text) buttons ------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      // ---- Filled tonal button (used for neutral actions) -------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      // ---- Text fields: filled, rounded, floating labels --------------
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.error),
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      // ---- Chips ------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        labelStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // ---- Dialogs ----------------------------------------------------
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
      ),

      // ---- Floating action buttons -------------------------------------
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),

      // ---- Bottom sheets -----------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        showDragHandle: true,
      ),

      // ---- Snackbars: floating, rounded, readable ----------------------
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(fontSize: 14, color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        elevation: 2,
      ),

      // ---- Popup menus -------------------------------------------------
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),

      // ---- Dividers / progress / sliders -------------------------------
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        trackHeight: 4,
      ),

      // ---- Tabs (M3 pill indicator) ------------------------------------
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onPrimary.withValues(alpha: 0.7),
        indicatorColor: scheme.onPrimary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),

      // ---- List tiles ---------------------------------------------------
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // ---- Misc ----------------------------------------------------------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  /// A clean, slightly tightened type scale on top of the M3 defaults.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true).textTheme;
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(color: scheme.onSurface, height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(color: scheme.onSurface, height: 1.4),
      bodySmall: base.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(letterSpacing: 0.3),
    );
  }
}
