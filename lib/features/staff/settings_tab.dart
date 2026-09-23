import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../widgets/cafeteria_image.dart';
import '../shared/notification_center.dart';
import '../shared/notification_settings_screen.dart';

/// Staff settings, and the notice composer.
///
/// The Settings tab was `Center(Text('Settings Screen'))`. The composer closes
/// REQ-89 / TBD-11 — notices could previously only be created by inserting a
/// row by hand in the Supabase dashboard.
class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.profile,
    required this.cafeteria,
    required this.notifications,
    this.onCafeteriaChanged,
  });

  final Profile profile;
  final Cafeteria cafeteria;
  final NotificationCenter notifications;

  /// Called after the cover photo changes, so the shell holds the new value.
  final ValueChanged<Cafeteria>? onCafeteriaChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final AuthRepository _auth = AuthRepository();
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _auth.signOut();
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compose() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoticeComposer(cafeteria: widget.cafeteria),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      children: [
        Text('Signed in as', style: theme.textTheme.bodySmall
            ?.copyWith(color: AppColors.textSecondary)),
        Text(
          profile.fullName.isEmpty ? profile.displayName : profile.fullName,
          style: theme.textTheme.titleLarge,
        ),
        Text(
          '${profile.role.label} · ${profile.studentStaffId ?? ''}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),

        const SizedBox(height: AppSpacing.xxl),
        Text('Announcements', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Publish a notice to students or to other staff at '
          '${widget.cafeteria.name}.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _compose,
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('Write a notice'),
        ),

        const SizedBox(height: AppSpacing.xxl),
        Text('Notifications', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          elevation: AppElevation.none,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius,
            side: BorderSide(color: theme.colorScheme.outline),
          ),
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification settings'),
            subtitle: const Text('New orders, cancellations, sound'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  NotificationSettingsScreen(center: widget.notifications),
            )),
          ),
        ),

        const SizedBox(height: AppSpacing.xxl),
        Text('Your cafeteria', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The cover photo students see on the home page and at the top of '
          'your menu.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        _CafeteriaPhotoCard(
          cafeteria: widget.cafeteria,
          onChanged: widget.onCafeteriaChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Cafeteria assignments are managed by an administrator. If you need '
          'access to another outlet, ask them to add it to your account.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),

        const SizedBox(height: AppSpacing.xxl),
        FilledButton.icon(
          onPressed: _busy ? null : _signOut,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          icon: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// The cafeteria's cover photo, with upload, replace and remove.
///
/// Stored in the same `menu-images` bucket under the cafeteria's folder, so
/// the existing storage policy already limits it to this cafeteria's staff.
class _CafeteriaPhotoCard extends StatefulWidget {
  const _CafeteriaPhotoCard({required this.cafeteria, this.onChanged});

  final Cafeteria cafeteria;
  final ValueChanged<Cafeteria>? onChanged;

  @override
  State<_CafeteriaPhotoCard> createState() => _CafeteriaPhotoCardState();
}

class _CafeteriaPhotoCardState extends State<_CafeteriaPhotoCard> {
  final CatalogRepository _catalog = CatalogRepository();
  bool _busy = false;

  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final url = await _catalog.pickAndUploadImage(
        cafeteriaId: widget.cafeteria.id,
        prefix: 'cover-',
      );
      if (url == null) return;
      await _apply(url);
      if (!mounted) return;
      context.showAppSuccess('Cover photo updated');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await _apply(null);
      if (!mounted) return;
      context.showAppSuccess('Cover photo removed');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves the new URL, then removes the replaced object (REQ-81).
  Future<void> _apply(String? url) async {
    final previous = widget.cafeteria.imageUrl;
    await _catalog.setCafeteriaImage(
      cafeteriaId: widget.cafeteria.id,
      imageUrl: url,
    );
    if (previous != null && previous != url) {
      await _catalog.deleteImageIfOwned(previous);
    }
    widget.onChanged?.call(Cafeteria(
      id: widget.cafeteria.id,
      name: widget.cafeteria.name,
      isOpen: widget.cafeteria.isOpen,
      imageUrl: url,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cafeteria = widget.cafeteria;
    final hasUpload = cafeteria.imageUrl != null;

    return Card(
      elevation: AppElevation.none,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CafeteriaImage(cafeteria: cafeteria),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x99000000)],
                      stops: [0.4, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: AppSpacing.md,
                  child: Text(
                    cafeteria.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.white),
                  ),
                ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x66FFFFFF),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _upload,
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(hasUpload ? 'Replace photo' : 'Upload photo'),
                  ),
                ),
                if (hasUpload) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    tooltip: 'Remove photo',
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: Text(
              'Landscape photos look best. Up to 5 MB.'
              '${cafeteria.isOpen ? '' : ' Students see it greyed out while you are paused.'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// REQ-89.
class _NoticeComposer extends StatefulWidget {
  const _NoticeComposer({required this.cafeteria});

  final Cafeteria cafeteria;

  @override
  State<_NoticeComposer> createState() => _NoticeComposerState();
}

class _NoticeComposerState extends State<_NoticeComposer> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _message = TextEditingController();
  final _repository = NotificationRepository();

  // BR-11: a notice is addressed to exactly one audience.
  UserRole _audience = UserRole.student;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await _repository.publish(
        cafeteriaId: widget.cafeteria.id,
        audience: _audience,
        title: _title.text,
        message: _message.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showAppSuccess('Notice published');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: [
            Text('Write a notice', style: theme.textTheme.headlineSmall),
            Text(
              'Posted as ${widget.cafeteria.name}.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text('Who should see this?', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(
                  value: UserRole.student,
                  label: Text('Students'),
                  icon: Icon(Icons.school_outlined),
                ),
                ButtonSegment(
                  value: UserRole.staff,
                  label: Text('Staff'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_audience},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _audience = s.first),
            ),
            const SizedBox(height: AppSpacing.xl),

            TextFormField(
              controller: _title,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => Validators.required(v, 'title'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _message,
              enabled: !_busy,
              maxLines: 4,
              maxLength: 280,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Message'),
              validator: (v) => Validators.required(v, 'message'),
            ),
            const SizedBox(height: AppSpacing.lg),

            // REQ-103: the app must not carry allergen or dietary claims,
            // because it holds no such data and a wrong claim could harm.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.onWarningContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Do not include allergen or dietary claims in a notice.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.onWarningContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            FilledButton(
              onPressed: _busy ? null : _publish,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}
