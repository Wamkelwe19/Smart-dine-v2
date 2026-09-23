import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../data/models/models.dart';
import 'app_widgets.dart';
import 'price_tag.dart';
import 'special_badge.dart';

/// A menu item tile.
///
/// REQ-37 shows name, price, stock position and image. REQ-40 disables the add
/// control when the item cannot be ordered. REQ-41 is the important change: an
/// item that is sold out and an item staff have withdrawn from sale now read
/// differently — both previously rendered as the single word "Unavailable", so
/// a student could not tell whether to come back later.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    super.key,
    required this.item,
    required this.onAdd,
    this.parentCafeteriaOpen,
    this.showCafeteriaName = false,
    this.busy = false,
  });

  final MenuItem item;
  final VoidCallback onAdd;
  final bool? parentCafeteriaOpen;

  /// REQ-44: search results carry the owning cafeteria and its trading status.
  final bool showCafeteriaName;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availability = item.availability(parentCafeteriaOpen: parentCafeteriaOpen);
    final canOrder = availability.canOrder && !busy;

    return Semantics(
      button: canOrder,
      label: '${item.name}, ${item.effectivePriceLabel}'
          '${item.special == null ? '' : ', ${item.special!.badgeLabel.toLowerCase()}'}'
          ', ${availability.label}',
      child: Card(
        elevation: AppElevation.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          onTap: canOrder ? onAdd : null,
          child: Opacity(
            opacity: availability.canOrder ? 1 : 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _image(context, availability)),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (item.optionsSummary != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          item.optionsSummary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                      if (showCafeteriaName && item.cafeteriaName != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          item.cafeteriaName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      _stockLine(context, availability),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: PriceTag(item: item, enabled: canOrder),
                          ),
                          _addButton(context, canOrder),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context, MenuItemAvailability availability) {
    // REQ-11: a placeholder rather than a broken or empty frame.
    final fallback = Container(
      color: AppColors.brandPale,
      child: const Center(
        child: Icon(Icons.restaurant_menu, size: 36, color: AppColors.primary),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.imageUrl == null)
          fallback
        else
          Image.network(
            item.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const AppSkeleton(height: double.infinity, radius: 0),
          ),
        // REQ-41: the distinction is stated on the image, where it is seen
        // first, not buried in the stock line.
        if (!availability.canOrder)
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: StatusPill(
              label: availability.label,
              tone: availability == MenuItemAvailability.soldOut
                  ? StatusTone.warning
                  : StatusTone.negative,
              dense: true,
            ),
          )
        else if (item.special != null)
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: SpecialBadge(special: item.special!),
          ),
      ],
    );
  }

  Widget _stockLine(BuildContext context, MenuItemAvailability availability) {
    final theme = Theme.of(context);

    if (!availability.canOrder) {
      return Text(
        switch (availability) {
          MenuItemAvailability.soldOut => 'Back tomorrow',
          MenuItemAvailability.withdrawn => 'Removed by the cafeteria',
          MenuItemAvailability.cafeteriaClosed => 'Opens again later',
          MenuItemAvailability.available => '',
        },
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      );
    }

    // Colour plus wording, never colour alone (REQ-4).
    final units = item.availableUnits;
    return Text(
      item.isLowStock ? 'Only $units left' : '$units available',
      style: theme.textTheme.bodySmall?.copyWith(
        color: item.isLowStock ? AppColors.warning : AppColors.success,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _addButton(BuildContext context, bool canOrder) {
    if (busy) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    return IconButton.filled(
      onPressed: canOrder ? onAdd : null,
      // Items with varieties or combo choices open the options sheet.
      icon: Icon(item.needsOptions ? Icons.tune : Icons.add, size: 20),
      tooltip: canOrder
          ? (item.needsOptions
              ? 'Choose options for ${item.name}'
              : 'Add ${item.name} to cart')
          : null,
      constraints: const BoxConstraints(
        minWidth: AppA11y.minTouchTarget,
        minHeight: AppA11y.minTouchTarget,
      ),
    );
  }
}
