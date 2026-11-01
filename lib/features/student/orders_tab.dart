import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/order_item_row.dart';
import 'card_payment_sheet.dart';

/// REQ-68: the student's orders, live, with where each one is.
///
/// This tab previously rendered `Center(Text('My Orders Content'))` in white on
/// a white background, so it appeared completely blank. The realtime stream was
/// also built inside `build()`, so every rebuild opened a new subscription.
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key, required this.profile});

  final Profile profile;

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  final OrderRepository _orders = OrderRepository();
  late Stream<List<Order>> _stream = _orders.watchMyOrders(widget.profile.id);

  void _resubscribe() =>
      setState(() => _stream = _orders.watchMyOrders(widget.profile.id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: StreamBuilder<List<Order>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: AppError.from(snapshot.error!).message,
              onRetry: _resubscribe,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'Once you place an order it will appear here so you can '
                  'track it through to collection.',
            );
          }

          final active = orders.where((o) => !o.status.isTerminal).toList();
          final past = orders.where((o) => o.status.isTerminal).toList();

          return RefreshIndicator(
            onRefresh: () async => _resubscribe(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.lg,
                AppSpacing.gutter,
                AppSpacing.contentBottomInset(context),
              ),
              children: [
                if (active.isNotEmpty) ...[
                  Text('In progress',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  for (final order in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _OrderCard(
                        key: ValueKey(order.id),
                        order: order,
                        repository: _orders,
                        initiallyExpanded: true,
                      ),
                    ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Past orders',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  for (final order in past)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _OrderCard(
                        key: ValueKey(order.id),
                        order: order,
                        repository: _orders,
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({
    super.key,
    required this.order,
    required this.repository,
    this.initiallyExpanded = false,
  });

  final Order order;
  final OrderRepository repository;
  final bool initiallyExpanded;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  final PaymentRepository _payments = PaymentRepository();

  Order? _detail;
  bool _loadingDetail = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _loadDetail();
  }

  @override
  void didUpdateWidget(covariant _OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A status or payment change arrives through realtime; refresh the lines'
    // context only when something the card shows has moved.
    if (oldWidget.order.status != widget.order.status ||
        oldWidget.order.paymentState != widget.order.paymentState) {
      _detail = null;
      if (widget.initiallyExpanded) _loadDetail();
    }
  }

  /// Line items are not in the realtime payload, so they load on demand.
  Future<void> _loadDetail() async {
    if (_detail != null || _loadingDetail) return;
    setState(() => _loadingDetail = true);
    try {
      final detail = await widget.repository.fetchOrderDetail(widget.order.id);
      if (mounted) setState(() => _detail = detail);
    } catch (_) {
      // Leave the summary showing; the header already carries the essentials.
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          'Order ${widget.order.collectionRef} will be cancelled and the items '
          'returned to the menu. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _run(() async {
      await widget.repository.cancel(widget.order.id);
      if (mounted) context.showAppSuccess('Order cancelled');
    });
  }

  Future<void> _payByCard() => _run(() async {
        final outcome =
            await payOrderByCard(context, orderId: widget.order.id, payments: _payments);
        if (!mounted) return;
        _report(outcome);
      });

  Future<void> _checkPayment() => _run(() async {
        final reference =
            await widget.repository.latestPaymentReference(widget.order.id);
        if (reference == null) {
          if (mounted) context.showAppInfo('No card payment has been started for this order.');
          return;
        }
        final outcome = await _payments.verifyWithRetry(reference, attempts: 2);
        if (mounted) _report(outcome);
      });

  void _report(PaymentOutcome outcome) {
    switch (outcome) {
      case PaymentOutcome.paid:
        context.showAppSuccess('Payment confirmed for ${widget.order.collectionRef}');
      case PaymentOutcome.failed:
        context.showAppError(const AppError(
            'That payment did not go through. You can try again or pay at the counter.'));
      case PaymentOutcome.pending:
      case PaymentOutcome.abandoned:
        context.showAppInfo(
            'Yoco has not confirmed a payment yet. It updates on its own if you paid.');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final detail = _detail;

    final unpaid = order.paymentState != PaymentState.paid &&
        order.paymentState != PaymentState.refunded &&
        order.status != OrderStatus.cancelled &&
        order.status != OrderStatus.collected;
    final canPayByCard = unpaid;
    final canCheck = unpaid && order.paymentMethod == PaymentMethod.card;

    return Card(
      elevation: AppElevation.none,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(
          color: order.status == OrderStatus.ready
              ? AppColors.success
              : theme.colorScheme.outline,
          width: order.status == OrderStatus.ready ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        onExpansionChanged: (open) {
          if (open) _loadDetail();
        },
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.collectionRef,
                      style: theme.textTheme.titleMedium?.copyWith(
                        letterSpacing: 2,
                        color: theme.colorScheme.primary,
                      )),
                  Text(
                    [
                      ?detail?.cafeteriaName,
                      TimeAgo.format(order.createdAt),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            _statusPill(order.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            children: [
              Text(order.totalLabel, style: theme.textTheme.titleSmall),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                order.paymentMethod == PaymentMethod.card
                    ? Icons.credit_card
                    : Icons.payments_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  order.paymentLabel,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: switch (order.paymentState) {
                      PaymentState.paid => AppColors.success,
                      PaymentState.failed => AppColors.danger,
                      _ => AppColors.textSecondary,
                    },
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (order.status != OrderStatus.cancelled)
                  _StatusStepper(status: order.status)
                else
                  _CancelledNote(),
                const SizedBox(height: AppSpacing.md),
                if (_loadingDetail)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (detail != null)
                  ...detail.items.map((item) => OrderItemRow(item: item)),
                if (canPayByCard || canCheck || order.status.isCancellable) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (canPayByCard)
                        FilledButton.icon(
                          onPressed: _busy ? null : _payByCard,
                          icon: const Icon(Icons.credit_card),
                          label: const Text('Pay by card'),
                        ),
                      if (canCheck)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _checkPayment,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Check payment'),
                        ),
                      if (order.status.isCancellable)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _cancel,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel order'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                        ),
                    ],
                  ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(OrderStatus status) => StatusPill(
        label: status.label,
        tone: switch (status) {
          OrderStatus.isNew => StatusTone.neutral,
          OrderStatus.preparing => StatusTone.warning,
          OrderStatus.ready => StatusTone.positive,
          OrderStatus.collected => StatusTone.positive,
          OrderStatus.cancelled => StatusTone.negative,
        },
        dense: true,
      );
}

/// Placed → Preparing → Ready → Collected, so a student can see at a glance
/// how far along their food is.
class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.status});

  final OrderStatus status;

  static const _steps = [
    (OrderStatus.isNew, 'Placed', Icons.receipt_long_outlined),
    (OrderStatus.preparing, 'Preparing', Icons.soup_kitchen_outlined),
    (OrderStatus.ready, 'Ready', Icons.notifications_active_outlined),
    (OrderStatus.collected, 'Collected', Icons.check_circle_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _steps.indexWhere((s) => s.$1 == status);

    return Semantics(
      label: 'Order status: ${status.label}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= current
                          ? (i == 2 && current == 2
                              ? AppColors.success
                              : AppColors.primary)
                          : AppColors.surfaceMuted,
                    ),
                    child: Icon(
                      _steps[i].$3,
                      size: 18,
                      color: i <= current ? Colors.white : AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _steps[i].$2,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: i <= current
                          ? AppColors.textPrimary
                          : AppColors.textDisabled,
                      fontWeight: i == current ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (i < _steps.length - 1)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: i < current ? AppColors.primary : AppColors.outline,
                      borderRadius: AppRadius.pillRadius,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CancelledNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.dangerContainer,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This order was cancelled and its items returned to the menu.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
            ),
          ],
        ),
      );
}
