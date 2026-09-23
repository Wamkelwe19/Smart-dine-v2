import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// The application theme.
///
/// Previously `ThemeData` was three lines seeded from `deepPurple` that nothing
/// honoured — every screen hardcoded its own colours, and the seed leaked out
/// only as purple ripples on unstyled buttons and a purple login hover state.
/// Screens should now take their colours from `Theme.of(context).colorScheme`
/// rather than naming a colour directly.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.darkPrimary,
            onPrimary: AppColors.onDarkPrimary,
            primaryContainer: AppColors.primaryDark,
            onPrimaryContainer: AppColors.brandPale,
            secondary: AppColors.secondaryContainer,
            onSecondary: AppColors.onSecondaryContainer,
            surface: AppColors.darkSurface,
            onSurface: AppColors.darkTextPrimary,
            error: AppColors.dangerContainer,
            onError: AppColors.onDangerContainer,
            outline: AppColors.darkOutline,
          )
        : const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.onPrimary,
            primaryContainer: AppColors.primaryContainer,
            onPrimaryContainer: AppColors.onPrimaryContainer,
            secondary: AppColors.secondary,
            onSecondary: AppColors.onSecondary,
            secondaryContainer: AppColors.secondaryContainer,
            onSecondaryContainer: AppColors.onSecondaryContainer,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            error: AppColors.danger,
            onError: AppColors.onPrimary,
            errorContainer: AppColors.dangerContainer,
            onErrorContainer: AppColors.onDangerContainer,
            outline: AppColors.outline,
          );

    final baseText = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;

    // Quicksand is the established brand face. This scale replaces the thirteen
    // ad-hoc font sizes the old screens used.
    final textTheme = GoogleFonts.quicksandTextTheme(baseText).copyWith(
      displaySmall: GoogleFonts.quicksand(
          fontSize: 32, fontWeight: FontWeight.w700, height: 1.2),
      headlineMedium: GoogleFonts.quicksand(
          fontSize: 26, fontWeight: FontWeight.w700, height: 1.25),
      headlineSmall: GoogleFonts.quicksand(
          fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
      titleLarge: GoogleFonts.quicksand(
          fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
      titleMedium: GoogleFonts.quicksand(
          fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      titleSmall: GoogleFonts.quicksand(
          fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
      bodyLarge: GoogleFonts.quicksand(
          fontSize: 16, fontWeight: FontWeight.w500, height: 1.5),
      bodyMedium: GoogleFonts.quicksand(
          fontSize: 14, fontWeight: FontWeight.w500, height: 1.5),
      bodySmall: GoogleFonts.quicksand(
          fontSize: 12, fontWeight: FontWeight.w500, height: 1.45),
      labelLarge: GoogleFonts.quicksand(
          fontSize: 15, fontWeight: FontWeight.w700, height: 1.2),
      labelMedium: GoogleFonts.quicksand(
          fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
      labelSmall: GoogleFonts.quicksand(
          fontSize: 11, fontWeight: FontWeight.w600, height: 1.2),
    );

    final surfaceMuted =
        isDark ? AppColors.darkSurfaceMuted : AppColors.surfaceMuted;
    final mutedText =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.background,
      dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: AppElevation.none,
        scrolledUnderElevation: AppElevation.card,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: AppElevation.card,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        clipBehavior: Clip.antiAlias,
      ),

      // Every button style below meets the 48dp minimum (REQ-125).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(AppA11y.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          elevation: AppElevation.none,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppA11y.minTouchTarget),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(AppA11y.minTouchTarget),
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize:
              const Size(AppA11y.minTouchTarget, AppA11y.minTouchTarget),
          textStyle: textTheme.labelMedium,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: AppA11y.minTouchSize,
          foregroundColor: scheme.onSurface,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: mutedText),
        hintStyle: textTheme.bodyMedium?.copyWith(color: mutedText),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.darkSurfaceMuted : const Color(0xFF322F2B),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs)),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape:
            const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
        showDragHandle: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        elevation: AppElevation.sheet,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        labelStyle: textTheme.labelMedium,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
        side: BorderSide.none,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: mutedText,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
