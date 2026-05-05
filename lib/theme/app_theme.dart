import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF03070F);
  static const surface = Color(0xFF050E1C);
  static const card = Color(0xFF0A1828);
  static const cardHover = Color(0xFF0D1E30);

  static const accent = Color(0xFF5B9DFF);
  static const accentDim = Color(0x335B9DFF);
  static const accentDimHover = Color(0x595B9DFF);

  static const textPrimary = Color(0xFFE8EEF8);
  static const textSecondary = Color(0xC7E8EEF8);
  static const textTertiary = Color(0x8CE8EEF8);

  static const danger = Color(0xFFFF4D4D);
  static const dangerDim = Color(0x2EFF4D4D);
  static const warning = Color(0xFFFFB830);
  static const warningDim = Color(0x2EFFB830);
  static const success = Color(0xFF3DCC7E);
  static const successDim = Color(0x2E3DCC7E);

  static const borderSubtle = Color(0x1F5B9DFF);
  static const borderFocus = accent;

  static const inputBackground = card;
  static const inputBorder = Color(0x545B9DFF);
  static const placeholder = Color(0x59E8EEF8);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.accent,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.surface,
          primary: AppColors.accent,
          secondary: AppColors.accent,
          error: AppColors.danger,
          onPrimary: AppColors.background,
          onSurface: AppColors.textPrimary,
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      );
}
