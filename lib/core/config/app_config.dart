/// Build-time configuration (REQ-112).
///
/// Nothing secret lives in this file. Values are injected at build time with:
///
///   flutter run --dart-define-from-file=env.json
///   flutter build apk --release --dart-define-from-file=env.json
///
/// `env.json` is gitignored. Copy `env.example.json` and fill it in.
///
/// The Supabase *publishable* key is safe to ship in the client — it is visible
/// in any compiled binary. Row level security is what actually protects the
/// data. The Supabase *secret* / service-role key and the Paystack secret key
/// must never appear here; they belong in Edge Function secrets only.
library;

class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Paystack *public* key (pk_test_… / pk_live_…). Safe on the client; it can
  /// only initialise a transaction, never verify or refund one.
  static const String paystackPublicKey = String.fromEnvironment(
    'PAYSTACK_PUBLIC_KEY',
  );

  /// Google OAuth client IDs. The web client ID is the audience Supabase
  /// validates the ID token against, so it is required on every platform.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Custom URL scheme registered in AndroidManifest.xml and Info.plist.
  static const String redirectScheme = 'za.ac.ump.smartdine';

  static const String authRedirectUrl = '$redirectScheme://login-callback';

  static const String paymentRedirectUrl = '$redirectScheme://payment-callback';

  /// True when Google sign-in has been configured for this build. The sign-in
  /// button is hidden rather than shown broken when it is false.
  static bool get isGoogleSignInConfigured => googleWebClientId.isNotEmpty;

  /// True when card payment is available. Cash checkout still works without it.
  static bool get isCardPaymentConfigured => paystackPublicKey.isNotEmpty;

  /// Fails fast at startup with an actionable message rather than surfacing an
  /// opaque Supabase error on the first query.
  static void validate() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    ];

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing build configuration: ${missing.join(', ')}.\n'
        'Copy env.example.json to env.json, fill in the values, then run with:\n'
        '  flutter run --dart-define-from-file=env.json',
      );
    }
  }
}
