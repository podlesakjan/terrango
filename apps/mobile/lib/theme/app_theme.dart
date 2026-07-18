import 'package:flutter/material.dart';

class TerrangoTheme {
  static ThemeData dark() {
    const seed = Color(0xFF4FC3F7);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF0C1220),
      background: const Color(0xFF08101E),
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF08101E),
      useMaterial3: true,
      textTheme: Typography.whiteMountainView,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0E1729),
        indicatorColor: seed.withValues(alpha: 0.22),
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF121A2B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.15)),
      ),
    );
  }
}

