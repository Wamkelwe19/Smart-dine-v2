import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/app_widgets.dart';
import 'role_selection_screen.dart';

/// Sign in with a student or staff number.
///
/// Changes from the old screen:
///   * the "Test Supabase Connection" debug button and its `print()` calls are
///     gone (REQ-32, REQ-115),
///   * the number is exchanged for an email through a SECURITY DEFINER function
///     rather than an unauthenticated read of `profiles` (REQ-111),
///   * an unknown number and a wrong password now produce the same message
///     (REQ-30),
///   * navigation is left to the AuthGate, which listens to auth state, rather
///     than being pushed imperatively after a 1.2s delay.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialError});

  /// A sign-in that did not complete (e.g. Google returned an error), shown
  /// once when the screen appears.
  final String? initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthRepository _auth = AuthRepository();

  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final error = widget.initialError;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.showAppError(AppError(error));
      });
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    // REQ-26: an empty field is rejected without touching the network.
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await _auth.signInWithNumber(
        number: _numberController.text,
        password: _passwordController.text,
      );
      // The AuthGate is listening; it routes by role from here (REQ-1, REQ-29).
    } catch (error) {
      if (!mounted) return;
      final appError = AppError.from(error);
      // An account created with Google has no password, so number + password
      // can never work for it; say so rather than only "incorrect password".
      context.showAppError(
        AppConfig.isGoogleSignInConfigured &&
                appError.message.startsWith('Incorrect')
            ? AppError('${appError.message} Signed up with Google? Use '
                '"Continue with Google" instead.')
            : appError,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      await _auth.signInWithGoogle();
      // Returns through the deep link; the AuthGate picks the session up.
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              // Keeps the form readable on a tablet or a desktop window rather
              // than stretching it across the full width.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 140)),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sign in to order ahead and skip the queue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    TextFormField(
                      controller: _numberController,
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Student / Staff number',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) =>
                          Validators.required(value, 'student or staff number'),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    TextFormField(
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                      validator: (value) =>
                          Validators.required(value, 'password'),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // REQ-3: the control is disabled and shows progress for the
                    // duration of the network operation.
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),

                    if (AppConfig.isGoogleSignInConfigured) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md),
                            child: Text(
                              'or',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const RoleSelectionScreen(),
                                    ),
                                  ),
                          child: const Text('Sign up'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
