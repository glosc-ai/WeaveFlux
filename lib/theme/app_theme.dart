import 'package:flutter/material.dart';

/// WeaveFlux 全局设计令牌。
///
/// 来源：design_handoff/weaveflux-core.css
abstract final class AppColors {
  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color foreground = Color(0xFFF8FAFC);
  static const Color muted = Color(0xFF94A3B8);
  static const Color border = Color(0xFF334155);
  static const Color primaryAccent = Color(0xFF10B981);
  static const Color secondaryAccent = Color(0xFF3B82F6);
  static const Color danger = Color(0xFFEF4444);
}

abstract final class AppRadii {
  static const double card = 16;
  static const double button = 12;
  static const double input = 8;

  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get buttonRadius => BorderRadius.circular(button);
  static BorderRadius get inputRadius => BorderRadius.circular(input);
}

abstract final class AppSpacing {
  static const double screenX = 20;
  static const double contentBottom = 16;
  static const double statusTop = 14;
  static const double statusX = 24;
}

abstract final class AppTheme {
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryAccent,
      brightness: Brightness.dark,
      primary: AppColors.primaryAccent,
      secondary: AppColors.secondaryAccent,
      surface: AppColors.surface,
      error: AppColors.danger,
    ).copyWith(
      onSurface: AppColors.foreground,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      textTheme: _textTheme,
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: const BorderSide(
            color: AppColors.secondaryAccent,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: const BorderSide(
            color: AppColors.danger,
            width: 2,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primaryAccent,
        inactiveTrackColor: AppColors.border,
        thumbColor: AppColors.primaryAccent,
        overlayColor: AppColors.primaryAccent.withValues(alpha: 0.16),
        valueIndicatorColor: AppColors.surface,
        valueIndicatorTextStyle: const TextStyle(
          color: AppColors.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryAccent,
          foregroundColor: AppColors.foreground,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.buttonRadius,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.foreground,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.buttonRadius,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    headlineSmall: TextStyle(
      color: AppColors.foreground,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.2,
    ),
    titleMedium: TextStyle(
      color: AppColors.foreground,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.25,
    ),
    bodyLarge: TextStyle(
      color: AppColors.foreground,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      color: AppColors.foreground,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.4,
    ),
    bodySmall: TextStyle(
      color: AppColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.35,
    ),
    labelSmall: TextStyle(
      color: AppColors.muted,
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      height: 1.2,
    ),
  );
}
