import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';

/// The user's notification choices, kept on this phone.
///
/// Phone notifications are shown by the app itself (no push service), so the
/// choices only need to live where the app runs.
class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.soundAndVibration = true,
    this.muted = const {},
    this.permissionAsked = false,
  });

  /// The master switch for phone notifications. The in-app inbox keeps
  /// everything regardless.
  final bool enabled;

  final bool soundAndVibration;

  /// Kinds the user switched off.
  final Set<NotificationKind> muted;

  /// Whether we have already shown Android's "Allow notifications?" prompt,
  /// so it is asked once rather than on every launch.
  final bool permissionAsked;

  bool allows(NotificationKind kind) => enabled && !muted.contains(kind);

  NotificationPrefs copyWith({
    bool? enabled,
    bool? soundAndVibration,
    Set<NotificationKind>? muted,
    bool? permissionAsked,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        soundAndVibration: soundAndVibration ?? this.soundAndVibration,
        muted: muted ?? this.muted,
        permissionAsked: permissionAsked ?? this.permissionAsked,
      );

  NotificationPrefs toggled(NotificationKind kind, bool on) => copyWith(
        muted: on ? ({...muted}..remove(kind)) : {...muted, kind},
      );

  static const _enabledKey = 'notifications.enabled';
  static const _soundKey = 'notifications.sound_and_vibration';
  static const _mutedKey = 'notifications.muted';
  static const _askedKey = 'notifications.permission_asked';

  static Future<NotificationPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationPrefs(
      enabled: prefs.getBool(_enabledKey) ?? true,
      soundAndVibration: prefs.getBool(_soundKey) ?? true,
      muted: (prefs.getStringList(_mutedKey) ?? const [])
          .map(NotificationKind.parse)
          .toSet(),
      permissionAsked: prefs.getBool(_askedKey) ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setBool(_soundKey, soundAndVibration);
    await prefs.setStringList(_mutedKey, muted.map((k) => k.wire).toList());
    await prefs.setBool(_askedKey, permissionAsked);
  }

  // ------------------------------------------------------------ watermarks --
  // The newest notice already turned into a phone notification, per user and
  // per stream, in the SERVER's clock. Only newer notices pop up, so a restart
  // never replays old ones and a wrong phone clock cannot skip new ones.

  static String _watermarkKey(String userId, String stream) =>
      'notifications.delivered.$stream.$userId';

  static Future<DateTime?> watermark(String userId, String stream) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_watermarkKey(userId, stream));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> setWatermark(
      String userId, String stream, DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _watermarkKey(userId, stream), value.toUtc().toIso8601String());
  }
}
