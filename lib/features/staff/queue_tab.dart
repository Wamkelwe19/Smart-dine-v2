import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/order_item_row.dart';

/// The live order queue.
///
/// This tab was entirely fabricated before: the three counters were the
/// constants 2, 4 and 3; `_buildOrderList` ignored the status it was passed and
/// rendered five identical placeholder cards; every card showed "12:30 PM" and
/// the same three invented line items; and the advance button's `onPressed` was
/// an empty body. Staff were shown numbers that meant nothing.
///
/// REQ-62 to REQ-67.
class QueueTab extends StatefulWidget {
  const QueueTab({super.key, required this.cafeteria});

  final Cafeteria cafeteria;

  @override
  State<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<QueueTab> {
  final OrderRepository _orders = OrderRepository();

  StreamSubscription<List<Order>>? _subscription;
  List<Order> _queue = const [];
  bool _loading = true;
  Object? _error;
  OrderStatus? _filter;
  String? _busyOrderId;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant QueueTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resubscribe when the staff member switches cafeteria. The old dashboard
    // built its stream inside build(), creating a fresh subscription on every
    // rebuild and never cancelling the previous one.
    if (oldWidget.cafeteria.id != widget.cafeteria.id) {
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    // Assigned directly rather than through setState: this also runs from
    // initState, where there is nothing built yet to mark dirty. The async
    // _refresh() below calls setState once it has data.
    _loading = true;
    _error = null;

    // The realtime stream tells us *when* something changed; the detail fetch
    // brings the line items, which are not part of the realtime payload.
    _subscription = _orders.watchCafeteriaQueue(widget.cafeteria.id).listen(
      (_) => _refresh(),
      onError: (Object error) {
        if (mounted) setState(() => _error = error);
      },
    );
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final queue = await _orders.fetchQueueWithItems(widget.cafeteria.id);
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _advance(Order order) async {
    final next = order.status.next;
    if (next == null) return;

    setState(() => _busyOrderId = order.id);
    try {
      await _orders.advance(order.id, next);
      await _refresh();
      if (!mounted) return;
      context.showAppSuccess('Order ${order.collectionRef} → ${next.label}');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _cancel(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel ${order.collectionRef}?'),
        content: const Text(
          'The student will see the order as cancelled and the items go back '
          'onto the menu.',
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

    setState(() => _busyOrderId = order.id);
    try {
      await _orders.cancel(order.id, reason: 'Cancelled by staff');
      await _refresh();
      if (!mounted) return;
      context.showAppSuccess('Order ${order.collectionRef} cancelled');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  int _countOf(OrderStatus status) =>
      _queue.where((order) => order.status == status).length;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorRetry(
        message: AppError.from(_error!).message,
        onRetry: _refresh,
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    final visible = _filter == null
        ? _queue
        : _queue.where((order) => order.status == _filter).toList();

    return Column(
      children: [
        // REQ-66: real counts, derived from the live queue.
        Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Row(
            children: [
              _stat('New', _countOf(OrderStatus.isNew), AppColors.secondary),
              const SizedBox(width: AppSpacing.md),
              _stat('Preparing', _countOf(OrderStatus.preparing), AppColors.warning),
              const SizedBox(width: AppSpacing.md),
              _stat('Ready', _countOf(OrderStatus.ready), AppColors.success),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            children: [
              _chip('All', null),
              _chip('New', OrderStatus.isNew),
              _chip('Preparing', OrderStatus.preparing),
              _chip('Ready', OrderStatus.ready),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  icon: Icons.inbox_outlined,
                  title: _filter == null ? 'No orders waiting' : 'Nothing here',
                  message: _filter == null
                      ? 'New orders from students will appear here the moment '
                          'they are placed.'
                      : 'No orders are at this stage right now.',
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.gutter),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) => _OrderCard(
                      order: visible[index],
                      busy: _busyOrderId == visible[index].id,
                      onAdvance: () => _advance(visible[index]),
                      onCancel: () => _cancel(visible[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _stat(String label, int count, Color colour) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppRadius.cardRadius,
          border: Border(left: BorderSide(color: colour, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text('$count',
                style: theme.textTheme.headlineSmall?.copyWith(color: colour)),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, OrderStatus? status) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: FilterChip(
          label: Text(label),
          selected: _filter == status,
          onSelected: (_) => setState(() => _filter = status),
        ),
      );
}

/// Handing over an unpaid cash order also takes the payment, so the button
/// says so.
String _advanceLabel(Order order) {
  if (order.status == OrderStatus.ready &&
      order.paymentMethod == PaymentMethod.cash &&
      order.paymentState != PaymentState.paid) {
    return 'Collected · ${order.totalLabel} cash received';
  }
  return order.status.advanceLabel ?? 'Done';
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onAdvance,
    required this.onCancel,
  });

  final Order order;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: AppElevation.none,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        // New orders stand out until someone starts on them.
        side: BorderSide(
          color: order.status == OrderStatus.isNew
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: order.status == OrderStatus.isNew ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // REQ-61: the reference staff match against the student.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    order.collectionRef,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusPill(
                  label: order.status.label,
                  tone: switch (order.status) {
                    OrderStatus.isNew => StatusTone.neutral,
                    OrderStatus.preparing => StatusTone.warning,
                    _ => StatusTone.positive,
                  },
                  icon: switch (order.status) {
                    OrderStatus.isNew => Icons.fiber_new_outlined,
                    OrderStatus.preparing => Icons.soup_kitchen_outlined,
                    _ => Icons.notifications_active_outlined,
                  },
                  dense: true,
                ),
                const Spacer(),
                // Card orders awaiting Paystack are not "pay at counter".
                StatusPill(
                  label: order.paymentLabel,
                  tone: switch (order.paymentState) {
                    PaymentState.paid => StatusTone.positive,
                    PaymentState.failed => StatusTone.negative,
                    _ => StatusTone.warning,
                  },
                  icon: order.paymentMethod == PaymentMethod.card
                      ? Icons.credit_card
                      : Icons.payments_outlined,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  // A real timestamp, not the hardcoded "12:30 PM".
                  '${TimeAgo.clock(order.createdAt)} · ${TimeAgo.format(order.createdAt)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                if (order.studentName != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '· ${order.studentName}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: AppSpacing.xl),

            // Real line items from order_items.
            // With the variety or combo parts, so the right thing is made.
            ...order.items.map((item) => OrderItemRow(item: item)),

            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                Text('Total', style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(order.totalLabel, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Row(
              children: [
                if (order.status.isCancellable)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onCancel,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger),
                      child: const Text('Cancel'),
                    ),
                  ),
                if (order.status.isCancellable)
                  const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: busy ? null : onAdvance,
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(_advanceLabel(order)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
