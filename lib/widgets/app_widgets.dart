import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';

/// Shared components.
///
/// These replace eleven duplicated or near-duplicated blocks catalogued during
/// the audit — four separate copies of the logo, two notification sheets, two
/// cafeteria dropdowns, five variants of a status dot, and two different
/// visual languages for the same food card.

// ------------------------------------------------------------------- logo --

/// One logo widget. There were four copies, and the sign-up screen's differed
/// enough (no Hero, no ClipOval, fixed height) to break the shared Hero flight.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 160, this.useHero = true});

  final double size;
  final bool useHero;

  @override
  Widget build(BuildContext context) {
    final image = ClipOval(
      child: Image.asset(
        'Ump Smart Dine Logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: AppColors.brandPale,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.restaurant, size: size * 0.45, color: AppColors.primary),
        ),
      ),
    );

    return Semantics(
      label: 'UMP Smart Dine logo',
      image: true,
      child: useHero ? Hero(tag: 'app_logo', child: image) : image,
    );
  }
}

// ------------------------------------------------------------ status pill --

enum StatusTone { positive, negative, warning, neutral }

/// A labelled status chip.
///
/// REQ-4: the text is never optional. The old screens signalled open/closed
/// with an 8px coloured dot and the staff availability bar with colour alone,
/// both of which are invisible to a colour-blind user.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.dense = false,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      StatusTone.positive => (AppColors.success, AppColors.successContainer),
      StatusTone.negative => (AppColors.danger, AppColors.dangerContainer),
      StatusTone.warning => (AppColors.warning, AppColors.warningContainer),
      StatusTone.neutral => (AppColors.secondary, AppColors.secondaryContainer),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? AppSpacing.xxs : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: (dense
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ empty state --

/// Replaces the bare `Center(Text(...))` placeholders — two of which rendered
/// white text on a white background and so looked like blank screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A full-screen error state that offers a retry, so a network failure leaves
/// the interface somewhere the user can recover from (REQ-14, REQ-121).
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        message: message,
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
}

// -------------------------------------------------------------- skeletons --

/// A shimmering placeholder block. Every loading state in the old app was a
/// bare centred spinner, which gives no sense of what is arriving.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = AppRadius.xs,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.outline;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.25 + (_controller.value * 0.2)),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- section --

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xl,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            ?trailing,
          ],
        ),
      );
}

// ------------------------------------------------------------ quantity UI --

/// Accessible quantity stepper.
///
/// The old cart used `IconButton`s with `iconSize: 16`, `padding: zero` and
/// `constraints: BoxConstraints()`, the last of which removes IconButton's
/// built-in 48dp floor. The effective target was about 16x16dp — the worst
/// accessibility defect in the app.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    this.busy = false,
  });

  final int quantity;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: busy ? null : onDecrease,
            icon: const Icon(Icons.remove, size: 18),
            tooltip: 'Remove one',
            constraints: const BoxConstraints(
              minWidth: AppA11y.minTouchTarget,
              minHeight: AppA11y.minTouchTarget,
            ),
          ),
          SizedBox(
            width: 28,
            child: busy
                ? const Center(
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
          ),
          IconButton(
            onPressed: busy ? null : onIncrease,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Add one more',
            constraints: const BoxConstraints(
              minWidth: AppA11y.minTouchTarget,
              minHeight: AppA11y.minTouchTarget,
            ),
          ),
        ],
      ),
    );
  }
}
