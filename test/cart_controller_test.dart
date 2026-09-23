import 'package:flutter_test/flutter_test.dart';
import 'package:ump_smart_dine/data/models/models.dart';
import 'package:ump_smart_dine/data/repositories/order_repository.dart';
import 'package:ump_smart_dine/features/student/cart_controller.dart';

/// REQ-46 to REQ-53 and the stock-inflation regression.
///
/// The old cart kept two copies of itself: a list in the home screen's State
/// and a shallow copy the cart screen took once in `initState` with no
/// `didUpdateWidget`. When the parent removed a line at quantity 1, the cart
/// screen kept a phantom row, and pressing minus on it credited stock back to
/// the database while changing nothing locally — repeatable indefinitely.
///
/// There is now one source of truth, and the fake below stands in for the
/// database so the arithmetic can be tested without one. It mirrors
/// `reserve_line` / `release_line` from migration 0009: a cart line is one
/// (item, choice) pair, and each unit of it holds stock on the item, on the
/// chosen variety, or on every part of a combo.
class _FakeOrderRepository extends OrderRepository {
  _FakeOrderRepository({required this.stock});

  /// Stock key -> units on the shelf. A plain item's key is its id; a
  /// variety's is its variant id.
  final Map<String, int> stock;

  /// Line key -> (item, selection, quantity held).
  final Map<String, ({MenuItem item, CartSelection selection, int quantity})>
      lines = {};

  int reserveCalls = 0;
  int releaseCalls = 0;

  /// What one unit of a line holds: stock key -> units.
  Map<String, int> _holds(MenuItem item, CartSelection selection) {
    if (item.isCombo) {
      return {
        for (final part in item.components)
          (selection.componentVariants[part.item.id]?.id ?? part.item.id):
              part.quantity,
      };
    }
    return {selection.variant?.id ?? item.id: 1};
  }

  @override
  Future<String> reserve(
    MenuItem item, {
    CartSelection selection = CartSelection.none,
    int quantity = 1,
  }) async {
    reserveCalls++;
    if (!selection.isCompleteFor(item)) throw Exception('SELECTION_REQUIRED');

    final holds = _holds(item, selection);
    // All or nothing, like the single transaction in reserve_line.
    for (final hold in holds.entries) {
      if ((stock[hold.key] ?? 0) < hold.value * quantity) {
        throw Exception('INSUFFICIENT_STOCK');
      }
    }
    for (final hold in holds.entries) {
      stock[hold.key] = stock[hold.key]! - hold.value * quantity;
    }

    final key = '${item.id}|${selection.key}';
    final held = lines[key]?.quantity ?? 0;
    lines[key] = (item: item, selection: selection, quantity: held + quantity);
    return key;
  }

  @override
  Future<int> release(CartLine line, {int quantity = 1}) async {
    releaseCalls++;
    final held = lines[line.reservationId];
    if (held == null) {
      // This is the guard that makes the old bug impossible: you cannot
      // release stock you are not holding.
      throw Exception('NO_RESERVATION');
    }
    final toRelease = quantity < held.quantity ? quantity : held.quantity;
    for (final hold in _holds(held.item, held.selection).entries) {
      stock[hold.key] = (stock[hold.key] ?? 0) + hold.value * toRelease;
    }
    final remaining = held.quantity - toRelease;
    if (remaining == 0) {
      lines.remove(line.reservationId);
    } else {
      lines[line.reservationId] =
          (item: held.item, selection: held.selection, quantity: remaining);
    }
    return remaining;
  }

  @override
  Future<void> releaseAll() async {
    for (final line in lines.values) {
      for (final hold in _holds(line.item, line.selection).entries) {
        stock[hold.key] = (stock[hold.key] ?? 0) + hold.value * line.quantity;
      }
    }
    lines.clear();
  }

  @override
  Future<List<CartLine>> fetchCart() async {
    return lines.entries
        .map(
          (entry) => CartLine(
            item: entry.value.item,
            quantity: entry.value.quantity,
            reservationId: entry.key,
            selection: entry.value.selection,
          ),
        )
        .toList()
      ..sort((a, b) => a.item.name.compareTo(b.item.name));
  }
}

