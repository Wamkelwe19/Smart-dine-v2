import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
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
  List<AppNotification> notices, {
  Set<String> dismissedIds = const {},
  required Future<void> Function(String id) onDismiss,
}) {
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
        dismissedIds: dismissedIds,
        onDismiss: onDismiss,
        controller: scrollController,
      ),
    ),
  );
}

class _NotificationList extends StatefulWidget {
  const _NotificationList({
    required this.notices,
    required this.dismissedIds,
    required this.onDismiss,
    required this.controller,
  });

  final List<AppNotification> notices;
  final Set<String> dismissedIds;
  final Future<void> Function(String id) onDismiss;
  final ScrollController controller;

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList> {
  late final Set<String> _dismissedIds = {...widget.dismissedIds};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleNotices = widget.notices
        .where((notice) => !_dismissedIds.contains(notice.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Text('Notices', style: theme.textTheme.titleLarge),
        ),
        Expanded(
          child: visibleNotices.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notices yet',
                  message: 'Announcements from the cafeterias will show here.',
                )
              : ListView.separated(
                  controller: widget.controller,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  itemCount: visibleNotices.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final notice = visibleNotices[index];
                    return Dismissible(
                      key: ValueKey(notice.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: AppRadius.cardRadius,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        try {
                          await widget.onDismiss(notice.id);
                          return true;
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppError.from(error).message),
                              ),
                            );
                          }
                          return false;
                        }
                      },
                      onDismissed: (_) {
                        setState(() => _dismissedIds.add(notice.id));
                      },
                      child: _NoticeCard(notice: notice),
                    );
                  },
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
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
