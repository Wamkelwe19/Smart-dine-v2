import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/app_widgets.dart';

/// One-time profile completion for accounts created through Google.
///
/// A Google account arrives with an email and possibly a name, but no role and
/// no student number — and the app is built around signing in with that number.
/// This screen collects the missing pieces once. Afterwards the account is
/// indistinguishable from one created through the sign-up form, and the user is
/// auto-logged-in on every subsequent launch (REQ-15).
///
/// The role set here is final: BR-1 says it is fixed at registration, and a
/// database trigger enforces that rather than only the UI.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _number = TextEditingController();
  final _phone = TextEditingController();

  final AuthRepository _auth = AuthRepository();
  UserRole _role = UserRole.student;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prefillFromGoogle();
  }

  /// Google supplies the first name and surname separately (given_name /
  /// family_name), falling back to splitting the display name. The email and
  /// photo come across automatically; only the number, phone and role are
  /// left for the student to type.
  void _prefillFromGoogle() {
    final details = _auth.providerDetails;
    if (details.firstName != null) _name.text = details.firstName!;
    if (details.surname != null) _surname.text = details.surname!;
  }

  @override
  void dispose() {
    for (final c in [_name, _surname, _number, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await _auth.completeProfile(
        role: _role,
        number: _number.text,
        name: _name.text,
        surname: _surname.text,
        phone: _phone.text,
      );
      if (!mounted) return;
      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _auth.providerDetails;
    final email = details.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finish setting up'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: details.avatarUrl == null
                          ? const AppLogo(size: 100)
                          : CircleAvatar(
                              radius: 44,
                              backgroundColor: AppColors.brandPale,
                              foregroundImage: NetworkImage(details.avatarUrl!),
                              child: const Icon(Icons.person,
                                  size: 40, color: AppColors.primary),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Almost there',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      email.isEmpty
                          ? 'We just need a few details to finish your account.'
                          : 'Signed in as $email. We just need a few more details.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    Text('I am a', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<UserRole>(
                      segments: const [
                        ButtonSegment(
                          value: UserRole.student,
                          label: Text('Student'),
                          icon: Icon(Icons.school_outlined),
                        ),
                        ButtonSegment(
                          value: UserRole.staff,
                          label: Text('Staff'),
                          icon: Icon(Icons.badge_outlined),
                        ),
                      ],
                      selected: {_role},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) =>
                              setState(() => _role = selection.first),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'This cannot be changed later.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    _field(
                      controller: _name,
                      label: 'First name',
                      icon: Icons.person_outline,
                      validator: (v) => Validators.required(v, 'first name'),
                    ),
                    _field(
                      controller: _surname,
                      label: 'Surname',
                      icon: Icons.person_outline,
                      validator: (v) => Validators.required(v, 'surname'),
                    ),
                    _field(
                      controller: _number,
                      label: _role == UserRole.student
                          ? 'Student number'
                          : 'Staff number',
                      icon: Icons.badge_outlined,
                      validator: (v) => Validators.identifier(
                        v,
                        isStudent: _role == UserRole.student,
                      ),
                    ),
                    _field(
                      controller: _phone,
                      label: 'Phone number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: Validators.phone,
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
                          : const Text('Finish'),
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
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: TextFormField(
          controller: controller,
          enabled: !_busy,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
          ),
        ),
      );
}
