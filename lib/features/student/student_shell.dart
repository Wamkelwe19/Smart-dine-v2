import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import 'cart_controller.dart';
import 'cart_tab.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'profile_tab.dart';

/// The student interface: four tabs over a shared cart.
///
/// Two structural changes from the old screen:
///
/// 1. `IndexedStack` replaces `screens[_currentIndex]`. The old code rebuilt
///    the whole tab list on every `build()` and rendered only the active entry,
///    so switching tabs destroyed and recreated each subtree — re-running
///    `initState`, re-subscribing all three realtime streams, losing scroll
///    position, and wiping a half-typed form.
///
/// 2. The cart lives here, in one controller, instead of being a list in the
///    home screen's State that the cart screen shallow-copied.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key, required this.profile});

  final Profile profile;

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  final CartController _cart = CartController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // REQ-52: picks up any cart left over from a previous session.
    _cart.load();
  }

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  void _goToTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              HomeTab(
                profile: widget.profile,
                cart: _cart,
                onViewCart: () => _goToTab(1),
              ),
              CartTab(
                cart: _cart,
                onBrowse: () => _goToTab(0),
                onOrderPlaced: () => _goToTab(2),
              ),
              OrdersTab(profile: widget.profile),
              ProfileTab(profile: widget.profile),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            // Listens so the cart badge updates the moment a line changes.
            child: ListenableBuilder(
              listenable: _cart,
              builder: (context, _) => _NavBar(
                index: _index,
                cartCount: _cart.itemCount,
                onChanged: _goToTab,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.cartCount,
    required this.onChanged,
  });

  final int index;
  final int cartCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
        height: AppSpacing.navBarHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppRadius.pillRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            _item(context, 0, Icons.home_rounded, 'Home'),
            // The old navbar had no cart badge at all.
            _item(context, 1, Icons.shopping_bag_rounded, 'Cart',
                badge: cartCount),
            _item(context, 2, Icons.receipt_long_rounded, 'Orders'),
            _item(context, 3, Icons.person_rounded, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int slot,
    IconData icon,
    String label, {
    int badge = 0,
  }) {
    final theme = Theme.of(context);
    final selected = index == slot;
    final colour = selected ? theme.colorScheme.primary : AppColors.textSecondary;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: badge > 0 ? '$label, $badge items' : label,
        child: InkWell(
          onTap: () => onChanged(slot),
          borderRadius: AppRadius.pillRadius,
          // The whole 68dp-tall cell is the target, comfortably over the 48dp
          // minimum (REQ-125).
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(icon, size: 24, color: colour),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
