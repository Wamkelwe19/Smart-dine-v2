import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cafeteria_image.dart';
import '../../widgets/item_options_sheet.dart';
import '../../widgets/special_card.dart';
import '../shared/notification_center.dart';
import '../shared/notification_sheet.dart';
import 'cart_controller.dart';
import 'hall_menu_screen.dart';
import 'menu_search_delegate.dart';

/// The student home: today's specials across campus, then every dining hall.
///
/// Each hall opens its own page ([HallMenuScreen]) with the full menu, so the
/// home screen stays a calm overview rather than one long grid.
///
/// Search is a persistent action in a compact app bar; the old 210px pinned
/// header scrolled its search bar out of reach.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.profile,
    required this.cart,
    required this.onViewCart,
    required this.notifications,
    required this.onViewOrders,
  });

  final Profile profile;
  final CartController cart;
  final VoidCallback onViewCart;
  final NotificationCenter notifications;
  final VoidCallback onViewOrders;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final CatalogRepository _catalog = CatalogRepository();

  late Stream<List<Cafeteria>> _cafeterias = _catalog.watchCafeterias();
  StreamSubscription<List<MenuSpecial>>? _specialsSubscription;

  /// Every special row, for the per-hall "N on special" counts.
  List<MenuSpecial> _allSpecials = const [];

  /// Live specials joined to their item, for the carousel.
  List<MenuSpecial> _liveSpecials = const [];

  @override
  void initState() {
    super.initState();
    _listenToSpecials();
  }

  @override
  void dispose() {
    _specialsSubscription?.cancel();
    super.dispose();
  }

  /// Realtime tells us *that* specials changed; the joined fetch then gets
  /// each one's item and cafeteria in a single query.
  void _listenToSpecials() {
    _specialsSubscription?.cancel();
    _specialsSubscription = _catalog.watchSpecials().listen(
      (rows) {
        if (mounted) setState(() => _allSpecials = rows);
        _loadLiveSpecials();
      },
      // A specials failure must not take the halls down with it; the
      // carousel simply stays hidden.
      onError: (_) {},
    );
  }

  Future<void> _loadLiveSpecials() async {
    try {
      final live = await _catalog.fetchLiveSpecials();
      if (mounted) setState(() => _liveSpecials = live);
    } catch (_) {
      // Same as above: the carousel is additive.
    }
  }

  Future<void> _refresh() async {
    setState(() => _cafeterias = _catalog.watchCafeterias());
    _listenToSpecials();
    await _loadLiveSpecials();
  }

  /// Items with varieties or combo choices open the options sheet first.
  Future<void> _addToCart(MenuItem item) =>
      addItemToCart(context, cart: widget.cart, item: item);

  void _openHall(Cafeteria cafeteria) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HallMenuScreen(
          cafeteria: cafeteria,
          cart: widget.cart,
          onViewCart: widget.onViewCart,
        ),
      ),
    );
  }

  int _liveCountFor(String cafeteriaId) {
    final now = DateTime.now();
    return _allSpecials
        .where((s) => s.cafeteriaId == cafeteriaId && s.isLiveAt(now))
        .map((s) => s.menuItemId)
        .toSet()
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.gutter,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hi, ${widget.profile.displayName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'What are you eating today?',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search the menu',
            icon: const Icon(Icons.search),
            onPressed: () => showSearch<void>(
              context: context,
              delegate: MenuSearchDelegate(
                catalog: _catalog,
                onAdd: _addToCart,
              ),
            ),
          ),
          NotificationBell(
            center: widget.notifications,
            onOpenOrders: widget.onViewOrders,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: StreamBuilder<List<Cafeteria>>(
        stream: _cafeterias,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: AppError.from(snapshot.error!).message,
              onRetry: _refresh,
            );
          }
          if (!snapshot.hasData) return const _HomeSkeleton();

          final cafeterias = snapshot.data!;
          if (cafeterias.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No cafeterias yet',
              message: 'Campus outlets will appear here once they are set up.',
            );
          }

          // Open halls first, then by name, so what can serve you now leads.
          final ordered = [...cafeterias]
            ..sort((a, b) {
              if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
              return a.name.compareTo(b.name);
            });

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                if (_liveSpecials.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: "Today's specials",
                      trailing: Text(
                        '${_liveSpecials.length} '
                        '${_liveSpecials.length == 1 ? 'deal' : 'deals'}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ListenableBuilder(
                      listenable: widget.cart,
                      builder: (context, _) => _SpecialsCarousel(
                        specials: _liveSpecials,
                        busyItemId: widget.cart.busyItemId,
                        onAdd: _addToCart,
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Dining halls',
                    trailing: Text(
                      '${cafeterias.where((c) => c.isOpen).length} open now',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.contentBottomInset(context),
                  ),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      return SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          // One wide card per row on a phone; more on tablets.
                          crossAxisCount: width < 600
                              ? 1
                              : (width < 900 ? 2 : 3),
                          mainAxisSpacing: AppSpacing.lg,
                          crossAxisSpacing: AppSpacing.lg,
                          childAspectRatio: 16 / 10,
                        ),
                        itemCount: ordered.length,
                        itemBuilder: (context, index) {
                          final cafeteria = ordered[index];
                          return _DiningHallCard(
                            cafeteria: cafeteria,
                            specialCount: _liveCountFor(cafeteria.id),
                            onTap: () => _openHall(cafeteria),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- carousel --

class _SpecialsCarousel extends StatefulWidget {
  const _SpecialsCarousel({
    required this.specials,
    required this.busyItemId,
    required this.onAdd,
  });

  final List<MenuSpecial> specials;
  final String? busyItemId;
  final ValueChanged<MenuItem> onAdd;

  @override
  State<_SpecialsCarousel> createState() => _SpecialsCarouselState();
}

class _SpecialsCarouselState extends State<_SpecialsCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.86);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.specials.length;
    final page = _page.clamp(0, count - 1);

    return Column(
      children: [
        SizedBox(
          // Photo plus two lines of text and the price row, at up to 1.3x
          // text scale.
          height: 300,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: count,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) {
              final special = widget.specials[index];
              return Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? AppSpacing.gutter : AppSpacing.xs,
                  right: index == count - 1 ? AppSpacing.gutter : AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                child: SpecialCard(
                  special: special,
                  busy: widget.busyItemId == special.menuItemId,
                  onAdd: widget.onAdd,
                ),
              );
            },
          ),
        ),
        if (count > 1) ...[
          const SizedBox(height: AppSpacing.md),
          _PageDots(count: count, index: page),
        ],
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: i == index ? 20 : 6,
            decoration: BoxDecoration(
              color: i == index ? AppColors.primary : AppColors.outline,
              borderRadius: AppRadius.pillRadius,
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------- dining halls --

/// REQ-33 / REQ-34: every outlet with its live trading status, now with its
/// photo. The photo carries into the hall page through a Hero.
class _DiningHallCard extends StatelessWidget {
  const _DiningHallCard({
    required this.cafeteria,
    required this.specialCount,
    required this.onTap,
  });

  final Cafeteria cafeteria;
  final int specialCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label:
          '${cafeteria.name}, ${cafeteria.statusLabel}'
          '${specialCount > 0 ? ', $specialCount on special' : ''}',
      excludeSemantics: true,
      child: Card(
        elevation: AppElevation.card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A closed hall is shown, but visibly quieter.
              ColorFiltered(
                colorFilter: cafeteria.isOpen
                    ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                    : const ColorFilter.matrix(_desaturate),
                child: CafeteriaImage(
                  cafeteria: cafeteria,
                  heroTag: CafeteriaImage.heroTagFor(cafeteria),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xA6000000)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              if (specialCount > 0)
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: _SpecialsChip(count: specialCount),
                ),
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.lg,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cafeteria.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              shadows: const [
                                Shadow(color: Color(0x66000000), blurRadius: 8),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          StatusPill(
                            label: cafeteria.isOpen ? 'Open now' : 'Closed',
                            tone: cafeteria.isOpen
                                ? StatusTone.positive
                                : StatusTone.negative,
                            icon: cafeteria.isOpen
                                ? Icons.check_circle_outline
                                : Icons.do_not_disturb_on_outlined,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Container(
                      height: 40,
                      width: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<double> _desaturate = [
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

class _SpecialsChip extends StatelessWidget {
  const _SpecialsChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: AppRadius.pillRadius,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_offer_outlined, size: 14, color: Colors.white),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$count on special',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- shared --

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.gutter),
    children: const [
      AppSkeleton(height: 24, width: 160, radius: AppRadius.xs),
      SizedBox(height: AppSpacing.md),
      AppSkeleton(height: 260, radius: AppRadius.md),
      SizedBox(height: AppSpacing.xl),
      AppSkeleton(height: 24, width: 140, radius: AppRadius.xs),
      SizedBox(height: AppSpacing.md),
      AppSkeleton(height: 200, radius: AppRadius.md),
      SizedBox(height: AppSpacing.lg),
      AppSkeleton(height: 200, radius: AppRadius.md),
    ],
  );
}
