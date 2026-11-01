import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../widgets/app_widgets.dart';
import '../shared/notification_sheet.dart';
import 'management_tab.dart';
import 'queue_tab.dart';
import 'settings_tab.dart';
import 'specials_tab.dart';

/// The staff dashboard.
///
/// The cafeteria selector now lists only the outlets this user is bound to
/// through `staff_cafeterias` (REQ-36, BR-3). The old dropdown listed every
/// cafeteria on campus and let any staff account change any of them — and with
/// RLS off, those writes succeeded.
///
/// A staff account with no binding sees an explanation rather than an empty
/// dropdown, because that is the expected state until an administrator grants
/// access.
class StaffShell extends StatefulWidget {
  const StaffShell({super.key, required this.profile});

  final Profile profile;

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  final CatalogRepository _catalog = CatalogRepository();
  final NotificationRepository _notifications = NotificationRepository();

  List<Cafeteria>? _cafeterias;
  Cafeteria? _selected;
  Object? _error;
  DateTime? _lastSeen;
  Set<String> _dismissedNotificationIds = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _notifications.lastSeen().then((value) {
      if (mounted) setState(() => _lastSeen = value);
    });
    _notifications.dismissedIds(widget.profile.id).then((value) {
      if (mounted) setState(() => _dismissedNotificationIds = value);
    });
  }

  Future<void> _dismissNotification(String id) async {
    await _notifications.dismiss(
      userId: widget.profile.id,
      notificationId: id,
    );
    if (mounted) {
      setState(() => _dismissedNotificationIds = {
            ..._dismissedNotificationIds,
            id,
          });
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await _catalog.fetchMyCafeterias();
      if (!mounted) return;
      setState(() {
        _cafeterias = list;
        _selected = list.isEmpty ? null : list.first;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// Keeps the picker list and the selection in step after an edit, such as a
  /// new cover photo from Settings.
  void _replaceCafeteria(Cafeteria updated) {
    setState(() {
      _cafeterias = [
        for (final c in _cafeterias ?? const <Cafeteria>[])
          c.id == updated.id ? updated : c,
      ];
      if (_selected?.id == updated.id) _selected = updated;
    });
  }

  Future<void> _toggleTrading(bool open) async {
    final cafeteria = _selected;
    if (cafeteria == null) return;

    // REQ-83: optimistic, reverted on failure.
    setState(() => _selected = Cafeteria(
          id: cafeteria.id,
          name: cafeteria.name,
          isOpen: open,
          imageUrl: cafeteria.imageUrl,
        ));

    try {
      await _catalog.setTradingStatus(cafeteriaId: cafeteria.id, isOpen: open);
      if (!mounted) return;
      context.showAppSuccess(
        open ? '${cafeteria.name} is now accepting orders' : '${cafeteria.name} is paused',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _selected = cafeteria);
      context.showAppError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: ErrorRetry(
          message: AppError.from(_error!).message,
          onRetry: _load,
        ),
      );
    }

    final cafeterias = _cafeterias;
    if (cafeterias == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (cafeterias.isEmpty) return _noAccess();

    final selected = _selected!;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: _CafeteriaPicker(
            cafeterias: cafeterias,
            selected: selected,
            onChanged: (c) => setState(() => _selected = c),
          ),
          actions: [
            _bell(),
            const SizedBox(width: AppSpacing.sm),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Queue'),
              Tab(text: 'Menu'),
              Tab(text: 'Specials'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: Column(
          children: [
            _TradingToggle(
              cafeteria: selected,
              onChanged: _toggleTrading,
            ),
            Expanded(
              child: TabBarView(
                // The inner order-status tabs used to be a second swipeable
                // TabBarView nested inside this one, so horizontal drags were
                // ambiguous. The inner one is now a filter chip row.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  QueueTab(cafeteria: selected),
                  ManagementTab(cafeteria: selected),
                  SpecialsTab(cafeteria: selected),
                  SettingsTab(
                    profile: widget.profile,
                    cafeteria: selected,
                    onCafeteriaChanged: _replaceCafeteria,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bell() => StreamBuilder<List<AppNotification>>(
        stream: _notifications.watch(UserRole.staff),
        builder: (context, snapshot) {
          final notices = (snapshot.data ?? const <AppNotification>[])
              .where(
                (notice) =>
                    !_dismissedNotificationIds.contains(notice.id),
              )
              .toList();
          final unread = NotificationRepository.hasUnread(notices, _lastSeen);

          return IconButton(
            tooltip: unread ? 'Notices, unread' : 'Notices',
            onPressed: () async {
              final seenAt = await _notifications.markSeen();
              if (!mounted) return;
              setState(() => _lastSeen = seenAt);
              if (!context.mounted) return;
              await showNotificationSheet(
                context,
                notices,
                dismissedIds: _dismissedNotificationIds,
                onDismiss: _dismissNotification,
              );
            },
            icon: Badge(
              isLabelVisible: unread,
              child: const Icon(Icons.notifications_outlined),
            ),
          );
        },
      );

  Widget _noAccess() => Scaffold(
        appBar: AppBar(title: const Text('Staff dashboard')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'No cafeteria assigned yet',
          message: 'Your account is set up, but an administrator still needs to '
              'assign you to a cafeteria before you can manage a menu or see '
              'orders.',
          action: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
        ),
      );
}

class _CafeteriaPicker extends StatelessWidget {
  const _CafeteriaPicker({
    required this.cafeterias,
    required this.selected,
    required this.onChanged,
  });

  final List<Cafeteria> cafeterias;
  final Cafeteria selected;
  final ValueChanged<Cafeteria> onChanged;

  @override
  Widget build(BuildContext context) {
    // A single assignment is the common case; a dropdown there is just noise.
    if (cafeterias.length == 1) {
      return Text(selected.name, style: Theme.of(context).textTheme.titleLarge);
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected.id,
        isExpanded: true,
        // The old dropdown hid its arrow with SizedBox.shrink(), removing the
        // only affordance that it could be tapped.
        icon: const Icon(Icons.arrow_drop_down),
        style: Theme.of(context).textTheme.titleLarge,
        items: cafeterias
            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
            .toList(),
        onChanged: (id) {
          if (id == null) return;
          onChanged(cafeterias.firstWhere((c) => c.id == id));
        },
      ),
    );
  }
}

/// REQ-82 / REQ-84.
class _TradingToggle extends StatelessWidget {
  const _TradingToggle({required this.cafeteria, required this.onChanged});

  final Cafeteria cafeteria;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = cafeteria.isOpen;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: open ? AppColors.successContainer : AppColors.dangerContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            open ? Icons.storefront : Icons.pause_circle_outline,
            color: open ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open ? 'Accepting orders' : 'Paused',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: open
                        ? AppColors.onSuccessContainer
                        : AppColors.onDangerContainer,
                  ),
                ),
                Text(
                  open
                      ? 'Students can add items and check out.'
                      : 'Students can browse but cannot order.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: open
                        ? AppColors.onSuccessContainer
                        : AppColors.onDangerContainer,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: open,
            onChanged: onChanged,
            // The old control was an unlabelled GestureDetector with no
            // tooltip, invisible to a screen reader as a button.
          ),
        ],
      ),
    );
  }
}
