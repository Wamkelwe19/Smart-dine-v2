import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/special_badge.dart';
import 'menu_item_editor.dart';
import 'specials_tab.dart';

/// Menu management: meals, combos, beverages and snacks, with their varieties
/// and combo parts.
///
/// Adds the delete path the old dashboard never had (REQ-75), and keeps the
/// realtime stream out of `build()` — it was constructed inline there, creating
/// a new subscription on every rebuild of the tab and never cancelling the old
/// one.
class ManagementTab extends StatefulWidget {
  const ManagementTab({super.key, required this.cafeteria});

  final Cafeteria cafeteria;

  @override
  State<ManagementTab> createState() => _ManagementTabState();
}

class _ManagementTabState extends State<ManagementTab> {
  final CatalogRepository _catalog = CatalogRepository();

  /// Joined, so each item carries its varieties, combo parts and special.
  late Stream<List<MenuItem>> _stream =
      _catalog.watchHallMenu(widget.cafeteria.id);

  /// Null shows every category.
  MenuCategory? _filter;

  @override
  void didUpdateWidget(covariant ManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cafeteria.id != widget.cafeteria.id) {
      setState(() => _stream = _catalog.watchHallMenu(widget.cafeteria.id));
    }
  }

  Future<void> _edit(List<MenuItem> menu, {MenuItem? item}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MenuItemEditor(
        cafeteria: widget.cafeteria,
        item: item,
        menu: menu,
      ),
    );
  }

  /// REQ-75 and REQ-81 — the stored image goes with the item.
  Future<void> _delete(MenuItem item, List<MenuItem> menu) async {
    final inCombos = menu
        .where((m) => m.components.any((c) => c.item.id == item.id))
        .map((m) => m.name)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          'This removes the item and its photograph permanently. If you only '
          'want to stop selling it for now, switch it off instead.'
          '${inCombos.isEmpty ? '' : '\n\nIt will also be taken out of: '
              '${inCombos.join(', ')}.'}',
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
      await _catalog.deleteMenuItem(item);
      if (!mounted) return;
      context.showAppSuccess('${item.name} deleted');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MenuItem>>(
      stream: _stream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MenuItem>[];

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: snapshot.hasData
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(items),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                )
              : null,
          body: _body(snapshot, items),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<List<MenuItem>> snapshot, List<MenuItem> items) {
    if (snapshot.hasError) {
      return ErrorRetry(
        message: AppError.from(snapshot.error!).message,
        onRetry: () =>
            setState(() => _stream = _catalog.watchHallMenu(widget.cafeteria.id)),
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.restaurant_menu,
        title: 'No menu items yet',
        message: 'Add your first dish so students can start ordering.',
        action: FilledButton.icon(
          onPressed: () => _edit(items),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      );
    }

    final shown = _filter == null
        ? items
        : items.where((i) => i.category == _filter).toList();

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
            children: [
              _FilterChip(
                label: 'All · ${items.length}',
                icon: Icons.restaurant_menu,
                selected: _filter == null,
                onSelected: () => setState(() => _filter = null),
              ),
              for (final category in MenuCategory.values)
                _FilterChip(
                  label: '${category.label} · '
                      '${items.where((i) => i.category == category).length}',
                  icon: categoryIcon(category),
                  selected: _filter == category,
                  onSelected: () => setState(() => _filter = category),
                ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  icon: categoryIcon(_filter!),
                  title: 'No ${_filter!.label.toLowerCase()} yet',
                  message: _filter == MenuCategory.combo
                      ? 'Build a combo from items already on your menu.'
                      : 'Add one with the button below.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    96, // clears the FAB
                  ),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final item = shown[index];
                    return _ManagementCard(
                      item: item,
                      onEdit: () => _edit(items, item: item),
                      onDelete: () => _delete(item, items),
                      onCreateSpecial: () => showSpecialEditor(
                        context,
                        cafeteria: widget.cafeteria,
                        menu: items,
                        initialItem: item,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: FilterChip(
          avatar: Icon(icon, size: 16),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onSelected(),
        ),
      );
}

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onCreateSpecial,
  });

  final MenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCreateSpecial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = item.availableUnits;
    final soldOut = !item.availability().canOrder && item.isAvailable;

    final stockLabel = item.isCombo
        ? (item.components.isEmpty
            ? 'No items in it'
            : soldOut
                ? 'A part is sold out'
                : '$units can be made')
        : units == 0
            ? 'Sold out'
            : '$units in stock';

    return Card(
      elevation: AppElevation.none,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: SizedBox(
                  height: 64,
                  width: 64,
                  child: item.imageUrl == null
                      ? Container(
                          color: AppColors.brandPale,
                          child: Icon(
                            categoryIcon(item.category),
                            color: AppColors.primary,
                          ),
                        )
                      : Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.brandPale,
                            child: Icon(
                              categoryIcon(item.category),
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      [
                        item.category.singular,
                        ?item.optionsSummary,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      item.isDiscounted
                          ? '${item.effectivePriceLabel} (usually ${item.priceLabel})'
                          : item.priceLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (item.hasVariants) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.variants
                            .map((v) => '${v.name} ${v.isAvailable ? v.stockCount : 'off'}')
                            .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (item.special != null)
                          SpecialBadge(special: item.special!),
                        // REQ-41: the two states read differently here too.
                        StatusPill(
                          label: item.isAvailable ? 'On sale' : 'Off sale',
                          tone: item.isAvailable
                              ? StatusTone.positive
                              : StatusTone.negative,
                          dense: true,
                        ),
                        StatusPill(
                          label: stockLabel,
                          tone: units == 0
                              ? StatusTone.warning
                              : StatusTone.neutral,
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'special') onCreateSpecial();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'special',
                    child: Text('Create special'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
