import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/notifications/local_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import 'notification_center.dart';

/// Notification settings, for students and staff alike.
///
/// Shows whether the phone allows notifications at all, a master switch,
/// one switch per kind of notification the user's role receives, sound and
/// vibration, and a test button.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.center});

  final NotificationCenter center;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool? _systemAllowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSystemState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the phone's settings may have changed the permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSystemState();
  }

  Future<void> _refreshSystemState() async {
    final allowed = await LocalNotifier.instance.areEnabled();
    if (mounted) setState(() => _systemAllowed = allowed);
  }

  Future<void> _allow() async {
    final granted = await LocalNotifier.instance.requestPermission();
    if (!granted) {
      // Android only shows its prompt twice; after that, settings is the way.
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
    await _refreshSystemState();
  }

  Future<void> _test() async {
    final center = widget.center;
    if (!center.prefs.enabled) {
      context.showAppInfo('Turn on phone notifications first.');
      return;
    }
    if (_systemAllowed == false) {
      context.showAppError(const AppError(
          'Your phone is blocking notifications from UMP Smart Dine. Tap '
          '"Allow" above.'));
      return;
    }
    await center.sendTest();
    if (mounted) context.showAppSuccess('Test notification sent');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = widget.center;
    final kinds = NotificationKind.forRole(center.profile.role);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListenableBuilder(
        listenable: center,
        builder: (context, _) {
          final prefs = center.prefs;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xxxl),
            children: [
              if (_systemAllowed == false) ...[
                _Banner(
                  icon: Icons.notifications_off_outlined,
                  text: 'Your phone is blocking notifications from UMP Smart '
                      'Dine, so none will appear.',
                  action: 'Allow',
                  onAction: _allow,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              _Section(
                children: [
                  SwitchListTile(
                    value: prefs.enabled,
                    onChanged: (v) => center.updatePrefs(prefs.copyWith(enabled: v)),
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Phone notifications'),
                    subtitle: Text(
                      prefs.enabled
                          ? 'On. Everything also stays in the bell inbox.'
                          : 'Off. Updates still collect in the bell inbox.',
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: prefs.soundAndVibration,
                    onChanged: prefs.enabled
                        ? (v) => center.updatePrefs(
                            prefs.copyWith(soundAndVibration: v))
                        : null,
                    secondary: const Icon(Icons.volume_up_outlined),
                    title: const Text('Sound and vibration'),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              Text(
                center.profile.role.isStaff ? 'Tell me about' : 'Tell me when',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Section(
                children: [
                  for (var i = 0; i < kinds.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    SwitchListTile(
                      value: !prefs.muted.contains(kinds[i]),
                      onChanged: prefs.enabled
                          ? (v) => center.updatePrefs(prefs.toggled(kinds[i], v))
                          : null,
                      title: Text(kinds[i].label),
                      subtitle: Text(kinds[i].description),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: _test,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Send a test notification'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () =>
                    AppSettings.openAppSettings(type: AppSettingsType.notification),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open phone notification settings'),
              ),

              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Notifications arrive while UMP Smart Dine is open or '
                        'running in the background. If you close the app '
                        'completely, you will see what you missed in the bell '
                        'inbox next time you open it.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        elevation: AppElevation.none,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(children: children),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.onWarningContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.onWarningContainer),
              ),
            ),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      );
}
