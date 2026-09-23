import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';

/// The price a student pays, with the usual price struck through beside it
/// when a special applies.
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.item,
    this.enabled = true,
    this.large = false,
  });

  final MenuItem item;
  final bool enabled;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = (large ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
        ?.copyWith(
      color: enabled ? theme.colorScheme.primary : AppColors.textSecondary,
    );

    // Varieties at different prices read "From R ..." rather than one price.
    final from = item.hasPriceRange;
    final price = Money.format(from ? item.fromPriceCents : item.effectivePriceCents);
    final showWas = item.isDiscounted && !from;

    return Semantics(
      label: from
          ? 'From $price'
          : showWas
              ? '$price, was ${item.priceLabel}'
              : price,
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: AppSpacing.xs,
        children: [
          if (from)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'From',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          Text(price, style: current),
          if (showWas)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                item.priceLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
