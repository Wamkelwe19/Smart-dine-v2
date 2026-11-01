import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/app_widgets.dart';
import 'notification_center.dart';
import 'notification_settings_screen.dart';

/// The bell for both interfaces: unread count, opening the inbox.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.center,
    required this.onOpenOrders,
  });

  final NotificationCenter center;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) {
        final unread = center.unreadCount;
        return IconButton(
          tooltip: unread == 0
              ? 'Notifications'
              : 'Notifications, $unread unread',
          onPressed: () => showNotificationSheet(
            context,
            center: center,
            onOpenOrders: onOpenOrders,
          ),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 9 ? '9+' : '$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

/// The inbox: order updates and cafeteria announcements, newest first.
Future<void> showNotificationSheet(
  BuildContext context, {
  required NotificationCenter center,
  required VoidCallback onOpenOrders,
}) {
  final navigator = Navigator.of(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => ListenableBuilder(
        listenable: center,
        builder: (context, _) => _Inbox(
          center: center,
          controller: scrollController,
          onOpenOrders: () {
            Navigator.of(sheetContext).pop();
            onOpenOrders();
          },
          onOpenSettings: () {
            Navigator.of(sheetContext).pop();
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => NotificationSettingsScreen(center: center),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _Entry {
  const _Entry({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.icon,
    required this.tint,
    required this.unread,
    this.isOrder = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime? at;
  final IconData icon;
  final Color tint;
  final bool unread;
  final bool isOrder;
}

class _Inbox extends StatelessWidget {
  const _Inbox({
    required this.center,
    required this.controller,
    required this.onOpenOrders,
    required this.onOpenSettings,
  });

  final NotificationCenter center;
  final ScrollController controller;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenSettings;

  static (IconData, Color) _look(NotificationKind kind) => switch (kind) {
    NotificationKind.orderPlaced => (
      Icons.receipt_long_outlined,
      AppColors.primary,
    ),
    NotificationKind.orderPreparing => (
      Icons.soup_kitchen_outlined,
      AppColors.warning,
    ),
    NotificationKind.orderReady => (
      Icons.notifications_active_outlined,
      AppColors.success,
    ),
    NotificationKind.orderCollected => (
      Icons.check_circle_outline,
      AppColors.success,
    ),
    NotificationKind.orderCancelled => (
      Icons.cancel_outlined,
      AppColors.danger,
    ),
    NotificationKind.paymentReceived => (
      Icons.credit_score_outlined,
      AppColors.success,
    ),
    NotificationKind.paymentFailed => (
      Icons.credit_card_off_outlined,
      AppColors.danger,
    ),
    NotificationKind.newOrder => (Icons.add_shopping_cart, AppColors.primary),
    NotificationKind.announcement => (
      Icons.campaign_outlined,
      AppColors.secondary,
    ),
  };

  List<_Entry> _entries() {
    final dismissed = center.dismissedIds;
    final entries = <_Entry>[
      for (final notice in center.personal)
        if (!dismissed.contains('personal:${notice.id}'))
          () {
            final (icon, tint) = _look(notice.kind);
            return _Entry(
              id: 'personal:${notice.id}',
              title: notice.title,
              body: notice.body,
              at: notice.createdAt,
              icon: icon,
              tint: tint,
              unread: !notice.isRead,
              isOrder: notice.orderId != null,
            );
          }(),
      for (final notice in center.announcements)
        if (!dismissed.contains('announcement:${notice.id}'))
          _Entry(
            id: 'announcement:${notice.id}',
            title: notice.title?.isNotEmpty == true
                ? notice.title!
                : 'Announcement',
            body: notice.message,
            at: notice.createdAt,
            icon: switch (notice.type) {
              'low_stock' => Icons.warning_amber_rounded,
              'new_item' => Icons.restaurant_menu,
              _ => Icons.campaign_outlined,
            },
            tint: notice.type == 'low_stock'
                ? AppColors.warning
                : AppColors.secondary,
            unread: center.isUnread(notice),
          ),
    ]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('Notifications', style: theme.textTheme.titleLarge),
              ),
              if (center.unreadCount > 0)
                TextButton(
                  onPressed: center.markAllRead,
                  child: const Text('Mark all read'),
                ),
              IconButton(
                tooltip: 'Notification settings',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Nothing yet',
                  message:
                      'Order updates and cafeteria announcements will '
                      'show here.',
                )
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Dismissible(
                      key: ValueKey(entry.id),
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
                          await center.saveDismissal(entry.id);
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
                      onDismissed: (_) => center.applyDismissal(entry.id),
                      child: _EntryCard(
                        entry: entry,
                        onTap: entry.isOrder ? onOpenOrders : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, this.onTap});

  final _Entry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: AppElevation.none,
      margin: EdgeInsets.zero,
      color: entry.unread
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(
          color: entry.unread
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: entry.tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(entry.icon, size: 20, color: entry.tint),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(entry.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      TimeAgo.format(entry.at),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.unread)
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.xs),
                  height: 8,
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
