import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/notifications/local_notifier.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../data/models/models.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/user_notification_repository.dart';

/// Everything notification-related for the signed-in user.
///
/// * Streams their personal notices ("Order K7P2QX is ready", "New order
///   ...") and the announcements for their role.
/// * Drives the bell's unread count and the inbox sheet.
/// * Turns each NEW notice into a phone notification, if the user's settings
///   allow that kind.
///
/// One instance lives in each shell for as long as the user is signed in.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({
    required this.profile,
    UserNotificationRepository? personal,
    NotificationRepository? announcements,
    LocalNotifier? notifier,
  })  : _personal = personal ?? UserNotificationRepository(),
        _announcements = announcements ?? NotificationRepository(),
        _notifier = notifier ?? LocalNotifier.instance;

  final Profile profile;
  final UserNotificationRepository _personal;
  final NotificationRepository _announcements;
  final LocalNotifier _notifier;

  StreamSubscription<List<UserNotification>>? _personalSub;
  StreamSubscription<List<AppNotification>>? _announcementSub;

  List<UserNotification> _personalItems = const [];
  List<AppNotification> _announcementItems = const [];
  DateTime? _announcementsSeen;
  NotificationPrefs _prefs = const NotificationPrefs();
  bool _started = false;

  /// Server-clock watermarks: the newest notice already shown on the phone.
  DateTime? _personalMark;
  DateTime? _announcementMark;

  List<UserNotification> get personal => _personalItems;
  List<AppNotification> get announcements => _announcementItems;
  NotificationPrefs get prefs => _prefs;

  /// An announcement is unread until the inbox is marked read after it.
  bool isUnread(AppNotification notice) =>
      notice.createdAt != null &&
      (_announcementsSeen == null || notice.createdAt!.isAfter(_announcementsSeen!));

  int get unreadCount =>
      _personalItems.where((n) => !n.isRead).length +
      _announcementItems.where(isUnread).length;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _prefs = await NotificationPrefs.load();
    _announcementsSeen = await _announcements.lastSeen();
    _personalMark = await NotificationPrefs.watermark(profile.id, 'personal');
    _announcementMark = await NotificationPrefs.watermark(profile.id, 'announcements');
    notifyListeners();

    // Ask once, the first time someone signs in on this phone.
    if (!_prefs.permissionAsked) {
      await _notifier.requestPermission();
      _prefs = _prefs.copyWith(permissionAsked: true);
      await _prefs.save();
    }

    _personalSub = _personal.watchMine(profile.id).listen(
          _onPersonal,
          // Before migration 0011 the table does not exist; the inbox then
          // simply shows announcements.
          onError: (Object error) => debugPrint('user_notifications: $error'),
        );
    _announcementSub = _announcements.watch(profile.role).listen(
          _onAnnouncements,
          onError: (Object error) => debugPrint('notifications: $error'),
        );
  }

  void _onPersonal(List<UserNotification> rows) {
    _personalItems = rows;
    notifyListeners();

    final fresh = _fresh(rows.map((r) => (r.createdAt, r)), _personalMark);
    if (fresh.$2 != null) {
      _personalMark = fresh.$2;
      NotificationPrefs.setWatermark(profile.id, 'personal', fresh.$2!);
    }
    for (final notice in fresh.$1) {
      if (!_prefs.allows(notice.kind)) continue;
      _notifier.show(
        title: notice.title,
        body: notice.body,
        orderUpdate: notice.kind.isOrderUpdate,
        soundAndVibration: _prefs.soundAndVibration,
        payload: 'orders',
      );
    }
  }

  void _onAnnouncements(List<AppNotification> rows) {
    _announcementItems = rows;
    notifyListeners();

    final fresh = _fresh(rows.map((r) => (r.createdAt, r)), _announcementMark);
    if (fresh.$2 != null) {
      _announcementMark = fresh.$2;
      NotificationPrefs.setWatermark(profile.id, 'announcements', fresh.$2!);
    }
    if (!_prefs.allows(NotificationKind.announcement)) return;
    for (final notice in fresh.$1) {
      _notifier.show(
        title: notice.title?.isNotEmpty == true ? notice.title! : 'UMP Smart Dine',
        body: notice.message,
        orderUpdate: false,
        soundAndVibration: _prefs.soundAndVibration,
        payload: 'notices',
      );
    }
  }

  /// The rows newer than [mark], oldest first, and the new watermark.
  ///
  /// With no watermark yet (first sign-in on this phone), nothing is shown:
  /// the watermark is set to the newest existing row, so only notices that
  /// arrive from now on pop up.
  static (List<T>, DateTime?) _fresh<T>(
    Iterable<(DateTime?, T)> rows,
    DateTime? mark,
  ) {
    final dated = rows.where((r) => r.$1 != null).toList()
      ..sort((a, b) => a.$1!.compareTo(b.$1!));
    if (dated.isEmpty) return (const [], mark);

    final newest = dated.last.$1!;
    if (mark == null) return (const [], newest);

    final fresh = [
      for (final r in dated)
        if (r.$1!.isAfter(mark)) r.$2,
    ];
    return (fresh, newest.isAfter(mark) ? newest : mark);
  }

  Future<void> markAllRead() async {
    _announcementsSeen = await _announcements.markSeen();
    final now = DateTime.now();
    _personalItems = [
      for (final n in _personalItems)
        n.isRead
            ? n
            : UserNotification(
                id: n.id,
                kind: n.kind,
                title: n.title,
                body: n.body,
                orderId: n.orderId,
                createdAt: n.createdAt,
                readAt: now,
              ),
    ];
    notifyListeners();
    try {
      await _personal.markAllRead(profile.id);
    } catch (error) {
      debugPrint('markAllRead: $error');
    }
  }

  Future<void> updatePrefs(NotificationPrefs prefs) async {
    _prefs = prefs;
    notifyListeners();
    await prefs.save();
  }

  /// "Send a test notification" in settings.
  Future<void> sendTest() => _notifier.show(
        title: 'Notifications are working',
        body: profile.role.isStaff
            ? 'You will be told about new orders and cancellations here.'
            : 'You will be told here when your order is being prepared and '
                'when it is ready to collect.',
        orderUpdate: true,
        soundAndVibration: _prefs.soundAndVibration,
        payload: 'orders',
      );

  @override
  void dispose() {
    _personalSub?.cancel();
    _announcementSub?.cancel();
    super.dispose();
  }
}
