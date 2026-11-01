import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/app_colors.dart';

/// Shows phone notifications from inside the app (no push service).
///
/// They appear while the app is open or running in the background. Every one
/// carries the UMP Smart Dine icon: the white silhouette `ic_stat_notify` in
/// the status bar, and the full-colour logo as the large icon.
class LocalNotifier {
  LocalNotifier._();

  static final LocalNotifier instance = LocalNotifier._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();

  bool _ready = false;
  String? _launchPayload;

  /// Payloads of notifications the user tapped while the app was running.
  Stream<String> get taps => _taps.stream;

  /// The payload of the notification that launched the app, once.
  String? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Channel ids. Android fixes a channel's sound and vibration when it is
  /// created, so "quiet" versions exist for the sound-and-vibration switch.
  static const _orders = 'order_updates';
  static const _ordersQuiet = 'order_updates_quiet';
  static const _notices = 'announcements';
  static const _noticesQuiet = 'announcements_quiet';

  Future<void> init() async {
    if (_ready || !_supported) return;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notify'),
          // Permission is asked at a sensible moment (first sign-in), not at
          // launch before the user knows what the app is.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _taps.add(payload);
        },
      );

      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _launchPayload = launch!.notificationResponse?.payload;
      }

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        for (final channel in const [
          AndroidNotificationChannel(
            _orders,
            'Order updates',
            description: 'Your orders: placed, preparing, ready, collected.',
            importance: Importance.high,
          ),
          AndroidNotificationChannel(
            _ordersQuiet,
            'Order updates (silent)',
            description: 'Order updates without sound or vibration.',
            importance: Importance.defaultImportance,
            playSound: false,
            enableVibration: false,
          ),
          AndroidNotificationChannel(
            _notices,
            'Announcements',
            description: 'Notices from the cafeterias.',
          ),
          AndroidNotificationChannel(
            _noticesQuiet,
            'Announcements (silent)',
            description: 'Cafeteria notices without sound or vibration.',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        ]) {
          await android.createNotificationChannel(channel);
        }
      }
      _ready = true;
    } catch (error) {
      // Notifications are a convenience; the app must start without them.
      debugPrint('LocalNotifier.init failed: $error');
    }
  }

  /// Asks for permission (Android 13+ and iOS). Returns whether notifications
  /// can be shown.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  /// Whether the phone currently lets this app show notifications.
  Future<bool> areEnabled() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.areNotificationsEnabled() ?? false;
    return true;
  }

  int _nextId = 0;

  Future<void> show({
    required String title,
    required String body,
    required bool orderUpdate,
    required bool soundAndVibration,
    String? payload,
  }) async {
    if (!_ready) return;

    final channel = orderUpdate
        ? (soundAndVibration ? _orders : _ordersQuiet)
        : (soundAndVibration ? _notices : _noticesQuiet);
    final channelName = switch (channel) {
      _orders => 'Order updates',
      _ordersQuiet => 'Order updates (silent)',
      _notices => 'Announcements',
      _ => 'Announcements (silent)',
    };

    try {
      await _plugin.show(
        // Unique per notification in this run, so several stack rather than
        // replace each other.
        id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 30) + _nextId++,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            channelName,
            icon: 'ic_stat_notify',
            largeIcon: const DrawableResourceAndroidBitmap('notification_large_icon'),
            color: AppColors.primary,
            importance: orderUpdate && soundAndVibration
                ? Importance.high
                : Importance.defaultImportance,
            priority: orderUpdate ? Priority.high : Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body, contentTitle: title),
            category: orderUpdate ? AndroidNotificationCategory.status : null,
            playSound: soundAndVibration,
            enableVibration: soundAndVibration,
            ticker: title,
          ),
          iOS: DarwinNotificationDetails(
            presentSound: soundAndVibration,
            presentBanner: true,
            presentList: true,
          ),
        ),
      );
    } catch (error) {
      debugPrint('LocalNotifier.show failed: $error');
    }
  }
}
