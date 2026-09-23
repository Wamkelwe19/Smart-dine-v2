import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../data/models/models.dart';

/// "20% OFF", "SPECIAL" or "FEATURED", pinned to an image corner.
///
/// Discounts use the filled primary (the orange that carries white text);
/// featured items use the calmer staff blue so they do not read as a saving.
class SpecialBadge extends StatelessWidget {
  const SpecialBadge({super.key, required this.special, this.large = false});

  final MenuSpecial special;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final discount = special.changesPrice;
    final foreground = discount ? Colors.white : AppColors.secondary;
    final background = discount ? AppColors.primary : AppColors.secondaryContainer;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? AppSpacing.md : AppSpacing.sm,
        vertical: large ? AppSpacing.xs : AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillRadius,
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            discount ? Icons.local_offer_outlined : Icons.star_outline_rounded,
            size: large ? 14 : 12,
            color: foreground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            special.badgeLabel,
            style: (large ? textTheme.labelMedium : textTheme.labelSmall)?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
