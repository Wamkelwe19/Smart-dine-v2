import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../models/models.dart';

/// All authentication and profile access.
///
/// Replaces the inline Supabase calls that were scattered through
/// `login_page.dart` and `signup_page.dart`.
class AuthRepository {
  AuthRepository({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved lazily so the repository can be constructed (and
  /// subclassed in tests) without a live Supabase instance.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentSession != null;

  /// REQ-15: drives the splash-screen auth gate, and picks up the session that
  /// arrives via deep link when Google sign-in returns.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ------------------------------------------------------------- sign in --

  /// REQ-25 / REQ-7: authenticate from a student or staff number.
  ///
  /// The number is exchanged for an email through `lookup_login_email`, a
  /// SECURITY DEFINER function. The old code read the `profiles` table directly
  /// while unauthenticated and reported "Student/Staff ID not found" — an
  /// enumeration oracle, and the reason `profiles` had to stay anon-readable.
  ///
  /// The function now returns an unusable address for an unknown number, so an
  /// unregistered number and a wrong password fail identically (REQ-30).
  Future<AuthResponse> signInWithNumber({
    required String number,
    required String password,
  }) async {
    final email = await _client.rpc(
      'lookup_login_email',
      params: {'p_number': number.trim()},
    ) as String?;

    if (email == null || email.isEmpty) {
      throw const AppError('Incorrect student/staff number or password.');
    }

    return _client.auth.signInWithPassword(email: email, password: password);
  }

  // ------------------------------------------------------------- sign up --

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    required String surname,
    required String number,
    required String phone,
    required UserRole role,
  }) async {
    // REQ-23: a specific message rather than a generic failure.
    final available = await isIdentifierAvailable(number);
    if (!available) {
      throw const AppError(
        'That student/staff number is already registered. Try signing in instead.',
      );
    }

    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      // The profile row is created by the handle_new_user trigger from this
      // metadata. Note that `role` grants nothing: staff permissions come from
      // membership of staff_cafeterias, which only an administrator can set.
      data: {
        'name': name.trim(),
        'surname': surname.trim(),
        'student_staff_id': number.trim(),
        'phone': phone.trim(),
        'role': role.wire,
      },
      emailRedirectTo: AppConfig.authRedirectUrl,
    );
  }

  Future<bool> isIdentifierAvailable(String number) async {
    final result = await _client.rpc(
      'is_identifier_available',
      params: {'p_number': number.trim()},
    );
    return result == true;
  }

  // -------------------------------------------------------------- google --

  /// Opens Google sign-in in a browser tab; the session returns through the
  /// `za.ac.ump.smartdine://login-callback` deep link registered in
  /// AndroidManifest.xml and Info.plist, and arrives on [authStateChanges].
  ///
  /// This uses the OAuth redirect flow rather than the native `google_sign_in`
  /// package deliberately: it needs no extra dependency and no per-platform
  /// client IDs beyond what Supabase's dashboard already holds, which makes it
  /// far less brittle to set up. The native flow is a later polish step.
  Future<bool> signInWithGoogle() async {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: AppConfig.authRedirectUrl,
      // An in-app browser tab (Custom Tab) rather than the full browser app:
      // the return link lands in the running app (launchMode singleTask),
      // which closes the tab, instead of leaving Chrome open behind it.
      authScreenLaunchMode: LaunchMode.inAppBrowserView,
      // Always offer the account picker, so a shared phone can switch account.
      queryParams: const {'prompt': 'select_account'},
    );
  }

  /// What Google told us about the user, for prefilling "Finish setting up".
  ({String? firstName, String? surname, String? email, String? avatarUrl})
      get providerDetails {
    final user = currentUser;
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    String? text(Object? v) {
      final t = v?.toString().trim();
      return t == null || t.isEmpty ? null : t;
    }

    var first = text(meta['given_name']);
    var last = text(meta['family_name']);
    final full = text(meta['full_name']) ?? text(meta['name']);
    if ((first == null || last == null) && full != null) {
      final parts = full.split(RegExp(r'\s+'));
      first ??= parts.first;
      if (parts.length > 1) last ??= parts.sublist(1).join(' ');
    }
    return (
      firstName: first,
      surname: last,
      email: user?.email ?? text(meta['email']),
      avatarUrl: text(meta['avatar_url']) ?? text(meta['picture']),
    );
  }

  /// Creates the caller's profile row from their sign-in details if the
  /// new-user trigger did not (an account that existed before it, or a
  /// trigger that failed). Returns false where the server does not have
  /// migration 0011 yet.
  Future<bool> ensureProfile() async {
    try {
      await _client.rpc('ensure_profile');
      return true;
    } on PostgrestException {
      return false;
    }
  }

  // ------------------------------------------------------------- profile --

  Future<Profile?> loadProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final row = await _client
        .from('profiles')
        // `*` rather than a column list, so a column added by a later
        // migration (avatar_url, 0011) never breaks sign-in on a database
        // that has not been migrated yet.
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return Profile.fromMap(row);
  }

  /// One-time completion for Google accounts, which arrive with no role and no
  /// student number. The role is fixed here and cannot be changed afterwards
  /// (BR-1) — the database enforces that with a trigger, not just the UI.
  Future<Profile> completeProfile({
    required UserRole role,
    required String number,
    required String name,
    required String surname,
    required String phone,
  }) async {
    final row = await _client.rpc('complete_profile', params: {
      'p_role': role.wire,
      'p_number': number.trim(),
      'p_name': name.trim(),
      'p_surname': surname.trim(),
      'p_phone': phone.trim(),
    });

    return Profile.fromMap(Map<String, dynamic>.from(row as Map));
  }

  // ------------------------------------------------------------ sign out --

  /// REQ-91 and REQ-93.
  ///
  /// The student path previously only navigated back to the login screen and
  /// never called `signOut()`, so the session stayed alive and kept refreshing.
  /// Reserved stock is released first, so a departing user does not strand it.
  Future<void> signOut() async {
    try {
      await _client.rpc('release_my_reservations');
    } catch (_) {
      // Never block sign-out on the release; the scheduled sweep is the
      // backstop and will reclaim the stock within five minutes.
    }
    await _client.auth.signOut();
  }
}
