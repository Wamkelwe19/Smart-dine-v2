import '../../core/utils/formatters.dart';

/// Typed models replacing the raw `Map<String, dynamic>` passed end to end.
///
/// The old code did hard casts like `item['stock_count'] as int` at the top of
/// methods — *outside* the try block — so a null column threw past the error
/// handler and crashed the screen. Every parser below is null-tolerant.

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String _asString(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

bool _asBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

// ------------------------------------------------------------------ profile --

enum UserRole {
  student,
  staff;

  static UserRole parse(Object? raw) =>
      raw?.toString() == 'staff' ? UserRole.staff : UserRole.student;

  bool get isStaff => this == UserRole.staff;
  String get wire => name;
  String get label => this == UserRole.staff ? 'Staff' : 'Student';
}

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.isComplete,
    this.name,
    this.surname,
    this.studentStaffId,
    this.email,
    this.phone,
    this.avatarUrl,
  });

  final String id;
  final UserRole role;
  final bool isComplete;
  final String? name;
  final String? surname;
  final String? studentStaffId;
  final String? email;
  final String? phone;

  /// The Google profile photo, when the account signed up with Google (0011).
  final String? avatarUrl;

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: _asString(map['id']),
        role: UserRole.parse(map['role']),
        isComplete: _asBool(map['profile_completed'], fallback: false),
        name: map['name'] as String?,
        surname: map['surname'] as String?,
        studentStaffId: map['student_staff_id'] as String?,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
        avatarUrl: _asOptionalText(map['avatar_url']),
      );

  /// REQ-28: greet by name, falling back to the number when no name is stored.
  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return studentStaffId ?? 'there';
  }

  String get fullName => [name, surname]
      .where((part) => part != null && part.trim().isNotEmpty)
      .join(' ')
      .trim();
}

// --------------------------------------------------------------- cafeteria --

String? _asOptionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class Cafeteria {
  const Cafeteria({
    required this.id,
    required this.name,
    required this.isOpen,
    this.imageUrl,
  });

  final String id;
  final String name;
  final bool isOpen;

  /// The cover photo staff uploaded. Null falls back to a bundled photo, then
  /// to the branded placeholder (see CafeteriaImage).
  final String? imageUrl;

  factory Cafeteria.fromMap(Map<String, dynamic> map) => Cafeteria(
        id: _asString(map['id']),
        name: _asString(map['name'], 'Unnamed cafeteria'),
        // Defaults to closed. The old client defaulted this to `true` in one
        // file and `false` in another, so a missing join read as "open".
        isOpen: _asBool(map['is_open'], fallback: false),
        imageUrl: _asOptionalText(map['image_url']),
      );

  String get statusLabel => isOpen ? 'Open' : 'Closed';
}

// ----------------------------------------------------------------- special --

enum SpecialKind {
  percent,
  fixedPrice,
  featured;

  static SpecialKind parse(Object? raw) => switch (raw?.toString()) {
        'percent' => SpecialKind.percent,
        'fixed_price' => SpecialKind.fixedPrice,
        _ => SpecialKind.featured,
      };

  String get wire => switch (this) {
        SpecialKind.percent => 'percent',
        SpecialKind.fixedPrice => 'fixed_price',
        SpecialKind.featured => 'featured',
      };

  String get label => switch (this) {
        SpecialKind.percent => '% off',
        SpecialKind.fixedPrice => 'Special price',
        SpecialKind.featured => 'Featured',
      };
}

enum SpecialStatus {
  live,
  scheduled,
  ended,
  paused;

  String get label => switch (this) {
        SpecialStatus.live => 'Live',
        SpecialStatus.scheduled => 'Scheduled',
        SpecialStatus.ended => 'Ended',
        SpecialStatus.paused => 'Paused',
      };
}

/// A discount or promotion staff publish on one menu item.
///
/// The price the student pays is computed by `effective_price_cents()` in the
/// database; [applyTo] mirrors it exactly so the screen agrees with the charge.
class MenuSpecial {
  const MenuSpecial({
    required this.id,
    required this.menuItemId,
    required this.cafeteriaId,
    required this.kind,
    required this.startsAt,
    required this.isActive,
    this.percentOff,
    this.specialPriceCents,
    this.headline,
    this.endsAt,
    this.item,
  });

