import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error/app_error.dart';

/// Result of a payment attempt, as our server sees it.
enum PaymentOutcome {
  /// Yoco confirmed the charge (and the amount matched).
  paid,

  /// Yoco reported a final failure (declined or amount mismatch).
  failed,

  /// The student has not finished on Yoco yet, or Yoco has not confirmed.
  /// Not a failure: the webhook may still mark it paid.
  pending,

  /// We could not reach a verdict (unknown reference, service unreachable).
  abandoned;

  bool get isPaid => this == PaymentOutcome.paid;
  bool get isFinal =>
      this == PaymentOutcome.paid || this == PaymentOutcome.failed;
}

/// Yoco, through the Edge Functions in `supabase/functions/`.
///
/// The app never sees a card number. The old checkout collected the PAN, expiry
/// and CVV into Flutter `TextFormField`s, which puts the project inside PCI-DSS
/// scope for no benefit — and was broken anyway, because the 16-character limit
/// counted the dashes the formatter inserted, so a real 16-digit card could not
/// be typed. Yoco's hosted page collects the card instead, which satisfies
/// REQ-58 far better than a validated-but-inert form did.
class PaymentRepository {
  PaymentRepository({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved lazily so the repository can be constructed (and
  /// subclassed in tests) without a live Supabase instance.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  /// Starts a transaction. The Edge Function reads the amount from the order
  /// server-side, so a tampered client cannot ask to pay less.
  Future<({String authorizationUrl, String reference})> initialize(
    String orderId,
  ) async {
    final response = await _client.functions.invoke(
      'yoco-initialize',
      body: {'order_id': orderId},
    );

    final data = response.data;
    if (data is! Map || data['authorization_url'] == null) {
      throw AppError(
        'Could not start the payment. Please try again.',
        debugDetail: data?.toString(),
      );
    }

    return (
      authorizationUrl: data['authorization_url'] as String,
      reference: data['reference'] as String,
    );
  }

  /// The "come back and verify" step. Asks our server for the result of the
  /// signed Yoco webhook, after it has re-checked the amount.
  ///
  /// Idempotent with the webhook: whichever arrives first wins.
  Future<PaymentOutcome> verify(String reference) async {
    final response = await _client.functions.invoke(
      'yoco-verify',
      body: {'reference': reference},
    );

    final data = response.data;
    if (data is! Map) return PaymentOutcome.abandoned;
    if (data['paid'] == true) return PaymentOutcome.paid;

    return switch (data['reason']) {
      'failed' || 'amount_mismatch' => PaymentOutcome.failed,
      'pending' => PaymentOutcome.pending,
      _ => PaymentOutcome.abandoned,
    };
  }

  /// Opens the hosted checkout page. Returns once the browser has been
  /// launched — NOT when the student has paid. Callers must wait for the
  /// student to come back (see CardPaymentSheet) before verifying.
  Future<void> openCheckout(String authorizationUrl) async {
    final uri = Uri.parse(authorizationUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw const AppError(
        'Could not open the payment page. Check that you have a browser installed.',
      );
    }
  }

  /// Polls the Yoco webhook result after the student has returned to the app.
  ///
  /// Yoco can take a few seconds to deliver its webhook, so this retries until
  /// a final answer (paid / failed) or the
  /// attempts run out, in which case the result is `pending`.
  Future<PaymentOutcome> verifyWithRetry(
    String reference, {
    int attempts = 6,
    Duration gap = const Duration(milliseconds: 2500),
  }) async {
    PaymentOutcome outcome = PaymentOutcome.pending;

    for (var i = 0; i < attempts; i++) {
      try {
        outcome = await verify(reference);
        if (outcome.isFinal) return outcome;
      } catch (_) {
        // Keep trying; a transient failure here is not the final answer.
      }
      if (i < attempts - 1) await Future<void>.delayed(gap);
    }

    return outcome == PaymentOutcome.abandoned
        ? PaymentOutcome.pending
        : outcome;
  }
}
