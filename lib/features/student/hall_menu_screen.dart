import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cafeteria_image.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/item_options_sheet.dart';
import '../../widgets/menu_item_card.dart';
import 'cart_controller.dart';

/// One tab on the hall page: everything, the specials, or one category.
class _MenuTab {
  const _MenuTab(this.label, this.icon, this.matches, {this.category});

  final String label;
  final IconData icon;
  final bool Function(MenuItem item) matches;
  final MenuCategory? category;

  static final all = <_MenuTab>[
    _MenuTab('All', Icons.restaurant_menu, (_) => true),
    _MenuTab('Specials', Icons.local_offer_outlined, (i) => i.special != null),
    for (final category in MenuCategory.values)
      _MenuTab(
        category.label,
        categoryIcon(category),
        (i) => i.category == category,
        category: category,
      ),
  ];
}

/// One dining hall: a photo header that the home card's photo flies into,
/// then its menu under category tabs — All, Specials, Meals, Combos,
/// Beverages, Snacks.
///
/// Pushed over the student shell, so it carries its own cart bar in place of
/// the shell's navigation.
class HallMenuScreen extends StatefulWidget {
  const HallMenuScreen({
    super.key,
    required this.cafeteria,
    required this.cart,
    required this.onViewCart,
  });

  final Cafeteria cafeteria;
  final CartController cart;
  final VoidCallback onViewCart;

  @override
  State<HallMenuScreen> createState() => _HallMenuScreenState();
}

