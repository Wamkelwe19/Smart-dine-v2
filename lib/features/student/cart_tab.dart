import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/payment_repository.dart';
import '../../widgets/app_widgets.dart';
import 'card_payment_sheet.dart';
import 'cart_controller.dart';
import 'order_confirmation_screen.dart';

/// Cart and checkout.
///
/// The raw card form is gone. It collected the PAN, expiry and CVV into Flutter
/// text fields — which puts the project in PCI-DSS scope — and was broken
/// regardless: the 16-character limit counted the dashes its own formatter
/// inserted, so a real 16-digit card could not be entered, and the CVV field
/// was hard-limited to three digits. Paystack's hosted page collects the card
/// instead, so the app never touches it (REQ-58).
class CartTab extends StatefulWidget {
  const CartTab({
    super.key,
    required this.cart,
    required this.onBrowse,
    required this.onOrderPlaced,
  });

  final CartController cart;
  final VoidCallback onBrowse;
  final VoidCallback onOrderPlaced;

  @override
  State<CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<CartTab> {
  final PaymentRepository _payments = PaymentRepository();

  PaymentMethod _method = PaymentMethod.cash;
  bool _checkingOut = false;

  Future<void> _checkout() async {
    setState(() => _checkingOut = true);

    // Snapshot the lines for the confirmation screen: the cart empties once
    // the reservations become an order.
    final lines = List<CartLine>.of(widget.cart.lines);

    final Order order;
    try {
      // REQ-62: the order is created first, so the amount exists server-side
      // before any payment is initialised.
      order = await widget.cart.checkout(_method);
    } catch (error) {
      if (mounted) {
        setState(() => _checkingOut = false);
        context.showAppError(error);
      }
      // The cart may have partially changed; reload rather than guess.
      await widget.cart.load();
      return;
    }

    if (!mounted) return;

    if (_method == PaymentMethod.cash) {
      setState(() => _checkingOut = false);
      await _showConfirmation(order, lines: lines, paid: false);
      return;
    }

    // Card. From here the order exists whatever happens, so a payment problem
    // is reported on the confirmation screen, not as a bare error that leaves
    // the student wondering whether they ordered at all.
    PaymentOutcome? outcome;
    String? paymentNote;
    try {
      outcome = await payOrderByCard(context, orderId: order.id, payments: _payments);
    } catch (error) {
      paymentNote = AppError.from(error).message;
    }

    if (!mounted) return;
    setState(() => _checkingOut = false);
    await _showConfirmation(
      order,
      lines: lines,
      paid: outcome?.isPaid ?? false,
      outcome: outcome,
      paymentNote: paymentNote,
    );
  }

  Future<void> _showConfirmation(
    Order order, {
    required List<CartLine> lines,
    required bool paid,
    PaymentOutcome? outcome,
    String? paymentNote,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderConfirmationScreen(
          order: order,
          lines: lines,
          paid: paid,
          outcome: outcome,
          paymentNote: paymentNote,
        ),
      ),
    );
    if (mounted) widget.onOrderPlaced();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My cart')),
      body: ListenableBuilder(
        listenable: widget.cart,
        builder: (context, _) {
          final cart = widget.cart;

          if (cart.isLoading && cart.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          // A failed load is not an empty cart: say so and offer a retry.
          if (cart.error != null && cart.isEmpty) {
            return ErrorRetry(
              message: AppError.from(cart.error!).message,
              onRetry: cart.load,
            );
          }

          // REQ-59: checkout is unreachable with an empty cart.
          if (cart.isEmpty) {
            return EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your cart is empty',
              message: 'Browse a cafeteria menu and add something you fancy.',
              action: FilledButton.icon(
                onPressed: widget.onBrowse,
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('Browse menus'),
              ),
            );
          }

          return Column(
            children: [
              Expanded(child: _lines(cart)),
              _summary(cart),
            ],
          );
        },
      ),
    );
  }

  Widget _lines(CartController cart) => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        itemCount: cart.lines.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final line = cart.lines[index];
          return _CartLineCard(
            line: line,
            busy: cart.isLineBusy(line),
            onIncrease: () => _guard(() => cart.increase(line)),
            onDecrease: () => _guard(() => cart.decrease(line)),
            onRemove: () => _guard(() => cart.remove(line)),
          );
        },
      );

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    }
  }

  Widget _summary(CartController cart) {
    final theme = Theme.of(context);
    final blocked = cart.spansMultipleCafeterias;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.contentBottomInset(context),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.sheetRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // REQ-53: explain rather than silently fail at checkout.
          if (blocked) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 20, color: AppColors.onWarningContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your cart has items from more than one cafeteria. '
                      'Remove some so one order goes to one outlet.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.onWarningContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          Text('Payment method', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          // REQ-55: exactly two methods, defaulting to cash.
          SegmentedButton<PaymentMethod>(
            segments: [
              const ButtonSegment(
                value: PaymentMethod.cash,
                label: Text('Cash'),
                icon: Icon(Icons.payments_outlined),
              ),
              ButtonSegment(
                value: PaymentMethod.card,
                label: const Text('Card'),
                icon: const Icon(Icons.credit_card),
                enabled: AppConfig.isCardPaymentConfigured,
              ),
            ],
            selected: {_method},
            onSelectionChanged: _checkingOut
                ? null
                : (selection) => setState(() => _method = selection.first),
          ),
          if (!AppConfig.isCardPaymentConfigured)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Card payment is not configured for this build. '
                'Cash on collection is available.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text('Total', style: theme.textTheme.titleMedium),
              ),
              // REQ-54: the sum of each line, in rand, two decimal places.
              Text(
                Money.format(cart.totalCents),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          FilledButton(
            onPressed: (_checkingOut || blocked) ? null : _checkout,
            child: _checkingOut
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(_method == PaymentMethod.cash
                    ? 'Place order · pay at counter'
                    : 'Pay ${Money.format(cart.totalCents)}'),
          ),
        ],
      ),
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.line,
    required this.busy,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  final CartLine line;
  final bool busy;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(line.item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: AppRadius.cardRadius,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Card(
        elevation: AppElevation.none,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: SizedBox(
                  height: 64,
                  width: 64,
                  child: line.item.imageUrl == null
                      ? Container(
                          color: AppColors.brandPale,
                          child: const Icon(Icons.restaurant_menu,
                              color: AppColors.primary),
                        )
                      : Image.network(
                          line.item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.brandPale,
                            child: const Icon(Icons.restaurant_menu,
                                color: AppColors.primary),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    // The variety, or a combo's parts and choices.
                    if (line.details != null)
                      Text(
                        line.details!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text.rich(
                      TextSpan(
                        text: '${line.unitPriceLabel} each',
                        children: [
                          if (line.isDiscounted) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: Money.format(line.regularUnitPriceCents),
                              style: const TextStyle(
                                  decoration: TextDecoration.lineThrough),
                            ),
                            TextSpan(
                              text: '  ${line.item.special!.badgeLabel}',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      line.lineTotalLabel,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
              QuantityStepper(
                quantity: line.quantity,
                busy: busy,
                onDecrease: onDecrease,
                onIncrease: onIncrease,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
