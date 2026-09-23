import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_widgets.dart';
import 'special_editor.dart';

/// Opens the special editor over the staff portal. Shared with the Menu tab's
/// "Create special" shortcut.
Future<void> showSpecialEditor(
  BuildContext context, {
  required Cafeteria cafeteria,
  required List<MenuItem> menu,
  MenuSpecial? special,
  MenuItem? initialItem,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SpecialEditor(
      cafeteria: cafeteria,
      menu: menu,
      special: special,
      initialItem: initialItem,
    ),
  );
}

/// Discounts and featured items for this cafeteria.
class SpecialsTab extends StatefulWidget {
  const SpecialsTab({super.key, required this.cafeteria});

  final Cafeteria cafeteria;

  @override
  State<SpecialsTab> createState() => _SpecialsTabState();
}

class _SpecialsTabState extends State<SpecialsTab> {
  final CatalogRepository _catalog = CatalogRepository();

  // Created outside build() so a rebuild never re-subscribes.
  late Stream<List<MenuSpecial>> _specials =
      _catalog.watchSpecials(cafeteriaId: widget.cafeteria.id);
  late Stream<List<MenuItem>> _menu = _catalog.watchHallMenu(widget.cafeteria.id);

  @override
  void didUpdateWidget(covariant SpecialsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cafeteria.id != widget.cafeteria.id) {
      setState(() {
        _specials = _catalog.watchSpecials(cafeteriaId: widget.cafeteria.id);
        _menu = _catalog.watchHallMenu(widget.cafeteria.id);
      });
    }
  }

  Future<void> _setActive(MenuSpecial special, bool active) async {
    try {
      await _catalog.setSpecialActive(id: special.id, isActive: active);
      if (!mounted) return;
      context.showAppSuccess(active ? 'Special switched on' : 'Special paused');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    }
  }

  Future<void> _delete(MenuSpecial special, String itemName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this special?'),
        content: Text(
          'Students will stop seeing the deal on $itemName. If you only want '
          'to stop it for now, switch it off instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _catalog.deleteSpecial(special.id);
      if (!mounted) return;
      context.showAppSuccess('Special deleted');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MenuItem>>(
      stream: _menu,
      builder: (context, menuSnapshot) {
        final menu = menuSnapshot.data ?? const <MenuItem>[];

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: menu.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => showSpecialEditor(
                    context,
                    cafeteria: widget.cafeteria,
                    menu: menu,
                  ),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: const Text('New special'),
                ),
          body: StreamBuilder<List<MenuSpecial>>(
            stream: _specials,
            builder: (context, snapshot) {
              final error = snapshot.error ?? menuSnapshot.error;
              if (error != null) {
                return ErrorRetry(
                  message: AppError.from(error).message,
                  onRetry: () => setState(() {
                    _specials = _catalog.watchSpecials(
                        cafeteriaId: widget.cafeteria.id);
                    _menu = _catalog.watchHallMenu(widget.cafeteria.id);
                  }),
                );
              }
              if (!snapshot.hasData || !menuSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (menu.isEmpty) {
                return const EmptyState(
                  icon: Icons.restaurant_menu,
                  title: 'Add menu items first',
                  message: 'Specials are attached to items on your menu. '
                      'Add some in the Menu tab, then come back here.',
                );
              }

              final specials = snapshot.data!;
              if (specials.isEmpty) {
                return EmptyState(
                  icon: Icons.local_offer_outlined,
                  title: 'No specials yet',
                  message: 'Put a discount or a featured dish on the student '
                      'home page. Specials can start and end on their own.',
                  action: FilledButton.icon(
                    onPressed: () => showSpecialEditor(
                      context,
                      cafeteria: widget.cafeteria,
                      menu: menu,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('New special'),
                  ),
                );
              }

              final itemsById = {for (final item in menu) item.id: item};
              final now = DateTime.now();
              // Live first, then upcoming, paused, and finished last.
              final ordered = [...specials]..sort((a, b) =>
                  a.status(now).index.compareTo(b.status(now).index));

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  96, // clears the FAB
                ),
                itemCount: ordered.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final special = ordered[index];
                  final item = itemsById[special.menuItemId];
                  return _SpecialRow(
                    special: special,
                    item: item,
                    now: now,
                    onEdit: () => showSpecialEditor(
                      context,
                      cafeteria: widget.cafeteria,
                      menu: menu,
                      special: special,
                    ),
                    onActiveChanged: (v) => _setActive(special, v),
                    onDelete: () => _delete(special, item?.name ?? 'this item'),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _SpecialRow extends StatelessWidget {
  const _SpecialRow({
    required this.special,
    required this.item,
    required this.now,
    required this.onEdit,
    required this.onActiveChanged,
    required this.onDelete,
  });

  final MenuSpecial special;
  final MenuItem? item;
  final DateTime now;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = special.status(now);
    final item = this.item;

    final deal = switch (special.kind) {
      SpecialKind.percent => '${special.percentOff ?? 0}% off',
      SpecialKind.fixedPrice => 'Special price',
      SpecialKind.featured => 'Featured',
    };
    final priceLine = item == null || !special.changesPrice
        ? deal
        : '$deal · ${item.priceLabel} → '
            '${Money.format(special.applyTo(item.priceCents))}';

    final window = [
      if (status == SpecialStatus.scheduled)
        'Starts ${TimeAgo.dayClock(special.startsAt)}',
      if (special.endsAt != null)
        '${status == SpecialStatus.ended ? 'Ended' : 'Ends'} '
            '${TimeAgo.dayClock(special.endsAt!)}'
      else
        'No end date',
    ].join(' · ');

    return Card(
      elevation: AppElevation.none,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppRadius.cardRadius,
        child: Opacity(
          opacity: status == SpecialStatus.ended ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(url: item?.imageUrl),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        special.headline ?? item?.name ?? 'Removed item',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (special.headline != null && item != null)
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        priceLine,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        window,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      StatusPill(
                        label: status.label,
                        tone: switch (status) {
                          SpecialStatus.live => StatusTone.positive,
                          SpecialStatus.scheduled => StatusTone.neutral,
                          SpecialStatus.ended => StatusTone.warning,
                          SpecialStatus.paused => StatusTone.negative,
                        },
                        icon: switch (status) {
                          SpecialStatus.live => Icons.bolt,
                          SpecialStatus.scheduled => Icons.schedule,
                          SpecialStatus.ended => Icons.history,
                          SpecialStatus.paused => Icons.pause_circle_outline,
                        },
                        dense: true,
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Switch(
                      value: special.isActive,
                      onChanged: onActiveChanged,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.brandPale,
      child: const Icon(Icons.local_offer_outlined, color: AppColors.primary),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox(
        height: 64,
        width: 64,
        child: url == null
            ? fallback
            : Image.network(url!,
                fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}
