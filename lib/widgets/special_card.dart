import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'app_widgets.dart';
import 'price_tag.dart';
import 'special_badge.dart';

/// One special: photo, badge, headline, where to get it and the saving.
///
/// Shared by the student home carousel and the staff editor preview, so staff
/// see exactly what students will see.
class SpecialCard extends StatelessWidget {
  const SpecialCard({
    super.key,
    required this.special,
    this.onAdd,
    this.busy = false,
    this.now,
  });

  /// Must carry its joined [MenuSpecial.item].
  final MenuSpecial special;
  final ValueChanged<MenuItem>? onAdd;
  final bool busy;

  /// For the staff preview, which shows a special before its start.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = special.item!.withSpecial(special);
    final canOrder = onAdd != null && item.availability().canOrder && !busy;
    final title = special.headline ?? item.name;

    return Semantics(
      button: canOrder,
      label: '$title, ${special.badgeLabel.toLowerCase()}, '
          '${item.effectivePriceLabel}'
          '${item.cafeteriaName == null ? '' : ', at ${item.cafeteriaName}'}',
      excludeSemantics: true,
      child: Card(
        elevation: AppElevation.raised,
        shadowColor: AppColors.primary.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: canOrder ? () => onAdd!(item) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ItemPhoto(url: item.imageUrl),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x59000000)],
                          stops: [0.55, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.md,
                      left: AppSpacing.md,
                      child: SpecialBadge(special: special, large: true),
                    ),
                    if (special.endsAt != null)
                      Positioned(
                        left: AppSpacing.md,
                        bottom: AppSpacing.sm,
                        child: _EndsLabel(endsAt: special.endsAt!, now: now),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            [
                              if (special.headline != null) item.name,
                              ?item.cafeteriaName,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: PriceTag(item: item, large: true)),
                        if (onAdd != null) _addButton(item, canOrder),
                      ],
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

  Widget _addButton(MenuItem item, bool canOrder) {
    if (busy) {
      return const SizedBox(
        height: AppA11y.minTouchTarget,
        width: AppA11y.minTouchTarget,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return IconButton.filled(
      onPressed: canOrder ? () => onAdd!(item) : null,
      icon: const Icon(Icons.add, size: 20),
      tooltip: canOrder ? 'Add ${item.name} to cart' : null,
      constraints: const BoxConstraints(
        minWidth: AppA11y.minTouchTarget,
        minHeight: AppA11y.minTouchTarget,
      ),
    );
  }
}

class _ItemPhoto extends StatelessWidget {
  const _ItemPhoto({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    // REQ-11: a placeholder rather than a broken or empty frame.
    final fallback = Container(
      color: AppColors.brandPale,
      child: const Center(
        child: Icon(Icons.restaurant_menu, size: 40, color: AppColors.primary),
      ),
    );
    if (url == null) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const AppSkeleton(height: double.infinity, radius: 0),
    );
  }
}

class _EndsLabel extends StatelessWidget {
  const _EndsLabel({required this.endsAt, this.now});

  final DateTime endsAt;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 14, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Ends ${TimeAgo.dayClock(endsAt, now: now)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              shadows: const [Shadow(color: Color(0x80000000), blurRadius: 4)],
            ),
          ),
        ],
      );
}

