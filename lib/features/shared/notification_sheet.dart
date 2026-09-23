import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../widgets/app_widgets.dart';

/// One notification sheet for both interfaces.
///
/// The student and staff versions were previously byte-for-byte duplicates of
/// the same `DraggableScrollableSheet` configuration, right down to the grab
/// handle dimensions, with separately maintained list builders.
Future<void> showNotificationSheet(
  BuildContext context,
  List<AppNotification> notices,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => _NotificationList(
        notices: notices,
        controller: scrollController,
      ),
    ),
  );
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.notices, required this.controller});

  final List<AppNotification> notices;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.md),
          child: Text('Notices', style: theme.textTheme.titleLarge),
        ),
        Expanded(
          child: notices.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notices yet',
                  message: 'Announcements from the cafeterias will show here.',
                )
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  itemCount: notices.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) =>
                      _NoticeCard(notice: notices[index]),
                ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final AppNotification notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, tint) = switch (notice.type) {
      'low_stock' => (Icons.warning_amber_rounded, AppColors.warning),
      'new_item' => (Icons.restaurant_menu, AppColors.primary),
      'announcement' => (Icons.campaign_outlined, AppColors.secondary),
      _ => (Icons.info_outline, AppColors.secondary),
    };

    return Card(
      elevation: AppElevation.none,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notice.title != null && notice.title!.isNotEmpty)
                    Text(notice.title!, style: theme.textTheme.titleSmall),
                  Text(notice.message, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    TimeAgo.format(notice.createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