  final String id;
  final String menuItemId;
  final String cafeteriaId;
  final SpecialKind kind;
  final int? percentOff;
  final int? specialPriceCents;
  final String? headline;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isActive;

  /// Present when fetched with the `menu_items(...)` join.
  final MenuItem? item;

  factory MenuSpecial.fromMap(Map<String, dynamic> map) {
    final joined = map['menu_items'] as Map<String, dynamic>?;
    return MenuSpecial(
      id: _asString(map['id']),
      menuItemId: _asString(map['menu_item_id']),
      cafeteriaId: _asString(map['cafeteria_id']),
      kind: SpecialKind.parse(map['kind']),
      percentOff: map['percent_off'] == null ? null : _asInt(map['percent_off']),
      specialPriceCents: map['special_price_cents'] == null
          ? null
          : _asInt(map['special_price_cents']),
      headline: _asOptionalText(map['headline']),
      // A missing start reads as "already started" rather than never live.
      startsAt: _asDate(map['starts_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      endsAt: _asDate(map['ends_at']),
      isActive: _asBool(map['is_active'], fallback: true),
      item: joined == null ? null : MenuItem.fromMap(joined),
    );
  }

  SpecialStatus status(DateTime now) {
    if (!isActive) return SpecialStatus.paused;
    if (now.isBefore(startsAt)) return SpecialStatus.scheduled;
    if (endsAt != null && !now.isBefore(endsAt!)) return SpecialStatus.ended;
    return SpecialStatus.live;
  }

  bool isLiveAt(DateTime now) => status(now) == SpecialStatus.live;

  bool get changesPrice => kind != SpecialKind.featured;

  /// The price after this special, never above the regular price.
  ///
  /// [deltaCents] is a variety's price difference: a percentage comes off
  /// the whole (base + difference); a fixed special price replaces the base
  /// and keeps the difference. Mirrors `effective_price_cents` in 0009.
  int applyTo(int baseCents, {int deltaCents = 0}) {
    final regular = baseCents + deltaCents;
    final int discounted;
    switch (kind) {
      case SpecialKind.percent:
        final percent = (percentOff ?? 0).clamp(0, 100);
        // Half-up rounding, matching SQL round() on a positive value.
        discounted = (regular * (100 - percent) + 50) ~/ 100;
      case SpecialKind.fixedPrice:
        discounted = (specialPriceCents ?? baseCents) + deltaCents;
      case SpecialKind.featured:
        discounted = regular;
    }
    final price = discounted < regular ? discounted : regular;
    return price < 0 ? 0 : price;
  }

  String get badgeLabel => switch (kind) {
        SpecialKind.percent => '${percentOff ?? 0}% OFF',
        SpecialKind.fixedPrice => 'SPECIAL',
        SpecialKind.featured => 'FEATURED',
      };

  /// The best live special among [specials] for display on one item: the
  /// cheapest discount, else a featured one. Mirrors effective_price_cents().
  static MenuSpecial? bestFor(
    MenuItem item,
    Iterable<MenuSpecial> specials,
    DateTime now,
  ) {
    MenuSpecial? best;
    for (final special in specials) {
      if (special.menuItemId != item.id || !special.isLiveAt(now)) continue;
      if (best == null) {
        best = special;
        continue;
      }
      final price = special.applyTo(item.priceCents);
      final bestPrice = best.applyTo(item.priceCents);
      if (price < bestPrice ||
          (price == bestPrice && special.changesPrice && !best.changesPrice)) {
        best = special;
      }
    }
    return best;
  }
}

// --------------------------------------------------------------- menu item --

/// The hall page's tabs. Stored as `menu_items.category` (migration 0009).
enum MenuCategory {
  meal,
  combo,
  beverage,
  snack;

  static MenuCategory parse(Object? raw) => switch (raw?.toString()) {
        'combo' => MenuCategory.combo,
        'beverage' => MenuCategory.beverage,
        'snack' => MenuCategory.snack,
        _ => MenuCategory.meal,
      };

  String get wire => name;

  /// Tab and filter label.
  String get label => switch (this) {
        MenuCategory.meal => 'Meals',
        MenuCategory.combo => 'Combos',
        MenuCategory.beverage => 'Beverages',
        MenuCategory.snack => 'Snacks',
      };

  /// Editor label.
  String get singular => switch (this) {
        MenuCategory.meal => 'Meal',
        MenuCategory.combo => 'Combo',
        MenuCategory.beverage => 'Beverage',
        MenuCategory.snack => 'Snack',
      };
}

/// One variety of an item — a flavour or a size — with its own stock and an
/// optional price difference from the item's price.
class MenuItemVariant {
  const MenuItemVariant({
    required this.id,
    required this.menuItemId,
    required this.name,
    this.priceDeltaCents = 0,
    this.stockCount = 0,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  /// Empty for a variety staff have added in the editor but not saved yet.
  final String id;
  final String menuItemId;
  final String name;
  final int priceDeltaCents;
  final int stockCount;
  final bool isAvailable;
  final int sortOrder;

  factory MenuItemVariant.fromMap(Map<String, dynamic> map) => MenuItemVariant(
        id: _asString(map['id']),
        menuItemId: _asString(map['menu_item_id']),
        name: _asString(map['name'], 'Option'),
        priceDeltaCents: _asInt(map['price_delta_cents']),
        stockCount: _asInt(map['stock_count']),
        isAvailable: _asBool(map['is_available'], fallback: true),
        sortOrder: _asInt(map['sort_order']),
      );

  bool get canOrder => isAvailable && stockCount > 0;

  /// "+R 5.00", "-R 2.00", or empty when it costs the same.
  String get deltaLabel {
    if (priceDeltaCents == 0) return '';
    final sign = priceDeltaCents > 0 ? '+' : '-';
    return '$sign${Money.format(priceDeltaCents.abs())}';
  }
}

int _byOrderThenName(int orderA, String nameA, int orderB, String nameB) {
  final byOrder = orderA.compareTo(orderB);
  return byOrder != 0 ? byOrder : nameA.compareTo(nameB);
}

/// One part of a combo: an existing menu item, and how many of it.
class ComboComponent {
  const ComboComponent({
    required this.item,
    required this.quantity,
    this.sortOrder = 0,
  });

  final MenuItem item;
  final int quantity;
  final int sortOrder;

  /// Parses the `combo_components(quantity, sort_order, component:menu_items(...))`
  /// embed. Returns null when the part has since been deleted.
  static ComboComponent? fromMap(Map<String, dynamic> map) {
    final component = map['component'];
    if (component is! Map<String, dynamic>) return null;
    return ComboComponent(
      item: MenuItem.fromMap(component),
      quantity: _asInt(map['quantity'], 1).clamp(1, 99),
      sortOrder: _asInt(map['sort_order']),
    );
  }

  /// Whether this part can supply one combo. A part with varieties needs at
  /// least one variety holding [quantity] units.
  bool get canSupply {
    if (!item.isAvailable) return false;
    if (item.hasVariants) {
      return item.variants.any((v) => v.isAvailable && v.stockCount >= quantity);
    }
    return item.stockCount >= quantity;
  }

  /// "2× Chips" or "Burger".
  String get label => quantity > 1 ? '$quantity× ${item.name}' : item.name;
}

/// REQ-41: sold out and withdrawn are different states and must not render
/// identically. The old card showed the single word "Unavailable" for both.
enum MenuItemAvailability {
  available,
  soldOut,
  withdrawn,
  cafeteriaClosed;

  bool get canOrder => this == MenuItemAvailability.available;

  String get label => switch (this) {
        MenuItemAvailability.available => 'Available',
        MenuItemAvailability.soldOut => 'Sold out',
        MenuItemAvailability.withdrawn => 'Not on sale',
        MenuItemAvailability.cafeteriaClosed => 'Cafeteria closed',
      };
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.cafeteriaId,
    required this.name,
    required this.priceCents,
    required this.stockCount,
    required this.isAvailable,
    this.imageUrl,
    this.cafeteriaName,
    this.cafeteriaIsOpen,
    this.special,
    this.category = MenuCategory.meal,
    this.description,
    this.variants = const [],
    this.components = const [],
  });

  final String id;
  final String cafeteriaId;
  final String name;
  final int priceCents;

  /// Ignored when the item has [variants] (stock is per variety) or is a
  /// combo (stock comes from its parts).
  final int stockCount;

  /// The staff withdrawal switch, not the sold-out signal.
  final bool isAvailable;

  final String? imageUrl;

  /// Present when the row was fetched with the `cafeterias(...)` join.
  final String? cafeteriaName;
  final bool? cafeteriaIsOpen;

  /// The live special on this item, attached by the screen that loaded it.
  final MenuSpecial? special;

  final MenuCategory category;
  final String? description;

  /// Sorted for display. Present when fetched with `menu_item_variants(*)`.
  final List<MenuItemVariant> variants;

  /// A combo's parts. Present when fetched with the `combo_components` embed.
  final List<ComboComponent> components;

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    final joined = map['cafeterias'] as Map<String, dynamic>?;

    // price_cents arrives once migration 0002 has run; fall back to the legacy
    // numeric column so the app works either side of that migration.
    final cents = map['price_cents'] != null
        ? _asInt(map['price_cents'])
        : Money.centsFromRands((map['price'] as num?) ?? 0);

    final rawVariants = map['menu_item_variants'];
    final variants = rawVariants is List
        ? (rawVariants
            .whereType<Map<String, dynamic>>()
            .map(MenuItemVariant.fromMap)
            .toList()
          ..sort((a, b) =>
              _byOrderThenName(a.sortOrder, a.name, b.sortOrder, b.name)))
        : const <MenuItemVariant>[];

    final rawComponents = map['combo_components'];
    final components = rawComponents is List
        ? (rawComponents
            .whereType<Map<String, dynamic>>()
            .map(ComboComponent.fromMap)
            .whereType<ComboComponent>()
            .toList()
          ..sort((a, b) => _byOrderThenName(
              a.sortOrder, a.item.name, b.sortOrder, b.item.name)))
        : const <ComboComponent>[];

    final item = MenuItem(
      id: _asString(map['id']),
      cafeteriaId: _asString(map['cafeteria_id']),
      name: _asString(map['name'], 'Unknown item'),
      priceCents: cents,
      stockCount: _asInt(map['stock_count']),
      isAvailable: _asBool(map['is_available'], fallback: true),
      imageUrl: _asOptionalText(map['image_url']),
      cafeteriaName: joined?['name'] as String?,
      cafeteriaIsOpen:
          joined == null ? null : _asBool(joined['is_open'], fallback: false),
      category: MenuCategory.parse(map['category']),
      description: _asOptionalText(map['description']),
      variants: variants,
      components: components,
    );

    // Present when fetched with the `menu_specials(*)` embed; attaches the
    // best live one so the price shown matches what checkout charges.
    final rawSpecials = map['menu_specials'];
    if (rawSpecials is! List) return item;
    final specials = rawSpecials
        .whereType<Map<String, dynamic>>()
        .map(MenuSpecial.fromMap);
    return item.withSpecial(MenuSpecial.bestFor(item, specials, DateTime.now()));
  }

  bool get isCombo => category == MenuCategory.combo;
  bool get hasVariants => variants.isNotEmpty;

  /// Whether the student must choose something before it can go in the cart.
  bool get needsOptions =>
      hasVariants || (isCombo && components.any((c) => c.item.hasVariants));

  String get priceLabel => Money.format(priceCents);

  /// What the student pays now for the item at its own price (no variety
  /// difference). The server recomputes this at checkout.
  int get effectivePriceCents => special?.applyTo(priceCents) ?? priceCents;
  String get effectivePriceLabel => Money.format(effectivePriceCents);
  bool get isDiscounted => effectivePriceCents < priceCents;

  /// Varieties cost different amounts, so the price reads "From ...".
  bool get hasPriceRange =>
      variants.any((v) => v.priceDeltaCents != variants.first.priceDeltaCents) ||
      (isCombo &&
          components.any((c) => c.item.variants.any((v) => v.priceDeltaCents != 0)));

  /// One unit with [variant] chosen. Mirrors `effective_price_cents(item,
  /// variant)` in migration 0009.
  int priceFor(MenuItemVariant? variant) {
    final delta = variant?.priceDeltaCents ?? 0;
    final special = this.special;
    if (special == null) {
      final base = priceCents + delta;
      return base < 0 ? 0 : base;
    }
    return special.applyTo(priceCents, deltaCents: delta);
  }

  /// One combo with [choices] (part item id → variety). Mirrors
  /// `line_unit_price_cents` for combos.
  int comboPriceFor(Map<String, MenuItemVariant> choices) {
    var total = effectivePriceCents;
    for (final component in components) {
      final choice = choices[component.item.id];
      if (choice != null) total += choice.priceDeltaCents * component.quantity;
    }
    return total < 0 ? 0 : total;
  }

  int priceForSelection(CartSelection selection) => isCombo
      ? comboPriceFor(selection.componentVariants)
      : priceFor(selection.variant);

  /// The cheapest price the student could pay, for "From R ..." on cards.
  int get fromPriceCents {
    if (isCombo) {
      var total = effectivePriceCents;
      for (final component in components) {
        if (!component.item.hasVariants) continue;
        final cheapest = component.item.variants
            .map((v) => v.priceDeltaCents)
            .reduce((a, b) => a < b ? a : b);
        total += cheapest * component.quantity;
      }
      return total < 0 ? 0 : total;
    }
    if (hasVariants) {
      return variants.map(priceFor).reduce((a, b) => a < b ? a : b);
    }
    return effectivePriceCents;
  }

  /// A copy with [special] attached, or cleared when null.
  MenuItem withSpecial(MenuSpecial? special) => MenuItem(
        id: id,
        cafeteriaId: cafeteriaId,
        name: name,
        priceCents: priceCents,
        stockCount: stockCount,
        isAvailable: isAvailable,
        imageUrl: imageUrl,
        cafeteriaName: cafeteriaName,
        cafeteriaIsOpen: cafeteriaIsOpen,
        special: special,
        category: category,
        description: description,
        variants: variants,
        components: components,
      );

  /// How many can be ordered right now: summed across varieties, and for a
  /// combo the number of whole combos its scarcest part can supply.
  int get availableUnits {
    if (isCombo) {
      if (components.isEmpty) return 0;
      int? units;
      for (final component in components) {
        final part = component.item;
        final stock = part.hasVariants
            ? part.variants
                .where((v) => v.isAvailable)
                .fold(0, (sum, v) => sum + v.stockCount)
            : part.stockCount;
        final supply = part.isAvailable ? stock ~/ component.quantity : 0;
        if (units == null || supply < units) units = supply;
      }
      return units ?? 0;
    }
    if (hasVariants) {
      return variants
          .where((v) => v.isAvailable)
          .fold(0, (sum, v) => sum + v.stockCount);
    }
    return stockCount;
  }

  MenuItemAvailability availability({bool? parentCafeteriaOpen}) {
    final open = parentCafeteriaOpen ?? cafeteriaIsOpen ?? true;
    if (!open) return MenuItemAvailability.cafeteriaClosed;
    if (!isAvailable) return MenuItemAvailability.withdrawn;
    if (isCombo) {
      final canSupply =
          components.isNotEmpty && components.every((c) => c.canSupply);
      return canSupply
          ? MenuItemAvailability.available
          : MenuItemAvailability.soldOut;
    }
    if (hasVariants) {
      return variants.any((v) => v.canOrder)
          ? MenuItemAvailability.available
          : MenuItemAvailability.soldOut;
    }
    if (stockCount <= 0) return MenuItemAvailability.soldOut;
    return MenuItemAvailability.available;
  }

  bool get isLowStock => availableUnits > 0 && availableUnits <= 5;

  /// "3 options" or "Burger · Chips · Drink": the card's options line.
  String? get optionsSummary {
    if (isCombo && components.isNotEmpty) {
      return components.map((c) => c.label).join(' · ');
    }
    if (hasVariants) {
      return '${variants.length} ${variants.length == 1 ? 'option' : 'options'}';
    }
    return null;
  }
}

// ------------------------------------------------------------------- cart --

/// What a student chose for an item: a variety, or one variety per combo part
/// that has them.
class CartSelection {
  const CartSelection({this.variant, this.componentVariants = const {}});

