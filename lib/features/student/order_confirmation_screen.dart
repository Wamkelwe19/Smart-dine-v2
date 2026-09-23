import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/payment_repository.dart';

/// REQ-61: issues the collection reference in a form staff can match against
/// the queue.
///
/// The old checkout showed a grey snackbar reading "Order placed! (Cash)" and
/// wrote nothing anywhere.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({
    super.key,
    required this.order,
    required this.paid,
    this.lines = const [],
    this.outcome,
    this.paymentNote,
  });

  final Order order;
  final bool paid;

  /// What was ordered, with each line's variety or combo choices.
  final List<CartLine> lines;

  final PaymentOutcome? outcome;

  /// Why card payment could not start (e.g. not set up yet). The order still
  /// stands and can be paid at the counter or later from Orders.
  final String? paymentNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = outcome == PaymentOutcome.failed;
    final pending = outcome == PaymentOutcome.pending ||
        outcome == PaymentOutcome.abandoned;
    final notStarted = paymentNote != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Order placed'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline
                        : pending || notStarted
                            ? Icons.hourglass_top
                            : Icons.check_circle_outline,
                    size: 72,
                    color: failed
                        ? AppColors.danger
                        : pending || notStarted
                            ? AppColors.warning
                            : AppColors.success,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    failed
                        ? 'Payment did not go through'
                        : notStarted
                            ? 'Order placed — not paid yet'
                            : pending
                                ? 'Payment still confirming'
                                : 'You are all set',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    paymentNote != null
                        ? '$paymentNote Your order is placed: pay at the '
                            'counter when you collect, or try card again from '
                            'Orders.'
                        : _subtitle(failed: failed, pending: pending),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // The reference is the whole point of this screen, so it is
                  // large, selectable and copyable.
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: AppRadius.cardRadius,
                      border: Border.all(color: theme.colorScheme.primary),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Collection reference',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SelectableText(
                          order.collectionRef,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: order.collectionRef));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Reference copied')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                  ),

                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    for (final line in lines) _lineRow(context, line),
                    const Divider(height: AppSpacing.xl),
                  ] else
                    const SizedBox(height: AppSpacing.xl),
                  _row(context, 'Total', order.totalLabel),
                  _row(context, 'Payment', order.paymentMethod.label),
                  _row(
                    context,
                    'Status',
                    paid ? 'Paid' : 'Pay at the counter',
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('View my orders'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle({required bool failed, required bool pending}) {
    if (failed) {
      return 'Your order has been created but not paid for. You can still pay '
          'at the counter when you collect.';
    }
    if (pending) {
      return 'Paystack has not confirmed the payment yet. If you paid, your '
          'order updates on its own shortly. Otherwise pay at the counter, or '
          'try card again from Orders.';
    }
    if (order.paymentMethod == PaymentMethod.cash) {
      return 'Show this reference at the counter and pay when you collect.';
    }
    return 'Payment confirmed. Show this reference when you collect.';
  }

  Widget _lineRow(BuildContext context, CartLine line) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text('${line.quantity}×', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.item.name, style: theme.textTheme.bodyMedium),
                if (line.details != null)
                  Text(
                    line.details!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Text(line.lineTotalLabel, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      );
}
