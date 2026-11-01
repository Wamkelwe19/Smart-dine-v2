import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/repositories/payment_repository.dart';

/// Pays one order by card: start a Yoco checkout, open its hosted page,
/// wait for the student to come back, then ask our server what happened.
///
/// Throws (an [AppError]-mappable error) only when the payment could not be
/// *started* — the order itself is untouched either way, so the caller can
/// still show it with "pay at the counter".
///
/// The old flow verified immediately after launching the browser, while the
/// student was still typing their card number, so every real payment was
/// reported as not completed.
Future<PaymentOutcome> payOrderByCard(
  BuildContext context, {
  required String orderId,
  PaymentRepository? payments,
}) async {
  final repository = payments ?? PaymentRepository();
  final session = await repository.initialize(orderId);
  await repository.openCheckout(session.authorizationUrl);
  if (!context.mounted) return PaymentOutcome.pending;

  final outcome = await showModalBottomSheet<PaymentOutcome>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => CardPaymentSheet(
      reference: session.reference,
      authorizationUrl: session.authorizationUrl,
      payments: repository,
    ),
  );
  return outcome ?? PaymentOutcome.pending;
}

/// Shown while the student is on Yoco. Verifies when they return — the
/// app coming back to the foreground, or the payment-callback link arriving,
/// whichever is first — or when they tap "I've paid".
class CardPaymentSheet extends StatefulWidget {
  const CardPaymentSheet({
    super.key,
    required this.reference,
    required this.authorizationUrl,
    required this.payments,
  });

  final String reference;
  final String authorizationUrl;
  final PaymentRepository payments;

  @override
  State<CardPaymentSheet> createState() => _CardPaymentSheetState();
}

enum _Phase { waiting, checking, notYet }

class _CardPaymentSheetState extends State<CardPaymentSheet> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<Uri>? _links;
  _Phase _phase = _Phase.waiting;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _check);
    _links = AppLinks().uriLinkStream.listen((uri) {
      if (uri.host == 'payment-callback') _check();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _links?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted || _phase == _Phase.checking) return;
    setState(() => _phase = _Phase.checking);

    final outcome = await widget.payments.verifyWithRetry(widget.reference);
    if (!mounted) return;

    if (outcome.isFinal) {
      Navigator.of(context).pop(outcome);
    } else {
      setState(() => _phase = _Phase.notYet);
    }
  }

  Future<void> _reopen() async {
    setState(() => _phase = _Phase.waiting);
    await widget.payments.openCheckout(widget.authorizationUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (IconData icon, Color colour, String title, String body) = switch (_phase) {
      _Phase.waiting => (
          Icons.credit_card,
          AppColors.primary,
          'Complete your payment',
          'Yoco has opened in your browser. Pay there, then come back to '
              'UMP Smart Dine — we will confirm it automatically.',
        ),
      _Phase.checking => (
          Icons.sync,
          AppColors.secondary,
          'Confirming your payment…',
          'Checking with Yoco. This takes a few seconds.',
        ),
      _Phase.notYet => (
          Icons.hourglass_top,
          AppColors.warning,
          'Not confirmed yet',
          'Yoco has not confirmed a payment for this order. If you paid, '
              'check again in a moment — it also updates on its own. Otherwise '
              'reopen the payment page, or pay at the counter.',
        ),
    };

    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: _phase == _Phase.checking
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: colour),
                      )
                    : Icon(icon, color: colour, size: 30),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _phase == _Phase.checking ? null : _check,
              icon: const Icon(Icons.verified_outlined),
              label: Text(_phase == _Phase.notYet ? 'Check again' : "I've paid — check now"),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_phase == _Phase.notYet)
              OutlinedButton.icon(
                onPressed: _reopen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Reopen payment page'),
              ),
            TextButton(
              onPressed: _phase == _Phase.checking
                  ? null
                  : () => Navigator.of(context).pop(PaymentOutcome.pending),
              child: const Text('Pay later or at the counter'),
            ),
          ],
        ),
      ),
    );
  }
}
