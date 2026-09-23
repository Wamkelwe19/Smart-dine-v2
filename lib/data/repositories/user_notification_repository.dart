import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Notices addressed to the signed-in user: "Order K7P2QX is ready", "New
/// order ...". Written by database triggers (migration 0011); the app only
/// reads them and marks them read.
class UserNotificationRepository {
  UserNotificationRepository({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved lazily so the repository can be constructed (and
  /// subclassed in tests) without a live Supabase instance.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  /// The user's newest fifty, live. RLS already limits rows to the caller;
  /// the filter keeps the realtime channel narrow.
  Stream<List<UserNotification>> watchMine(String userId) => _client
      .from('user_notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(UserNotification.fromMap).toList());

  Future<void> markAllRead(String userId) => _client
      .from('user_notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('user_id', userId)
      .isFilter('read_at', null);

  Future<void> markRead(String id) => _client
      .from('user_notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);
}
