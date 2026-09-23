import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';

/// The cart.
///
/// The old implementation held a `List<Map<String, dynamic>>` in the home
/// screen's State and handed it to the cart screen, which took a shallow copy
/// once in `initState` and never resynced. That produced a real, reproducible
/// stock-inflation bug: when the parent removed a line at quantity 1, the cart
/// screen kept a phantom row, and pressing minus on it credited stock back to
/// the database while changing nothing locally — repeatable indefinitely.
///
/// The fix is to stop keeping two copies. The database's `stock_reservations`
/// table is now the single source of truth, this controller is the single
/// in-memory view of it, and every mutation goes through an atomic RPC and then
/// reloads. That also gives REQ-52 (a cart that survives a restart) for free,
/// because the reservation rows outlive the process.
class CartController extends ChangeNotifier {
  CartController({OrderRepository? repository})
      : _repository = repository ?? OrderRepository();

  final OrderRepository _repository;

  List<CartLine> _lines = const [];
  bool _loading = false;
  String? _busyItemId;
  String? _busyLineKey;
  Object? _error;

  List<CartLine> get lines => _lines;
  bool get isLoading => _loading;
  bool get isEmpty => _lines.isEmpty;
  Object? get error => _error;

  /// Which menu item is mid-flight, so only its card shows a spinner.
  String? get busyItemId => _busyItemId;

  /// Whether this exact cart line is mid-flight.
  bool isLineBusy(CartLine line) => _busyLineKey == line.key;

  int get itemCount => _lines.fold(0, (sum, line) => sum + line.quantity);

  int get totalCents =>
      _lines.fold(0, (sum, line) => sum + line.lineTotalCents);

  /// REQ-53. A cart may only be checked out against one cafeteria; this is
  /// what the checkout button reads to decide whether it can proceed.
  String? get cafeteriaId {
    if (_lines.isEmpty) return null;
    final first = _lines.first.item.cafeteriaId;
    return _lines.every((line) => line.item.cafeteriaId == first) ? first : null;
  }

  bool get spansMultipleCafeterias => _lines.isNotEmpty && cafeteriaId == null;

  String? get cafeteriaName => _lines.isEmpty ? null : _lines.first.item.cafeteriaName;

  /// Units of this item across all its lines (every variety or combo choice).
  int quantityOf(String menuItemId) => _lines
      .where((line) => line.item.id == menuItemId)
      .fold(0, (sum, line) => sum + line.quantity);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _lines = await _repository.fetchCart();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// REQ-46 / REQ-49: repeat additions of the same item become one line with a
  /// quantity, which the unique index on the reservation table enforces.
  ///
  /// Rethrows so the caller can show the reason — "sold out" is information the
  /// student needs, not something to swallow.
  ///
  /// [selection] is the variety or combo choices; an item that needs one
  /// cannot be added without it (the database refuses with SELECTION_REQUIRED).
  Future<void> add(
    MenuItem item, {
    CartSelection selection = CartSelection.none,
    int quantity = 1,
  }) =>
      _mutate(
        item.id,
        '${item.id}|${selection.key}',
        () => _repository.reserve(item, selection: selection, quantity: quantity),
      );

  /// One more of exactly this line's choice.
  Future<void> increase(CartLine line) => _mutate(
        line.item.id,
        line.key,
        () => _repository.reserve(line.item, selection: line.selection),
      );

  /// REQ-47.
  Future<void> decrease(CartLine line) => _mutate(
        line.item.id,
        line.key,
        () => _repository.release(line),
      );

  /// Removes the whole line, returning every reserved unit.
  Future<void> remove(CartLine line) => _mutate(
        line.item.id,
        line.key,
        () => _repository.release(line, quantity: line.quantity),
      );

  Future<void> _mutate(
    String itemId,
    String lineKey,
    Future<void> Function() action,
  ) async {
    if (_busyItemId != null) return; // ignore double taps
    _busyItemId = itemId;
    _busyLineKey = lineKey;
    notifyListeners();

    try {
      await action();
      // Always reload rather than patching local state: the reservation table
      // is authoritative, and another device may have changed it too.
      _lines = await _repository.fetchCart();
    } finally {
      _busyItemId = null;
      _busyLineKey = null;
      notifyListeners();
    }
  }

  /// REQ-62. Clears the local view once the reservations have become an order.
  Future<Order> checkout(PaymentMethod method) async {
    final id = cafeteriaId;
    if (id == null) {
      throw StateError('CART_SPANS_CAFETERIAS');
    }

    final order = await _repository.placeOrder(cafeteriaId: id, method: method);
    _lines = const [];
    notifyListeners();
    return order;
  }

  /// REQ-93: called on sign-out.
  Future<void> clear() async {
    await _repository.releaseAll();
    _lines = const [];
    notifyListeners();
  }
}
