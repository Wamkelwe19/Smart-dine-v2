import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Fails fast with an actionable message if the build was run without
    // --dart-define-from-file=env.json (REQ-112).
    AppConfig.validate();

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        // PKCE is required for the Google OAuth redirect flow and is the
        // recommended flow for mobile clients generally.
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (error) {
    // A misconfigured build should explain itself on screen rather than dying
    // at a grey crash with the reason only in the console.
    runApp(_StartupFailure(message: error.toString()));
    return;
  }

  runApp(const MyApp());
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'UMP Smart Dine could not start',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'See SETUP.md, step 3.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UMP Smart Dine',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Always light (white background), even when the phone is in dark mode.
      themeMode: ThemeMode.light,
      // The gate resolves the stored session and routes by role, which is what
      // makes auto-login work (REQ-1, REQ-15).
      home: const AuthGate(),
    );
  }
}
