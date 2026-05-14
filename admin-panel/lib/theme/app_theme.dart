import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

class AdminAppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.info,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.outfit(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        height: 1.05,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        height: 1.1,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: AppColors.text,
        height: 1.55,
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        color: AppColors.text,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        color: AppColors.textMuted,
        height: 1.45,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      dividerColor: AppColors.divider,
      cardColor: AppColors.surface,
      canvasColor: AppColors.background,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.text),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textSoft),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: AppRadius.sm,
          border: Border.all(color: AppColors.border),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.text),
        waitDuration: const Duration(milliseconds: 250),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.surfaceSoft;
        }),
      ),
    );
  }
}