  static const none = CartSelection();

  final MenuItemVariant? variant;

  /// Combo part item id → the chosen variety.
  final Map<String, MenuItemVariant> componentVariants;

  /// Same ordering as `reserve_line`'s line_key: part ids ascending.
  List<MapEntry<String, MenuItemVariant>> get _sortedChoices =>
      componentVariants.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  /// Identifies the cart line this choice adds to.
  String get key {
    if (variant != null) return variant!.id;
    return _sortedChoices.map((e) => '${e.key}:${e.value.id};').join();
  }

  /// The `p_selections` argument for `reserve_line`, or null when not a combo.
  List<Map<String, String>>? get selectionsJson => componentVariants.isEmpty
      ? null
      : [
          for (final choice in _sortedChoices)
            {'component_item_id': choice.key, 'variant_id': choice.value.id},
        ];

  /// Whether every required choice for [item] is made.
  bool isCompleteFor(MenuItem item) {
    if (item.isCombo) {
      return item.components
          .where((c) => c.item.hasVariants)
          .every((c) => componentVariants.containsKey(c.item.id));
    }
    return !item.hasVariants || variant != null;
  }
}

/// A cart line. The quantity here is backed by a real `stock_reservations` row,
/// so it is authoritative rather than a local guess.
class CartLine {
  const CartLine({
    required this.item,
    required this.quantity,
    this.reservationId = '',
    this.selection = CartSelection.none,
  });

