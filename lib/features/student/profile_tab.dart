import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';

/// REQ-114 and the rest of TBD-12.
///
/// This tab previously rendered `Center(Text('Profile Content'))` in white on a
/// white background — indistinguishable from a blank screen.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.profile});

  final Profile profile;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final AuthRepository _auth = AuthRepository();
  bool _busy = false;

  /// REQ-91 / REQ-93. The old student sign-out only navigated back to the login
  /// screen — it never called `auth.signOut()`, so the session stayed alive and
  /// kept refreshing its token.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Anything still in your cart will be released back to the menu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      // signOut() releases the reservations before ending the session.
      await _auth.signOut();
      // The AuthGate is listening and will show the login screen.
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
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.contentBottomInset(context),
        ),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    _initials(profile),
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  profile.fullName.isEmpty ? profile.displayName : profile.fullName,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  profile.role.label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          _DetailTile(
            icon: Icons.badge_outlined,
            label: 'Student / staff number',
            value: profile.studentStaffId ?? 'Not set',
          ),
          _DetailTile(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.email ?? 'Not set',
          ),
          _DetailTile(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: profile.phone ?? 'Not set',
          ),

          const SizedBox(height: AppSpacing.xl),
          Text('Your data', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'We store your name, student or staff number, phone number and '
            'email address, and use them only to run this app. They are not '
            'shared with anyone beyond the hosting platform.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          // REQ-114: a route to deletion. Doing it in-app would need an
          // authenticated admin endpoint, so this states the process honestly
          // rather than pretending to offer a button that works.
          OutlinedButton.icon(
            onPressed: () => _showDeletionInfo(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Request account deletion'),
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
      ),
    );
  }

  void _showDeletionInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request account deletion'),
        content: const Text(
          'Email the cafeteria services team from your registered address '
          'asking for your UMP Smart Dine account to be deleted. Your profile '
          'and order history will be removed within 30 days.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _initials(Profile profile) {
    final first = profile.name?.trim();
    final last = profile.surname?.trim();
    final a = (first != null && first.isNotEmpty) ? first[0] : '';
    final b = (last != null && last.isNotEmpty) ? last[0] : '';
    final initials = '$a$b'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