class _HallMenuScreenState extends State<HallMenuScreen>
    with SingleTickerProviderStateMixin {
  final CatalogRepository _catalog = CatalogRepository();

  // Created once, not in build(), so a rebuild never re-subscribes.
  late final Stream<List<Cafeteria>> _cafeterias = _catalog.watchCafeterias();
  late Stream<List<MenuItem>> _menu = _catalog.watchHallMenu(widget.cafeteria.id);

  late final TabController _tabs =
      TabController(length: _MenuTab.all.length, vsync: this)
        ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openCart() {
    Navigator.of(context).pop();
    widget.onViewCart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keeps the trading status live while the student is browsing.
      body: StreamBuilder<List<Cafeteria>>(
        stream: _cafeterias,
        builder: (context, snapshot) {
          final cafeteria = snapshot.data?.firstWhere(
                (c) => c.id == widget.cafeteria.id,
                orElse: () => widget.cafeteria,
              ) ??
              widget.cafeteria;

          return StreamBuilder<List<MenuItem>>(
            stream: _menu,
            builder: (context, menu) => _body(cafeteria, menu),
          );
        },
      ),
      bottomNavigationBar: _CartBar(cart: widget.cart, onTap: _openCart),
    );
  }

  Widget _body(Cafeteria cafeteria, AsyncSnapshot<List<MenuItem>> menu) {
    final items = menu.data ?? const <MenuItem>[];
    final tab = _MenuTab.all[_tabs.index];
    final shown = items.where(tab.matches).toList();
    final specialCount = items.where((i) => i.special != null).length;

    return CustomScrollView(
      slivers: [
        _HallHeader(cafeteria: cafeteria),
        SliverToBoxAdapter(
          child: _HallSummary(
            cafeteria: cafeteria,
            itemCount: items.length,
            specialCount: specialCount,
          ),
        ),
        if (!cafeteria.isOpen)
          SliverToBoxAdapter(child: _ClosedBanner(name: cafeteria.name)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarHeader(
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              tabs: [
                for (final t in _MenuTab.all)
                  Tab(
                    height: 44,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Text(t.label),
                        if (menu.hasData) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _CountBadge(count: items.where(t.matches).length),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (menu.hasError)
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorRetry(
              message: AppError.from(menu.error!).message,
              onRetry: () => setState(
                  () => _menu = _catalog.watchHallMenu(widget.cafeteria.id)),
            ),
          )
        else if (!menu.hasData)
          const _GridSkeleton()
        // REQ-42: an explanation, not an empty grid.
        else if (shown.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyFor(tab, cafeteria, items.isEmpty),
          )
        else
          _MenuGrid(
            items: shown,
            cart: widget.cart,
            cafeteriaOpen: cafeteria.isOpen,
          ),
      ],
    );
  }

  Widget _emptyFor(_MenuTab tab, Cafeteria cafeteria, bool menuEmpty) {
    if (menuEmpty) {
      return EmptyState(
        icon: Icons.no_meals_outlined,
        title: 'Nothing on the menu',
        message: '${cafeteria.name} has not added any items yet. '
            'Check back a little later.',
      );
    }
    if (tab.category == null) {
      return const EmptyState(
        icon: Icons.local_offer_outlined,
        title: 'No specials right now',
        message: 'Deals from this hall will show up here.',
      );
    }
    return EmptyState(
      icon: tab.icon,
      title: 'No ${tab.label.toLowerCase()} here yet',
      message: '${cafeteria.name} has not added any '
          '${tab.label.toLowerCase()}. Try another tab.',
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Text(
          '$count',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
}

/// Pins the category tabs under the collapsed photo header.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  const _TabBarHeader(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        elevation: overlapsContent || shrinkOffset > 0 ? AppElevation.card : 0,
        child: Align(alignment: Alignment.bottomLeft, child: tabBar),
      );

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) => true;
}

/// The photo header. Collapses to the primary colour, which carries white text.
class _HallHeader extends StatelessWidget {
  const _HallHeader({required this.cafeteria});

  final Cafeteria cafeteria;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 240,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        titlePadding: const EdgeInsetsDirectional.only(
          start: 56,
          end: AppSpacing.gutter,
          bottom: AppSpacing.lg,
        ),
        title: Text(
          cafeteria.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            CafeteriaImage(
              cafeteria: cafeteria,
              heroTag: CafeteriaImage.heroTagFor(cafeteria),
            ),
            // Scrim at both ends: the back button on top, the title below.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xB3000000),
                  ],
                  stops: [0, 0.3, 0.5, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HallSummary extends StatelessWidget {
  const _HallSummary({
    required this.cafeteria,
    required this.itemCount,
    required this.specialCount,
  });

  final Cafeteria cafeteria;
  final int itemCount;
  final int specialCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          StatusPill(
            label: cafeteria.isOpen ? 'Open now' : 'Closed',
            tone: cafeteria.isOpen ? StatusTone.positive : StatusTone.negative,
            icon: cafeteria.isOpen
                ? Icons.check_circle_outline
                : Icons.do_not_disturb_on_outlined,
          ),
          StatusPill(
            label: '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            tone: StatusTone.neutral,
            icon: Icons.restaurant_menu,
          ),
          if (specialCount > 0)
            StatusPill(
              label: '$specialCount on special',
              tone: StatusTone.warning,
              icon: Icons.local_offer_outlined,
            ),
        ],
      ),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({
    required this.items,
    required this.cart,
    required this.cafeteriaOpen,
  });

  final List<MenuItem> items;
  final CartController cart;
  final bool cafeteriaOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.xxxl,
      ),
      sliver: ListenableBuilder(
        listenable: cart,
        builder: (context, _) => SliverLayoutBuilder(
          builder: (context, constraints) => SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  AppBreakpoints.gridColumns(constraints.crossAxisExtent),
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.lg,
              // Room for the options line ("3 options", a combo's parts).
              childAspectRatio: 0.66,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return MenuItemCard(
                item: item,
                parentCafeteriaOpen: cafeteriaOpen,
                busy: cart.busyItemId == item.id,
                onAdd: () => addItemToCart(
                  context,
                  cart: cart,
                  item: item,
                  parentCafeteriaOpen: cafeteriaOpen,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            childAspectRatio: 0.66,
          ),
          itemCount: 4,
          itemBuilder: (_, _) => const AppSkeleton(
            height: double.infinity,
            radius: AppRadius.md,
          ),
        ),
      );
}

/// REQ-35: states plainly why nothing can be added.
class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 20, color: AppColors.onWarningContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$name is closed right now, so you cannot add items yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.onWarningContainer),
              ),
            ),
          ],
        ),
      );
}

/// Stands in for the shell's navigation while this page covers it.
class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.onTap});

  final CartController cart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        if (cart.isEmpty) return const SizedBox.shrink();
        final count = cart.itemCount;

        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.md),
          child: Material(
            color: AppColors.primary,
            borderRadius: AppRadius.pillRadius,
            elevation: AppElevation.raised,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.pillRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'View cart · $count ${count == 1 ? 'item' : 'items'}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    Text(
                      Money.format(cart.totalCents),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