  final MenuItem item;
  final int quantity;

  /// The `stock_reservations` row; + and - act on exactly this line.
  final String reservationId;
  final CartSelection selection;

  /// Parses a `stock_reservations` row fetched with its item embedded.
  static CartLine? fromReservation(Map<String, dynamic> row) {
    final itemMap = row['menu_items'];
    if (itemMap is! Map<String, dynamic>) return null;
    final item = MenuItem.fromMap(itemMap);

    MenuItemVariant? variant;
    final variantId = row['variant_id']?.toString();
    if (variantId != null) {
      for (final v in item.variants) {
        if (v.id == variantId) variant = v;
      }
    }

    final choices = <String, MenuItemVariant>{};
    final rawSelections = row['selections'];
    if (rawSelections is List) {
      for (final entry in rawSelections.whereType<Map>()) {
        final componentId = entry['component_item_id']?.toString();
        final chosenId = entry['variant_id']?.toString();
        for (final component in item.components) {
          if (component.item.id != componentId) continue;
          for (final v in component.item.variants) {
            if (v.id == chosenId) choices[component.item.id] = v;
          }
        }
      }
    }

    return CartLine(
      item: item,
      quantity: _asInt(row['quantity'], 1),
      reservationId: _asString(row['id']),
      selection: CartSelection(variant: variant, componentVariants: choices),
    );
  }

