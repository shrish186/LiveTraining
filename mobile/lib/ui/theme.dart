import 'package:flutter/material.dart';

/// Design tokens. Dark, high-contrast, numbers first: one accent per metric.
abstract final class AppColors {
  // Ink blue, not black or grey: our own look. Cards are layers of the same blue, lifted by light.
  static const background = Color(0xFF0A1019);
  static const backgroundTop = Color(0xFF13213A);
  static const surface = Color(0xFF131C2A);
  static const surfaceHigh = Color(0xFF1B2638);
  static const outline = Color(0xFF26344A);
  static const text = Color(0xFFEEF2F8);
  static const textDim = Color(0xFF93A2B8);
  static const textFaint = Color(0xFF5E6D84);

  /// Brand: electric lime. The record button, the readiness gauge, primary actions.
  static const brand = Color(0xFFC6F35E);
  static const onBrand = Color(0xFF0A1019);

  static const accent = Color(0xFF4CC3FF); // information, motion
  static const heart = Color(0xFFFF5C8A); // heart rate
  static const load = Color(0xFF8B7CFF); // load
  static const danger = Color(0xFFFF5C6C); // alerts
  static const warning = Color(0xFFFFB547); // caution
  static const good = Color(0xFF5EE6A8); // fine / held up

  /// Recovery bands (high / medium / low).
  static Color recovery(double score) => score >= 67
      ? good
      : score >= 34
      ? warning
      : danger;
}

abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Small spaced-out caps label above every metric.
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: AppColors.textDim,
  );

  /// Card and section titles: bold, sentence case.
  static const section = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    letterSpacing: -0.1,
  );
  static const hero = TextStyle(
    fontSize: 64,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: -2,
    color: AppColors.text,
    fontFeatures: _tabular,
  );
  static const big = TextStyle(
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    color: AppColors.text,
    fontFeatures: _tabular,
  );
  static const stat = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    fontFeatures: _tabular,
  );
  static const unit = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim, letterSpacing: 1);
  static const title = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.5);
  static const body = TextStyle(fontSize: 15, color: AppColors.text, height: 1.35);
  static const dim = TextStyle(fontSize: 13, color: AppColors.textDim, height: 1.35);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: Brightness.dark).copyWith(
    primary: AppColors.brand,
    onPrimary: AppColors.onBrand,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.outline,
  );
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
  // Derive from the platform text theme so buttons keep the system font family.
  final baseText = ThemeData.dark().textTheme;
  final buttonText = baseText.labelLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    dividerColor: AppColors.outline,
    textTheme: baseText.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: pill, minimumSize: const Size(0, 52), textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        minimumSize: const Size(0, 48),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.outline),
        textStyle: buttonText.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.accent)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      labelStyle: const TextStyle(color: AppColors.textDim),
      helperStyle: const TextStyle(color: AppColors.textFaint, fontSize: 12),
      helperMaxLines: 2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.surfaceHigh,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.textFaint,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) =>
            IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textFaint),
      ),
    ),
  );
}
