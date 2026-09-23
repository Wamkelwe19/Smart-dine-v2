import 'package:flutter/widgets.dart';

/// Spacing scale — a 4pt grid.
///
/// The old screens used 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32 and 48
/// interchangeably, plus two hand-computed magic insets (110 and 100) to clear
/// the floating navbar, which disagreed with each other and were missing
/// entirely on the cart and placeholder tabs.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard screen gutter. Never less than this on a phone.
  static const double gutter = lg;

  /// Height of the floating bottom navigation bar.
  static const double navBarHeight = 68;

  /// Bottom inset any scrollable under the navbar must reserve, so the last row
  /// is not trapped behind it. Derive it from the real safe-area inset:
  /// `AppSpacing.contentBottomInset(context)`.
  static double contentBottomInset(BuildContext context) =>
      navBarHeight + MediaQuery.of(context).padding.bottom + xl;
}

/// Corner radii. Previously ten different values were used for the same "card"
/// concept (12, 14 and 15 all appeared on food cards).
class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;

  /// Anything higher than the element is a pill.
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(lg));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
}

/// Elevation steps. Shadows were previously bespoke at every call site.
class AppElevation {
  const AppElevation._();

  static const double none = 0;
  static const double card = 1;
  static const double raised = 3;
  static const double sheet = 8;
}

/// Accessibility constants.
class AppA11y {
  const AppA11y._();

  /// WCAG 2.1 / Material minimum interactive size (REQ-125).
  ///
  /// The cart quantity steppers previously measured about 16x16dp because they
  /// set `constraints: BoxConstraints()`, which removes IconButton's default
  /// 48dp floor entirely.
  static const double minTouchTarget = 48;

  static const Size minTouchSize = Size(minTouchTarget, minTouchTarget);
}

/// Layout breakpoints. All three grids in the app previously hardcoded
/// `crossAxisCount: 2`, which gives two absurdly wide cards on a tablet and
/// about 136dp per card on a 320dp phone.
class AppBreakpoints {
  const AppBreakpoints._();

  static const double phone = 600;
  static const double tablet = 900;

  /// Column count for a menu/food grid at the given width.
  static int gridColumns(double width) {
    if (width >= tablet) return 4;
    if (width >= phone) return 3;
    if (width < 360) return 1;
    return 2;
  }
}
