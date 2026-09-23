import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../widgets/app_widgets.dart';
import 'signup_screen.dart';

/// REQ-16: the role is chosen before the registration form is shown.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 120)),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Tell us who you are',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'This decides which version of the app you see, and it '
                    'cannot be changed later.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _RoleCard(
                    icon: Icons.school_outlined,
                    title: 'I am a student',
                    subtitle: 'Browse menus, order ahead and collect.',
                    onTap: () => _goToSignup(context, UserRole.student),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RoleCard(
                    icon: Icons.badge_outlined,
                    title: 'I am a staff member',
                    subtitle: 'Manage a cafeteria menu and order queue.',
                    onTap: () => _goToSignup(context, UserRole.staff),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goToSignup(BuildContext context, UserRole role) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SignupScreen(role: role)),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: AppElevation.none,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Icon(icon, size: 28, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
