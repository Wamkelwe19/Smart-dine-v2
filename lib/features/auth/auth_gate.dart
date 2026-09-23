import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/app_widgets.dart';
import '../staff/staff_shell.dart';
import '../student/student_shell.dart';
import 'complete_profile_screen.dart';
import 'login_screen.dart';

/// The app's entry point and the thing that makes auto-login work (REQ-15).
///
/// The old splash screen ran a 2.5s timer and then navigated to the login form
/// unconditionally — there was no session check anywhere in the codebase, so a
/// returning user always had to sign in again even though supabase_flutter had
/// kept their session the whole time.
///
/// This gate instead:
///   * shows the brand animation while it resolves the stored session,
///   * routes straight to the right interface when one exists (REQ-1),
///   * sends an incomplete profile (a fresh Google account) to the completion
///     screen first,
///   * and stays subscribed, so the session that arrives by deep link when
///     Google sign-in returns lands the user in the app without another tap.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _GateState { resolving, signedOut, needsProfile, student, staff, error }

class _AuthGateState extends State<AuthGate> with SingleTickerProviderStateMixin {
  final AuthRepository _auth = AuthRepository();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  StreamSubscription<AuthState>? _subscription;
  _GateState _state = _GateState.resolving;
  Profile? _profile;

  /// Shown on the login screen after a sign-in that did not complete.
  String? _signInError;

  /// Shown when the session exists but the profile could not be read.
  String? _loadError;

  /// Each resolve takes a ticket; only the newest one may change the screen.
  /// Two resolves overlap at start-up (the replayed initial session and the
  /// timed one), and the slower of them used to win whatever it found.
  int _ticket = 0;

  /// The splash is shown for at least this long so it reads as a brand moment
  /// rather than a flicker, but resolution happens in parallel — it does not
  /// add to the wait the way the old fixed 2.5s delay did.
  static const _minimumSplash = Duration(milliseconds: 1200);

  /// Events that can change who is signed in or what their profile is.
  /// tokenRefreshed is deliberately absent: re-resolving on every refresh
  /// meant a network blip during a refresh dropped a signed-in user onto the
  /// login screen.
  static const _relevant = {
    AuthChangeEvent.initialSession,
    AuthChangeEvent.signedIn,
    AuthChangeEvent.signedOut,
    AuthChangeEvent.userUpdated,
  };

  @override
  void initState() {
    super.initState();
    _subscription = _auth.authStateChanges.listen(
      (state) {
        if (mounted && _relevant.contains(state.event)) _resolve();
      },
      // A failed Google return (cancelled, expired or invalid code) arrives as
      // an error on this stream. It used to be unhandled, so nothing happened.
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _signInError = 'Google sign-in did not complete. Please try again.';
          if (!_auth.isSignedIn) _state = _GateState.signedOut;
        });
      },
    );
    _resolve(withMinimumSplash: true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolve({bool withMinimumSplash = false}) async {
    final ticket = ++_ticket;
    final splash = withMinimumSplash
        ? Future<void>.delayed(_minimumSplash)
        : Future<void>.value();

    _GateState next;
    Profile? profile;
    String? loadError;

    if (!_auth.isSignedIn) {
      next = _GateState.signedOut;
    } else {
      try {
        profile = await _auth.loadProfile();
        if (profile == null && await _auth.ensureProfile()) {
          // The new-user trigger did not create a row (an older account, or
          // a trigger that failed): create it from the sign-in details.
          profile = await _auth.loadProfile();
        }

        if (profile == null) {
          loadError = 'Your account has no profile yet. Please sign out and '
              'sign in again, or ask the administrator for help.';
          next = _GateState.error;
        } else if (!profile.isComplete) {
          next = _GateState.needsProfile;
        } else {
          // REQ-27: role decides the interface, and the user is never asked.
          next = profile.role.isStaff ? _GateState.staff : _GateState.student;
        }
      } catch (error) {
        // Offline, or the database refusing: keep the session and offer a
        // retry. Signing the user out here lost their session over a blip.
        loadError = AppError.from(error).message;
        next = _GateState.error;
      }
    }

    await splash;
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _state = next;
      _profile = profile;
      _loadError = loadError;
      if (next != _GateState.signedOut) _signInError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _GateState.resolving => _Splash(controller: _controller),
      _GateState.signedOut => LoginScreen(
          key: ValueKey(_signInError),
          initialError: _signInError,
        ),
      _GateState.needsProfile => CompleteProfileScreen(
          onCompleted: () => _resolve(),
        ),
      _GateState.student => StudentShell(profile: _profile!),
      _GateState.staff => StaffShell(profile: _profile!),
      _GateState.error => Scaffold(
          body: SafeArea(
            child: ErrorRetry(
              message: _loadError ?? 'Could not load your account.',
              onRetry: () {
                setState(() => _state = _GateState.resolving);
                _resolve();
              },
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: TextButton.icon(
                onPressed: _auth.signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ),
        ),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: controller, curve: Curves.easeIn);
    final scale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    );

    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 180),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Eat smart, study more',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
