import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';

/// Registration.
///
/// The old form held a `_formKey` and called `validate()`, but not one field
/// was ever given a validator — so `validate()` always returned true and an
/// entirely empty form went straight to the network. Every field below is now
/// validated before submission (REQ-17, REQ-21, REQ-22), and the student/staff
/// number is checked for uniqueness with a specific message (REQ-23).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _number = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final AuthRepository _auth = AuthRepository();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final controller in [
      _name, _surname, _number, _phone, _email, _password, _confirm,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isStudent => widget.role == UserRole.student;
  String get _idLabel => _isStudent ? 'Student number' : 'Staff number';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await _auth.signUp(
        email: _email.text,
        password: _password.text,
        name: _name.text,
        surname: _surname.text,
        number: _number.text,
        phone: _phone.text,
        role: widget.role,
      );

      if (!mounted) return;
      // REQ-24: tell the user a verification message has been sent.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.mark_email_unread_outlined,
              size: 40, color: AppColors.success),
          title: const Text('Check your email'),
          content: Text(
            'We have sent a verification link to ${_email.text.trim()}. '
            'Open it to activate your account, then sign in.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
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
      appBar: AppBar(title: Text('Sign up as ${widget.role.label.toLowerCase()}')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                // Errors appear as the user corrects them rather than only on
                // submit, which is how a form should behave.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Create your account',
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'You will sign in with your ${_idLabel.toLowerCase()}.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    _field(
                      controller: _name,
                      label: 'First name',
                      icon: Icons.person_outline,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => Validators.required(v, 'first name'),
                    ),
                    _field(
                      controller: _surname,
                      label: 'Surname',
                      icon: Icons.person_outline,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => Validators.required(v, 'surname'),
                    ),
                    _field(
                      controller: _number,
                      label: _idLabel,
                      icon: Icons.badge_outlined,
                      validator: (v) =>
                          Validators.identifier(v, isStudent: _isStudent),
                    ),
                    _field(
                      controller: _phone,
                      label: 'Phone number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: Validators.phone,
                    ),
                    _field(
                      controller: _email,
                      label: 'Email address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: Validators.email,
                    ),
                    _field(
                      controller: _password,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      helper: 'At least 8 characters.',
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                      ),
                      validator: Validators.password,
                    ),
                    _field(
                      controller: _confirm,
                      label: 'Confirm password',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      validator: (v) =>
                          Validators.confirmPassword(v, _password.text),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'We collect only what the app needs to operate: your '
                      'name, number, phone and email. It is never shared with '
                      'anyone else.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscure = false,
    String? helper,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        obscureText: obscure,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          prefixIcon: Icon(icon),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
