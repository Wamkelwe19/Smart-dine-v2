import 'package:flutter_test/flutter_test.dart';
import 'package:ump_smart_dine/data/models/models.dart';

/// Parsing and the order state machine.
///
/// The old code passed raw maps around and did hard casts like
/// `item['stock_count'] as int` *outside* the try block, so a null column threw
/// past the error handler and crashed the screen. These tests pin the
/// null-tolerance down.
void main() {
  group('MenuItem parsing', () {
    test('survives null and missing columns', () {
      final item = MenuItem.fromMap({'id': 'abc'});

      expect(item.id, 'abc');
      expect(item.name, 'Unknown item');
      expect(item.stockCount, 0);
      expect(item.priceCents, 0);
      expect(item.imageUrl, isNull);
    });

    test('prefers price_cents but falls back to the legacy price column', () {
      expect(MenuItem.fromMap({'id': 'a', 'price_cents': 1999}).priceCents, 1999);
      // Before migration 0002 has run, only `price` exists.
      expect(MenuItem.fromMap({'id': 'a', 'price': 19.99}).priceCents, 1999);
    });

    test('treats an empty image_url as no image', () {
      // The old editor wrote '' when the field was blank but read it back as a
      // nullable String, so the column held both '' and NULL.
      expect(MenuItem.fromMap({'id': 'a', 'image_url': ''}).imageUrl, isNull);
      expect(MenuItem.fromMap({'id': 'a', 'image_url': '  '}).imageUrl, isNull);
      expect(
        MenuItem.fromMap({'id': 'a', 'image_url': 'https://x/y.png'}).imageUrl,
        'https://x/y.png',
      );
    });
  });

  group('MenuItem availability (REQ-41)', () {
    MenuItem build({int stock = 5, bool available = true}) => MenuItem.fromMap({
          'id': 'a',
          'name': 'Bunny chow',
          'stock_count': stock,
          'is_available': available,
        });

    test('sold out and withdrawn are different states', () {
      expect(
        build(stock: 0).availability(parentCafeteriaOpen: true),
        MenuItemAvailability.soldOut,
      );
      expect(
        build(available: false).availability(parentCafeteriaOpen: true),
        MenuItemAvailability.withdrawn,
      );
      // The old card rendered both as the single word "Unavailable".
      expect(
        MenuItemAvailability.soldOut.label,
        isNot(MenuItemAvailability.withdrawn.label),
      );
    });

    test('a closed cafeteria overrides everything else', () {
      expect(
        build().availability(parentCafeteriaOpen: false),
        MenuItemAvailability.cafeteriaClosed,
      );
    });

    test('only the available state can be ordered', () {
      expect(build().availability(parentCafeteriaOpen: true).canOrder, isTrue);
      expect(build(stock: 0).availability(parentCafeteriaOpen: true).canOrder, isFalse);
    });

    test('a missing cafeteria join defaults to closed, not open', () {
      // Cafeteria.fromMap defaults is_open to false. The old client defaulted
      // the same column to true in one file and false in another, so a missing
      // join read as "open" in global search.
      expect(Cafeteria.fromMap({'id': 'c', 'name': 'X'}).isOpen, isFalse);
    });
  });

  group('OrderStatus state machine (BR-7)', () {
    test('advances forward only, in order', () {
      expect(OrderStatus.isNew.next, OrderStatus.preparing);
      expect(OrderStatus.preparing.next, OrderStatus.ready);
      expect(OrderStatus.ready.next, OrderStatus.collected);
    });

    test('terminal states cannot advance', () {
      expect(OrderStatus.collected.next, isNull);
      expect(OrderStatus.cancelled.next, isNull);
      expect(OrderStatus.collected.isTerminal, isTrue);
      expect(OrderStatus.cancelled.isTerminal, isTrue);
    });

    test('cancellation is permitted only from new or preparing', () {
      expect(OrderStatus.isNew.isCancellable, isTrue);
      expect(OrderStatus.preparing.isCancellable, isTrue);
      expect(OrderStatus.ready.isCancellable, isFalse);
      expect(OrderStatus.collected.isCancellable, isFalse);
      expect(OrderStatus.cancelled.isCancellable, isFalse);
    });

    test('wire format maps isNew to "new"', () {
      expect(OrderStatus.isNew.wire, 'new');
      expect(OrderStatus.preparing.wire, 'preparing');
      expect(OrderStatus.parse('new'), OrderStatus.isNew);
      expect(OrderStatus.parse('ready'), OrderStatus.ready);
    });

    test('an unknown status parses to new rather than throwing', () {
      expect(OrderStatus.parse(null), OrderStatus.isNew);
      expect(OrderStatus.parse('nonsense'), OrderStatus.isNew);
    });
  });

  group('Order parsing', () {
    test('totals its line items', () {
      final order = Order.fromMap({
        'id': 'o1',
        'student_id': 's1',
        'cafeteria_id': 'c1',
        'status': 'new',
        'payment_method': 'cash',
        'payment_state': 'pending',
        'total_cents': 4497,
        'collection_ref': 'K7QP2M',
        'order_items': [
          {'name': 'Bunny chow', 'unit_price_cents': 1999, 'quantity': 2},
          {'name': 'Iced tea', 'unit_price_cents': 499, 'quantity': 1},
        ],
      });

      expect(order.collectionRef, 'K7QP2M');
      expect(order.itemCount, 3);
      expect(order.totalLabel, 'R 44.97');
      expect(order.items.first.lineTotalLabel, 'R 39.98');
    });
  });

  group('Profile', () {
    test('falls back to the number when no name is stored (REQ-28)', () {
      final profile = Profile.fromMap({
        'id': 'u1',
        'student_staff_id': '231112009',
        'role': 'student',
      });
      expect(profile.displayName, '231112009');
    });

    test('uses the name when present', () {
      final profile = Profile.fromMap({
        'id': 'u1',
        'name': 'Tshepo',
        'surname': 'Masete',
        'student_staff_id': '231112009',
        'role': 'student',
      });
      expect(profile.displayName, 'Tshepo');
      expect(profile.fullName, 'Tshepo Masete');
    });

    test('an unknown role parses to student, never staff', () {
      // Fail closed: the old login defaulted anything that was not 'staff' to
      // the student screen, which is right, but the parse should agree.
      expect(Profile.fromMap({'id': 'u', 'role': null}).role, UserRole.student);
      expect(Profile.fromMap({'id': 'u', 'role': 'admin'}).role, UserRole.student);
      expect(Profile.fromMap({'id': 'u', 'role': 'staff'}).role, UserRole.staff);
    });

    test('a Google account with no number is incomplete', () {
      final google = Profile.fromMap({
        'id': 'u1',
        'email': 'someone@gmail.com',
        'profile_completed': false,
      });
      expect(google.isComplete, isFalse);
    });
  });

  group('CartLine', () {
    test('multiplies unit price by quantity', () {
      final line = CartLine(
        item: MenuItem.fromMap({'id': 'a', 'name': 'Pie', 'price_cents': 2550}),
        quantity: 3,
      );
      expect(line.lineTotalCents, 7650);
      expect(line.lineTotalLabel, 'R 76.50');
    });
  });

  group('Cafeteria image', () {
    test('parses image_url and treats blank as none', () {
      expect(Cafeteria.fromMap({'id': 'c', 'image_url': 'https://x/c.jpg'}).imageUrl,
          'https://x/c.jpg');
      expect(Cafeteria.fromMap({'id': 'c', 'image_url': ' '}).imageUrl, isNull);
      expect(Cafeteria.fromMap({'id': 'c'}).imageUrl, isNull);
    });
  });

  group('MenuSpecial', () {
    final start = DateTime(2026, 9, 23, 12);
    final end = DateTime(2026, 9, 23, 14);

    MenuSpecial special({
      String kind = 'percent',
      int? percent = 20,
      int? priceCents,
      bool active = true,
      DateTime? endsAt,
      String itemId = 'a',
    }) =>
        MenuSpecial.fromMap({
          'id': 's',
          'menu_item_id': itemId,
          'cafeteria_id': 'c',
          'kind': kind,
          'percent_off': percent,
          'special_price_cents': priceCents,
          'starts_at': start.toIso8601String(),
          'ends_at': endsAt?.toIso8601String(),
          'is_active': active,
        });

    test('parses every kind, tolerating missing columns', () {
      expect(special().kind, SpecialKind.percent);
      expect(special(kind: 'fixed_price', percent: null, priceCents: 3500).kind,
          SpecialKind.fixedPrice);
      expect(special(kind: 'featured', percent: null).kind, SpecialKind.featured);

      final bare = MenuSpecial.fromMap({'id': 's'});
      expect(bare.kind, SpecialKind.featured);
      expect(bare.isActive, isTrue);
      expect(bare.headline, isNull);
    });

    test('is live only inside its window and while active', () {
      final windowed = special(endsAt: end);
      expect(windowed.status(start.subtract(const Duration(minutes: 1))),
          SpecialStatus.scheduled);
      expect(windowed.isLiveAt(start), isTrue);
      expect(windowed.isLiveAt(end.subtract(const Duration(seconds: 1))), isTrue);
      // The end is exclusive, matching `ends_at > now()` in SQL.
      expect(windowed.status(end), SpecialStatus.ended);

      expect(special().isLiveAt(DateTime(2030)), isTrue, reason: 'open-ended');
      expect(special(active: false).status(start), SpecialStatus.paused);
    });

    test('percent rounds half up, matching round() in effective_price_cents', () {
      // 20% off R 45.00.
      expect(special(percent: 20).applyTo(4500), 3600);
      // 15% off R 12.99 = 1104.15 -> 1104.
      expect(special(percent: 15).applyTo(1299), 1104);
      // 50% off R 0.25 = 12.5 -> 13.
      expect(special(percent: 50).applyTo(25), 13);
    });

    test('never raises the price', () {
      final dearer = special(kind: 'fixed_price', percent: null, priceCents: 9000);
      expect(dearer.applyTo(4500), 4500);
      expect(special(kind: 'featured', percent: null).applyTo(4500), 4500);
    });

    test('best special picks the cheapest live discount over featured', () {
      final item = MenuItem.fromMap({'id': 'a', 'price_cents': 5000});
      final featured = special(kind: 'featured', percent: null);
      final tenOff = special(percent: 10);
      final fixed = special(kind: 'fixed_price', percent: null, priceCents: 4000);
      final paused = special(percent: 80, active: false);
      final otherItem = special(percent: 90, itemId: 'b');

      final best = MenuSpecial.bestFor(
          item, [featured, tenOff, fixed, paused, otherItem], start);
      expect(best, same(fixed));
      expect(MenuSpecial.bestFor(item, [featured], start), same(featured));
      expect(MenuSpecial.bestFor(item, [paused, otherItem], start), isNull);
    });

    test('an item carries its special into price and cart totals', () {
      final item = MenuItem.fromMap({'id': 'a', 'price_cents': 4500})
          .withSpecial(special(percent: 20));
      expect(item.effectivePriceCents, 3600);
      expect(item.isDiscounted, isTrue);
      expect(item.priceCents, 4500, reason: 'the usual price is kept');

      expect(CartLine(item: item, quantity: 2).lineTotalCents, 7200);

      final featured = item.withSpecial(special(kind: 'featured', percent: null));
      expect(featured.effectivePriceCents, 4500);
      expect(featured.isDiscounted, isFalse);
    });

    test('an embedded menu_specials list attaches only a live special', () {
      final now = DateTime.now();
      final item = MenuItem.fromMap({
        'id': 'a',
        'price_cents': 2000,
        'menu_specials': [
          {
            'id': 'expired',
            'menu_item_id': 'a',
            'kind': 'percent',
            'percent_off': 50,
            'starts_at': now.subtract(const Duration(days: 2)).toIso8601String(),
            'ends_at': now.subtract(const Duration(days: 1)).toIso8601String(),
            'is_active': true,
          },
          {
            'id': 'live',
            'menu_item_id': 'a',
            'kind': 'fixed_price',
            'special_price_cents': 1500,
            'starts_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
            'is_active': true,
          },
        ],
      });
      expect(item.special?.id, 'live');
      expect(item.effectivePriceCents, 1500);
    });
  });

  group('categories, varieties and combos (0009)', () {
    Map<String, dynamic> variant(String id, String name,
            {int delta = 0, int stock = 5, bool on = true, int order = 0}) =>
        {
          'id': id,
          'menu_item_id': 'doritos',
          'name': name,
          'price_delta_cents': delta,
          'stock_count': stock,
          'is_available': on,
          'sort_order': order,
        };

    test('category parses, defaulting old rows to meal', () {
      expect(MenuItem.fromMap({'id': 'a'}).category, MenuCategory.meal);
      expect(MenuItem.fromMap({'id': 'a', 'category': 'beverage'}).category,
          MenuCategory.beverage);
      expect(MenuItem.fromMap({'id': 'a', 'category': 'nonsense'}).category,
          MenuCategory.meal);
    });

    test('varieties parse sorted and drive availability', () {
      final item = MenuItem.fromMap({
        'id': 'doritos',
        'price_cents': 1500,
        'stock_count': 0, // ignored once varieties exist
        'menu_item_variants': [
          variant('b', 'Cheese', order: 1, stock: 0),
          variant('a', 'Sweet Chilli', order: 0, stock: 3),
        ],
      });
      expect(item.variants.map((v) => v.name), ['Sweet Chilli', 'Cheese']);
      expect(item.needsOptions, isTrue);
      expect(item.availability().canOrder, isTrue);
      expect(item.availableUnits, 3);
      expect(item.optionsSummary, '2 options');
    });

    test('an item whose every variety is out is sold out', () {
      final item = MenuItem.fromMap({
        'id': 'doritos',
        'price_cents': 1500,
        'stock_count': 50,
        'menu_item_variants': [
          variant('a', 'Sweet Chilli', stock: 0),
          variant('b', 'Cheese', stock: 9, on: false),
        ],
      });
      expect(item.availability(), MenuItemAvailability.soldOut);
    });

    test('variety prices, with and without a special', () {
      final item = MenuItem.fromMap({
        'id': 'doritos',
        'price_cents': 2000,
        'menu_item_variants': [
          variant('s', 'Small', delta: -500),
          variant('l', 'Large', delta: 500),
        ],
      });
      final small = item.variants.firstWhere((v) => v.name == 'Small');
      final large = item.variants.firstWhere((v) => v.name == 'Large');
      expect(item.priceFor(large), 2500);
      expect(item.priceFor(small), 1500);
      expect(item.hasPriceRange, isTrue);
      expect(item.fromPriceCents, 1500);

      MenuSpecial special(String kind, {int? percent, int? price}) =>
          MenuSpecial.fromMap({
            'id': 'x',
            'menu_item_id': 'doritos',
            'kind': kind,
            'percent_off': percent,
            'special_price_cents': price,
            'is_active': true,
          });

      // 10% off the whole of (R20 + R5): R22.50.
      expect(item.withSpecial(special('percent', percent: 10)).priceFor(large),
          2250);
      // A fixed R16 special keeps the size difference: R21.
      expect(
          item.withSpecial(special('fixed_price', price: 1600)).priceFor(large),
          2100);
    });

    test('a combo parses its parts and needs a choice for the drink', () {
      final combo = MenuItem.fromMap({
        'id': 'combo',
        'category': 'combo',
        'price_cents': 6000,
        'combo_components': [
          {
            'quantity': 2,
            'sort_order': 1,
            'component': {'id': 'chips', 'name': 'Chips', 'stock_count': 4},
          },
          {
            'quantity': 1,
            'sort_order': 0,
            'component': {
              'id': 'drink',
              'name': 'Drink',
              'menu_item_variants': [
                {
                  'id': 'cola',
                  'menu_item_id': 'drink',
                  'name': 'Cola',
                  'price_delta_cents': 300,
                  'stock_count': 5,
                },
              ],
            },
          },
          {'quantity': 1, 'component': null}, // part since deleted
        ],
      });

      expect(combo.isCombo, isTrue);
      expect(combo.components.map((c) => c.item.name), ['Drink', 'Chips']);
      expect(combo.needsOptions, isTrue);
      expect(combo.optionsSummary, 'Drink · 2× Chips');
      expect(combo.availableUnits, 2, reason: '4 chips, two per combo');

      final cola = combo.components.first.item.variants.single;
      final choice = CartSelection(componentVariants: {'drink': cola});
      expect(choice.isCompleteFor(combo), isTrue);
      expect(CartSelection.none.isCompleteFor(combo), isFalse);
      expect(combo.priceForSelection(choice), 6300);
      expect(choice.selectionsJson, [
        {'component_item_id': 'drink', 'variant_id': 'cola'},
      ]);
    });

    test('a combo is sold out when any part cannot supply it', () {
      final combo = MenuItem.fromMap({
        'id': 'combo',
        'category': 'combo',
        'price_cents': 6000,
        'combo_components': [
          {
            'quantity': 2,
            'component': {'id': 'chips', 'name': 'Chips', 'stock_count': 1},
          },
          {
            'quantity': 1,
            'component': {'id': 'burger', 'name': 'Burger', 'stock_count': 9},
          },
        ],
      });
      expect(combo.availability(), MenuItemAvailability.soldOut);
      expect(
        MenuItem.fromMap({'id': 'c', 'category': 'combo'}).availability(),
        MenuItemAvailability.soldOut,
        reason: 'a combo with no parts cannot be ordered',
      );
    });

    test('line keys are canonical, whatever order choices were made in', () {
      const a = MenuItemVariant(id: 'va', menuItemId: 'x', name: 'A');
      const b = MenuItemVariant(id: 'vb', menuItemId: 'y', name: 'B');
      const one = CartSelection(componentVariants: {'y': b, 'x': a});
      const two = CartSelection(componentVariants: {'x': a, 'y': b});
      expect(one.key, two.key);
      expect(one.key, 'x:va;y:vb;');
      expect(const CartSelection(variant: a).key, 'va');
      expect(CartSelection.none.key, '');
    });

    test('a cart row restores its variety and details', () {
      final line = CartLine.fromReservation({
        'id': 'r1',
        'quantity': 2,
        'variant_id': 'b',
        'menu_items': {
          'id': 'doritos',
          'name': 'Doritos',
          'price_cents': 1500,
          'menu_item_variants': [
            variant('a', 'Sweet Chilli'),
            variant('b', 'Cheese', delta: 200),
          ],
        },
      })!;
      expect(line.reservationId, 'r1');
      expect(line.details, 'Cheese');
      expect(line.unitPriceCents, 1700);
      expect(line.lineTotalCents, 3400);
    });

    test('order lines carry what was chosen', () {
      final item = OrderItem.fromMap({
        'name': 'Doritos',
        'unit_price_cents': 1500,
        'quantity': 1,
        'details': 'Sweet Chilli',
      });
      expect(item.details, 'Sweet Chilli');
      expect(OrderItem.fromMap({'name': 'Pie'}).details, isNull);
    });
  });
}