  int get unitPriceCents => item.priceForSelection(selection);
  String get unitPriceLabel => Money.format(unitPriceCents);

  /// The price without any special, for the struck-through "was" price.
  int get regularUnitPriceCents =>
      item.withSpecial(null).priceForSelection(selection);
  bool get isDiscounted => unitPriceCents < regularUnitPriceCents;

  int get lineTotalCents => unitPriceCents * quantity;
  String get lineTotalLabel => Money.format(lineTotalCents);

  /// Busy-spinner key for this line.
  String get key => '${item.id}|${selection.key}';

  /// "Sweet Chilli", or "Burger · 2× Chips (Salted) · Coke (Zero)". Mirrors
  /// `line_details` in migration 0009.
  String? get details {
    if (item.isCombo) {
      if (item.components.isEmpty) return null;
      return item.components.map((c) {
        final choice = selection.componentVariants[c.item.id];
        return choice == null ? c.label : '${c.label} (${choice.name})';
      }).join(' · ');
    }
    return selection.variant?.name;
  }

  CartLine copyWith({int? quantity}) => CartLine(
        item: item,
        quantity: quantity ?? this.quantity,
        reservationId: reservationId,
        selection: selection,
      );
}

// ------------------------------------------------------------------ order --

enum OrderStatus {
  isNew,
  preparing,
  ready,
  collected,
  cancelled;

