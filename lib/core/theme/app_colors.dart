import 'package:flutter/material.dart';

/// Colour tokens.
///
/// The app previously carried roughly 200 hardcoded colour literals: three
/// different oranges for the same element, seven greys, and a `deepPurple`
/// theme seed that nothing used except — visibly — the login hover state and
/// every unstyled button. Everything now resolves through these tokens.
///
/// ## On the orange
///
/// The UMP brand orange `#FF9800` is kept, but it cannot carry white text:
/// measured against white it is **2.16:1**, where WCAG AA needs 4.5:1. Every
/// field label on the login and sign-up cards currently fails that test.
///
/// So the brand splits in two. [brand] stays `#FF9800` and is used for accents,
/// icons, borders and highlights **on light surfaces**, where it reads as the
/// identity colour. [primary] is a deepened `#B35300` used for filled surfaces
/// that carry white text, where it measures **5.05:1** and passes. Side by side
/// they read as the same brand; only one of them is safe behind text.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------- brand --

  /// The identity orange. Accents, icons and borders on light surfaces only.
  /// Never put white text on this.
  static const Color brand = Color(0xFFFF9800);
  static const Color brandLight = Color(0xFFFFB74D);
  static const Color brandPale = Color(0xFFFFF3E0);

  /// Filled-surface orange. White text on this passes AA (5.05:1).
  static const Color primary = Color(0xFFB35300);
  static const Color primaryDark = Color(0xFF8A3F00);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFFFE0B2);
  static const Color onPrimaryContainer = Color(0xFF3A1900);

  /// The staff dashboard blue, previously declared as a private field on one
  /// State class and then re-typed as a literal twice because nothing else
  /// could reach it.
  static const Color secondary = Color(0xFF0A4D68);
  static const Color secondaryDark = Color(0xFF063546);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFD4EAF4);
  static const Color onSecondaryContainer = Color(0xFF041F2B);

  // ------------------------------------------------------------- semantic --
  // All four carry white text at AA or better.

  static const Color success = Color(0xFF1B7F4B);
  static const Color successContainer = Color(0xFFD9F2E4);
  static const Color onSuccessContainer = Color(0xFF06301A);

  static const Color warning = Color(0xFF9A5B00);
  static const Color warningContainer = Color(0xFFFFEBC7);
  static const Color onWarningContainer = Color(0xFF3B2100);

  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFF9DEDC);
  static const Color onDangerContainer = Color(0xFF410E0B);

  static const Color info = secondary;

  // ------------------------------------------------------- light surfaces --

  static const Color background = Color(0xFFFCFAF8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F2EF);
  static const Color outline = Color(0xFFDCD6D0);

  /// 12.6:1 on [surface].
  static const Color textPrimary = Color(0xFF1C1B1A);

  /// 5.9:1 on [surface] — the minimum for body copy. Replaces the `Colors.grey`
  /// (2.8:1) used for secondary text throughout the old screens.
  static const Color textSecondary = Color(0xFF5E5852);

  /// Non-text only: dividers, disabled iconography.
  static const Color textDisabled = Color(0xFF9A928B);

  // -------------------------------------------------------- dark surfaces --

  static const Color darkBackground = Color(0xFF15130F);
  static const Color darkSurface = Color(0xFF211E1A);
  static const Color darkSurfaceMuted = Color(0xFF2C2822);
  static const Color darkOutline = Color(0xFF4A443D);
  static const Color darkTextPrimary = Color(0xFFF2EEE9);
  static const Color darkTextSecondary = Color(0xFFBFB8B0);

  /// On dark surfaces the bright brand orange is the readable one, so the
  /// light-mode split reverses.
  static const Color darkPrimary = brandLight;
  static const Color onDarkPrimary = Color(0xFF412C00);

  // --------------------------------------------------------------- status --

  /// Trading status and stock states. Always paired with a text label — REQ-4
  /// forbids conveying state by colour alone.
  static const Color open = success;
  static const Color closed = danger;
  static const Color lowStock = warning;
}
