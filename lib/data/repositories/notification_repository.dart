import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Notices, and the unread indicator.
class NotificationRepository {
  NotificationRepository({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved lazily so the repository can be constructed (and
  /// subclassed in tests) without a live Supabase instance.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  static const _lastSeenKey = 'last_seen_notification_timestamp';
  static const _dismissedKeyPrefix = 'dismissed_notifications_';

  /// REQ-85 / REQ-86 / REQ-9: notices for this audience, newest first,
  /// capped at fifty.
  ///
  /// RLS also restricts the rows to the caller's own role, so the audience
  /// filter here is an optimisation rather than the security boundary. The
  /// staff side previously pulled every notice for a cafeteria and filtered by
  /// audience in Dart.
  Stream<List<AppNotification>> watch(UserRole role) => _client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('audience', role.wire)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromMap).toList());

  /// REQ-89, closing TBD-11. Notices could previously only be created by
  /// inserting a row by hand in the Supabase dashboard.
  Future<void> publish({
    required String cafeteriaId,
    required UserRole audience,
    required String title,
    required String message,
  }) async {
    await _client.from('notifications').insert({
      'cafeteria_id': cafeteriaId,
      'audience': audience.wire,
      'type': 'announcement',
      'title': title.trim(),
      'message': message.trim(),
    });
  }

  /// REQ-88: the indicator state survives a restart.
  Future<DateTime?> lastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSeenKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<DateTime> markSeen() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenKey, now.toIso8601String());
    return now;
  }

  Future<Set<String>> dismissedIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('$_dismissedKeyPrefix$userId') ?? const [])
        .toSet();
  }

  Future<void> dismiss({
    required String userId,
    required String notificationId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_dismissedKeyPrefix$userId';
    final ids = prefs.getStringList(key) ?? <String>[];
    if (ids.contains(notificationId)) return;
    ids.add(notificationId);
    if (!await prefs.setStringList(key, ids)) {
      throw StateError('Could not save the dismissed notification.');
    }
  }

  /// REQ-87.
  static bool hasUnread(List<AppNotification> notices, DateTime? lastSeen) {
    if (notices.isEmpty) return false;
    if (lastSeen == null) return true;
    return notices.any(
      (notice) =>
          notice.createdAt != null && notice.createdAt!.isAfter(lastSeen),
    );
  }
}