  static OrderStatus parse(Object? raw) => switch (raw?.toString()) {
        'preparing' => OrderStatus.preparing,
        'ready' => OrderStatus.ready,
        'collected' => OrderStatus.collected,
        'cancelled' => OrderStatus.cancelled,
        _ => OrderStatus.isNew,
      };

  String get wire => this == OrderStatus.isNew ? 'new' : name;

  String get label => switch (this) {
        OrderStatus.isNew => 'New',
        OrderStatus.preparing => 'Preparing',
        OrderStatus.ready => 'Ready for collection',
        OrderStatus.collected => 'Collected',
        OrderStatus.cancelled => 'Cancelled',
      };

  /// BR-7: forward only, and no transition out of a terminal state.
  OrderStatus? get next => switch (this) {
        OrderStatus.isNew => OrderStatus.preparing,
        OrderStatus.preparing => OrderStatus.ready,
        OrderStatus.ready => OrderStatus.collected,
        _ => null,
      };

  String? get advanceLabel => switch (this) {
        OrderStatus.isNew => 'Start preparing',
        OrderStatus.preparing => 'Mark as ready',
        OrderStatus.ready => 'Mark as collected',
        _ => null,
      };

  bool get isCancellable =>
      this == OrderStatus.isNew || this == OrderStatus.preparing;

