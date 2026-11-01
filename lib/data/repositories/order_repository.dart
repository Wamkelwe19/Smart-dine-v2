import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'catalog_repository.dart';

/// Stock reservation, checkout and the order lifecycle.
///
/// Every stock movement goes through a database function. The client no longer
/// reads a count and writes back a number derived from it, which is what made
/// two students able to buy the same last unit (REQ-50).
class OrderRepository {
  OrderRepository({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved lazily so the repository can be constructed (and
  /// subclassed in tests) without a live Supabase instance.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  // -------------------------------------------------------------- reserve --

  /// REQ-46 / REQ-48 / REQ-50. Adds [quantity] of one choice of [item] to the
  /// cart, taking the stock it needs atomically (migration 0009,
  /// `reserve_line`). Returns the cart line's id.
  ///
  /// Throws `INSUFFICIENT_STOCK` when the item, the chosen variety or any combo
  /// part just sold out, and `SELECTION_REQUIRED` when a choice is missing.
  Future<String> reserve(
    MenuItem item, {
    CartSelection selection = CartSelection.none,
    int quantity = 1,
  }) async {
    final result = await _client.rpc(
      'reserve_line',
      params: {
        'p_menu_item_id': item.id,
        'p_variant_id': selection.variant?.id,
        'p_selections': selection.selectionsJson,
        'p_qty': quantity,
      },
    );
    return result.toString();
  }

  /// REQ-47. Returns stock only up to what this line actually holds, so
  /// pressing minus on a stale row can no longer mint stock. Returns the
  /// units left on the line.
  Future<int> release(CartLine line, {int quantity = 1}) async {
    final result = await _client.rpc(
      'release_line',
      params: {'p_reservation_id': line.reservationId, 'p_qty': quantity},
    );
    return (result as num).toInt();
  }

  /// REQ-93: called on sign-out.
  Future<void> releaseAll() => _client.rpc('release_my_reservations');

  /// The authoritative cart: reservations that have not yet become an order.
  ///
  /// The old cart lived only in widget memory and the cart screen kept its own
  /// shallow copy that drifted from the parent's list. Reading it back from the
  /// database removes that whole class of bug, and gives REQ-52 (a cart that
  /// survives a restart) for free.
  Future<List<CartLine>> fetchCart() async {
    final rows = await _client
        .from('stock_reservations')
        // Specials, varieties and combo parts are embedded so the cart shows
        // the price place_order will charge and what was chosen.
        .select('id, quantity, variant_id, selections, '
            'menu_items!menu_item_id(${CatalogRepository.itemEmbeds})')
        .isFilter('order_id', null)
        .order('created_at');

    final lines = rows
        .map(CartLine.fromReservation)
        .whereType<CartLine>()
        .toList()
      ..sort((a, b) {
        final byName = a.item.name.compareTo(b.item.name);
        return byName != 0 ? byName : (a.details ?? '').compareTo(b.details ?? '');
      });
    return lines;
  }

  // ------------------------------------------------------------- checkout --

  /// REQ-62 / REQ-63. Converts the cart into an order atomically.
  /// Rejects a closed cafeteria (BR-6) and a multi-cafeteria cart (REQ-53).
  Future<Order> placeOrder({
    required String cafeteriaId,
    required PaymentMethod method,
  }) async {
    final row = await _client.rpc('place_order', params: {
      'p_cafeteria_id': cafeteriaId,
      'p_payment_method': method.wire,
    });
    return Order.fromMap(Map<String, dynamic>.from(row as Map));
  }

  // -------------------------------------------------------------- reading --

  /// REQ-68: a student's own orders, newest first.
  Stream<List<Order>> watchMyOrders(String studentId) => _client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('student_id', studentId)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Order.fromMap).toList());

  /// Line items are not part of the realtime payload, so they are fetched on
  /// demand when a card expands.
  Future<Order> fetchOrderDetail(String orderId) async {
    final row = await _client
        .from('orders')
        .select('*, order_items(*), cafeterias(name)')
        .eq('id', orderId)
        .single();
    return Order.fromMap(row);
  }

  /// REQ-65 / REQ-67: the staff queue for one cafeteria, live.
  /// RLS restricts this to cafeterias the caller is bound to.
  Stream<List<Order>> watchCafeteriaQueue(String cafeteriaId) => _client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('cafeteria_id', cafeteriaId)
      .order('created_at')
      .map(
        (rows) => rows
            .map(Order.fromMap)
            .where((order) => !order.status.isTerminal)
            .toList(),
      );

  /// Orders with their line items, for the queue cards. The realtime stream
  /// above drives *when* to refetch; this provides the detail.
  Future<List<Order>> fetchQueueWithItems(String cafeteriaId) async {
    final rows = await _client
        .from('orders')
        .select('*, order_items(*), profiles(name)')
        .eq('cafeteria_id', cafeteriaId)
        .inFilter('status', ['new', 'preparing', 'ready'])
        .order('created_at');

    return rows.map<Order>((r) => Order.fromMap(r)).toList();
  }

  /// The newest card-payment reference for [orderId], for "Check payment".
  /// RLS (payments_select_via_order) limits this to the order's own student
  /// and its cafeteria's staff.
  Future<String?> latestPaymentReference(String orderId) async {
    final row = await _client
        .from('payments')
        .select('provider_reference')
        .eq('order_id', orderId)
        .eq('provider', 'yoco')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['provider_reference'] as String?;
  }

  // ------------------------------------------------------------ lifecycle --

  /// REQ-64 / BR-7. The state machine is enforced in the database, so a
  /// tampered client cannot move an order backwards.
  Future<Order> advance(String orderId, OrderStatus to) async {
    final row = await _client.rpc('advance_order', params: {
      'p_order_id': orderId,
      'p_to': to.wire,
    });
    return Order.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// REQ-69: returns the reserved stock.
  Future<Order> cancel(String orderId, {String? reason}) async {
    final row = await _client.rpc('cancel_order', params: {
      'p_order_id': orderId,
      'p_reason': reason,
    });
    return Order.fromMap(Map<String, dynamic>.from(row as Map));
  }
}
