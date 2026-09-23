import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../data/models/models.dart';

/// One order line — "2× Doritos · Sweet Chilli  R 30.00" — shared by the
/// student's orders and the staff queue, so the kitchen sees exactly which
/// variety or which combo parts were chosen.
class OrderItemRow extends StatelessWidget {
  const OrderItemRow({super.key, required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text('${item.quantity}×', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: theme.textTheme.bodyMedium),
                if (item.details != null)
                  Text(
                    item.details!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(item.lineTotalLabel, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