  bool get isTerminal =>
      this == OrderStatus.collected || this == OrderStatus.cancelled;
}

enum PaymentMethod {
  cash,
  card;

  static PaymentMethod parse(Object? raw) =>
      raw?.toString() == 'card' ? PaymentMethod.card : PaymentMethod.cash;

  String get wire => name;
  String get label => this == PaymentMethod.card ? 'Card' : 'Cash';
}

enum PaymentState {
  pending,
  paid,
  failed,
  refunded;

  static PaymentState parse(Object? raw) => switch (raw?.toString()) {
        'paid' => PaymentState.paid,
        'failed' => PaymentState.failed,
        'refunded' => PaymentState.refunded,
        _ => PaymentState.pending,
      };

  String get label => switch (this) {
        PaymentState.paid => 'Paid',
        PaymentState.failed => 'Payment failed',
        PaymentState.refunded => 'Refunded',
        PaymentState.pending => 'Pay at counter',
      };
}

class OrderItem {
  const OrderItem({
    required this.name,
    required this.unitPriceCents,
    required this.quantity,
    this.details,
  });

  final String name;
  final int unitPriceCents;
  final int quantity;

  /// The variety or combo parts chosen (migration 0009).
  final String? details;

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        name: _asString(map['name'], 'Item'),
        unitPriceCents: _asInt(map['unit_price_cents']),
        quantity: _asInt(map['quantity'], 1),
        details: _asOptionalText(map['details']),
      );

  int get lineTotalCents => unitPriceCents * quantity;
  String get lineTotalLabel => Money.format(lineTotalCents);
}

class Order {
  const Order({
    required this.id,
    required this.studentId,
    required this.cafeteriaId,
    required this.status,
    required this.paymentMethod,
    required this.paymentState,
    required this.totalCents,
    required this.collectionRef,
    required this.createdAt,
    this.items = const [],
    this.cafeteriaName,
    this.studentName,
  });

  final String id;
  final String studentId;
  final String cafeteriaId;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentState paymentState;
  final int totalCents;

  /// REQ-61: the short code staff match against the queue.
  final String collectionRef;

  final DateTime? createdAt;
  final List<OrderItem> items;
  final String? cafeteriaName;
  final String? studentName;