void main() {
  late _FakeOrderRepository repository;
  late CartController cart;

  setUp(() {
    repository = _FakeOrderRepository(stock: {'pie': 3, 'tea': 1, 'b-roll': 2});
    cart = CartController(repository: repository);
  });

  /// Items prefixed "b-" belong to a second cafeteria, for the REQ-53 test.
  MenuItem item(String id) => MenuItem.fromMap({
        'id': id,
        'name': 'Item $id',
        'price_cents': 1000,
        'stock_count': repository.stock[id] ?? 0,
        'cafeteria_id': id.startsWith('b-') ? 'cafeteria-b' : 'cafeteria-a',
      });

  group('adding (REQ-46, REQ-49)', () {
    test('reserves stock and creates a line', () async {
      await cart.add(item('pie'));

      expect(cart.lines, hasLength(1));
      expect(cart.quantityOf('pie'), 1);
      expect(repository.stock['pie'], 2);
    });

    test('repeat additions become one line with a quantity', () async {
      await cart.add(item('pie'));
      await cart.add(item('pie'));

      expect(cart.lines, hasLength(1));
      expect(cart.quantityOf('pie'), 2);
      expect(repository.stock['pie'], 1);
    });

    test('refuses when stock has run out', () async {
      await cart.add(item('tea')); // last one
      expect(repository.stock['tea'], 0);

      await expectLater(cart.add(item('tea')), throwsA(isA<Exception>()));

      // The failed attempt must not have changed anything.
      expect(cart.quantityOf('tea'), 1);
      expect(repository.stock['tea'], 0);
    });
  });

  group('removing (REQ-47)', () {
    test('returns the reserved quantity to stock', () async {
      await cart.add(item('pie'));
      await cart.add(item('pie'));
      expect(repository.stock['pie'], 1);

      await cart.remove(cart.lines.first);

      expect(cart.isEmpty, isTrue);
      expect(repository.stock['pie'], 3, reason: 'both units returned');
    });

    test('decreasing drops the line when it reaches zero', () async {
      await cart.add(item('pie'));
      await cart.decrease(cart.lines.first);

      expect(cart.isEmpty, isTrue);
      expect(repository.stock['pie'], 3);
    });

    test('stock cannot be minted by releasing what is not held', () async {
      // The old bug, made impossible. Reserve one, release it, then try again.
      await cart.add(item('pie'));
      final line = cart.lines.first;
      await cart.decrease(line);

      expect(repository.stock['pie'], 3);

      // `line` is now stale — exactly the phantom row the old cart kept.
      await expectLater(cart.decrease(line), throwsA(isA<Exception>()));

      expect(repository.stock['pie'], 3,
          reason: 'stock must not exceed what the cafeteria actually has');
    });

    test('total stock is conserved across a long sequence', () async {
      const startingTotal = 3 + 1 + 2;

      await cart.add(item('pie'));
      await cart.add(item('pie'));
      await cart.add(item('tea'));
      await cart.decrease(cart.lines.firstWhere((l) => l.item.id == 'pie'));
      await cart.add(item('b-roll'));
      await cart.remove(cart.lines.firstWhere((l) => l.item.id == 'tea'));

      final onShelf = repository.stock.values.reduce((a, b) => a + b);
      final held = repository.lines.values.fold(0, (a, b) => a + b.quantity);

      expect(onShelf + held, startingTotal,
          reason: 'no unit may be created or destroyed');
    });
  });

  group('varieties', () {
    const sweetChilli = MenuItemVariant(
        id: 'v-chilli', menuItemId: 'doritos', name: 'Sweet Chilli', stockCount: 2);
    const cheese = MenuItemVariant(
        id: 'v-cheese',
        menuItemId: 'doritos',
        name: 'Cheese',
        priceDeltaCents: 200,
        stockCount: 1);
    const doritos = MenuItem(
      id: 'doritos',
      cafeteriaId: 'cafeteria-a',
      name: 'Doritos',
      priceCents: 1500,
      stockCount: 0,
      isAvailable: true,
      category: MenuCategory.snack,
      variants: [sweetChilli, cheese],
    );

    setUp(() {
      repository.stock.addAll({'v-chilli': 2, 'v-cheese': 1});
    });

    test('each variety is its own line and draws its own stock', () async {
      await cart.add(doritos,
          selection: const CartSelection(variant: sweetChilli));
      await cart.add(doritos, selection: const CartSelection(variant: cheese));
      await cart.add(doritos,
          selection: const CartSelection(variant: sweetChilli));

      expect(cart.lines, hasLength(2));
      expect(cart.quantityOf('doritos'), 3);
      expect(repository.stock['v-chilli'], 0);
      expect(repository.stock['v-cheese'], 0);
      // 2 x R15.00 + 1 x (R15.00 + R2.00)
      expect(cart.totalCents, 4700);
      expect(
        cart.lines.map((l) => l.details),
        containsAll(['Sweet Chilli', 'Cheese']),
      );
    });

    test('one sold-out variety does not block another', () async {
      await cart.add(doritos, selection: const CartSelection(variant: cheese));
      await expectLater(
        cart.add(doritos, selection: const CartSelection(variant: cheese)),
        throwsA(isA<Exception>()),
      );
      await cart.add(doritos,
          selection: const CartSelection(variant: sweetChilli));
      expect(cart.quantityOf('doritos'), 2);
    });

    test('an item with varieties cannot be added without choosing', () async {
      await expectLater(cart.add(doritos), throwsA(isA<Exception>()));
      expect(cart.isEmpty, isTrue);
    });
  });

  group('combos', () {
    const cola = MenuItemVariant(
        id: 'v-cola', menuItemId: 'drink', name: 'Cola', stockCount: 5);
    const burger = MenuItem(
        id: 'burger',
        cafeteriaId: 'cafeteria-a',
        name: 'Burger',
        priceCents: 4000,
        stockCount: 3,
        isAvailable: true);
    const chips = MenuItem(
        id: 'chips',
        cafeteriaId: 'cafeteria-a',
        name: 'Chips',
        priceCents: 1500,
        stockCount: 4,
        isAvailable: true);
    const drink = MenuItem(
        id: 'drink',
        cafeteriaId: 'cafeteria-a',
        name: 'Drink',
        priceCents: 1200,
        stockCount: 0,
        isAvailable: true,
        category: MenuCategory.beverage,
        variants: [cola]);
    const combo = MenuItem(
      id: 'combo',
      cafeteriaId: 'cafeteria-a',
      name: 'Burger Combo',
      priceCents: 6000,
      stockCount: 0,
      isAvailable: true,
      category: MenuCategory.combo,
      components: [
        ComboComponent(item: burger, quantity: 1),
        ComboComponent(item: chips, quantity: 2),
        ComboComponent(item: drink, quantity: 1),
      ],
    );
    const choice = CartSelection(componentVariants: {'drink': cola});

    setUp(() {
      repository.stock.addAll({'burger': 3, 'chips': 4, 'v-cola': 5});
    });

    test('takes stock from every part, and gives it all back', () async {
      await cart.add(combo, selection: choice);
      await cart.increase(cart.lines.single);

      expect(repository.stock['burger'], 1);
      expect(repository.stock['chips'], 0, reason: 'two chips per combo');
      expect(repository.stock['v-cola'], 3);
      expect(cart.totalCents, 12000);
      expect(cart.lines.single.details, 'Burger · 2× Chips · Drink (Cola)');

      await cart.remove(cart.lines.single);
      expect(repository.stock['burger'], 3);
      expect(repository.stock['chips'], 4);
      expect(repository.stock['v-cola'], 5);
    });

    test('is refused whole when any part runs short', () async {
      repository.stock['chips'] = 1; // a combo needs two
      await expectLater(
          cart.add(combo, selection: choice), throwsA(isA<Exception>()));
      expect(repository.stock['burger'], 3, reason: 'nothing taken');
      expect(repository.stock['v-cola'], 5);
    });

    test('needs the drink chosen', () async {
      await expectLater(cart.add(combo), throwsA(isA<Exception>()));
    });
  });

  group('totals (REQ-54)', () {
    test('sums each line price times quantity', () async {
      await cart.add(item('pie'));
      await cart.add(item('pie'));
      await cart.add(item('tea'));

      // 2 x R10.00 + 1 x R10.00
      expect(cart.totalCents, 3000);
      expect(cart.itemCount, 3);
    });

    test('an empty cart totals zero', () {
      expect(cart.totalCents, 0);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('single-cafeteria rule (REQ-53)', () {
    test('a single-outlet cart exposes its cafeteria', () async {
      await cart.add(item('pie'));
      await cart.add(item('tea'));

      expect(cart.cafeteriaId, 'cafeteria-a');
      expect(cart.spansMultipleCafeterias, isFalse);
    });

    test('a cart spanning two outlets is flagged and blocks checkout', () async {
      await cart.add(item('pie'));
      await cart.add(item('b-roll'));

      expect(cart.spansMultipleCafeterias, isTrue);
      expect(cart.cafeteriaId, isNull);
      await expectLater(
        cart.checkout(PaymentMethod.cash),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('sign-out (REQ-93)', () {
    test('clearing returns every reserved unit', () async {
      await cart.add(item('pie'));
      await cart.add(item('tea'));

      await cart.clear();

      expect(cart.isEmpty, isTrue);
      expect(repository.stock['pie'], 3);
      expect(repository.stock['tea'], 1);
    });
  });

  group('concurrency guard', () {
    test('a second mutation is ignored while one is in flight', () async {
      final first = cart.add(item('pie'));
      // Fired before the first completes; must be dropped, not queued.
      final second = cart.add(item('pie'));
      await Future.wait([first, second]);

      expect(repository.reserveCalls, 1);
      expect(cart.quantityOf('pie'), 1);
    });
  });
}