  factory Order.fromMap(Map<String, dynamic> map) {
    final rawItems = map['order_items'] as List<dynamic>?;
    final cafeteria = map['cafeterias'] as Map<String, dynamic>?;
    final student = map['profiles'] as Map<String, dynamic>?;

    return Order(
      id: _asString(map['id']),
      studentId: _asString(map['student_id']),
      cafeteriaId: _asString(map['cafeteria_id']),
      status: OrderStatus.parse(map['status']),
      paymentMethod: PaymentMethod.parse(map['payment_method']),
      paymentState: PaymentState.parse(map['payment_state']),
      totalCents: _asInt(map['total_cents']),
      collectionRef: _asString(map['collection_ref']),
      createdAt: _asDate(map['created_at']),
      items: rawItems
              ?.whereType<Map<String, dynamic>>()
              .map(OrderItem.fromMap)
              .toList() ??
          const [],
      cafeteriaName: cafeteria?['name'] as String?,
      studentName: student?['name'] as String?,
    );
  }

  String get totalLabel => Money.format(totalCents);

  /// "Pay at counter" only makes sense for cash; a card order waiting on
  /// Paystack reads differently.
  String get paymentLabel => switch (paymentState) {
        PaymentState.paid => 'Paid',
        PaymentState.failed => 'Card payment failed',
        PaymentState.refunded => 'Refunded',
        PaymentState.pending => paymentMethod == PaymentMethod.card
            ? 'Awaiting card payment'
            : 'Pay at counter',
      };

  int get itemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);
}

// ----------------------------------------------------------- notification --

class AppNotification {
  const AppNotification({
    required this.id,
    required this.message,
    required this.type,
    this.title,
    this.createdAt,
  });

  final String id;
  final String message;
  final String type;
  final String? title;
  final DateTime? createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: _asString(map['id']),
        message: _asString(map['message']),
        type: _asString(map['type'], 'info'),
        title: map['title'] as String?,
        createdAt: _asDate(map['created_at']),
      );

  bool get isLowStock => type == 'low_stock';
  bool get isNewItem => type == 'new_item';
}

/// What a notification is about. Each kind can be switched off separately in
/// notification settings; [roles] says who can receive it.
enum NotificationKind {
  orderPlaced('order_placed', 'Order placed', 'Confirmation when your order goes through', {UserRole.student}),
  orderPreparing('order_preparing', 'Being prepared', 'When the kitchen starts on your order', {UserRole.student}),
  orderReady('order_ready', 'Ready for collection', 'When your order is waiting at the counter', {UserRole.student}),
  orderCollected('order_collected', 'Collected', 'When your order is marked collected', {UserRole.student}),
  orderCancelled('order_cancelled', 'Cancellations', 'When an order is cancelled', {UserRole.student, UserRole.staff}),
  paymentReceived('payment_received', 'Payment received', 'When a card payment is confirmed', {UserRole.student}),
  paymentFailed('payment_failed', 'Payment problems', 'When a card payment does not go through', {UserRole.student}),
  newOrder('new_order', 'New orders', 'Every new order placed at your cafeteria', {UserRole.staff}),
  announcement('announcement', 'Announcements', 'Notices from the cafeterias', {UserRole.student, UserRole.staff});

  const NotificationKind(this.wire, this.label, this.description, this.roles);

  final String wire;
  final String label;
  final String description;
  final Set<UserRole> roles;

  static NotificationKind parse(Object? raw) {
    for (final kind in values) {
      if (kind.wire == raw) return kind;
    }
    return NotificationKind.announcement;
  }

  /// The order-related kinds go to the high-importance "Order updates"
  /// channel; announcements to a quieter one.
  bool get isOrderUpdate => this != NotificationKind.announcement;

  static List<NotificationKind> forRole(UserRole role) =>
      values.where((kind) => kind.roles.contains(role)).toList();
}

/// A notice addressed to one person, written by the database when one of
/// their orders moves (migration 0011).
class UserNotification {
  const UserNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.orderId,
    this.createdAt,
    this.readAt,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final String? orderId;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory UserNotification.fromMap(Map<String, dynamic> map) => UserNotification(
        id: _asString(map['id']),
        kind: NotificationKind.parse(map['kind']),
        title: _asString(map['title'], 'Update'),
        body: _asString(map['body']),
        orderId: _asOptionalText(map['order_id']),
        createdAt: _asDate(map['created_at']),
        readAt: _asDate(map['read_at']),
      );
}
