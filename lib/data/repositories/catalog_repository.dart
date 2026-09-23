import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../models/models.dart';

/// Cafeterias, menu items and menu-item management.
class CatalogRepository {
  CatalogRepository({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved lazily so the repository can be constructed (and
  /// subclassed in tests) without a live Supabase instance.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  // ------------------------------------------------------------- reading --

  /// The embeds every menu, search and cart query needs: cafeteria, live
  /// specials, varieties, and for combos each part with its varieties.
  ///
  /// Each embed names its foreign-key column (`!menu_item_id` and so on):
  /// menu_items and menu_item_variants are also linked through the cart and
  /// order tables, and without the hint PostgREST refuses the embed as
  /// ambiguous.
  static const itemEmbeds = '*, cafeterias!cafeteria_id(name, is_open, image_url), '
      'menu_specials!menu_item_id(*), menu_item_variants!menu_item_id(*), '
      'combo_components!combo_item_id(quantity, sort_order, '
      'component:menu_items!component_item_id(*, '
      'menu_item_variants!menu_item_id(*)))';

  /// A hall's full menu — varieties, combo parts and live specials attached —
  /// kept live.
  ///
  /// Realtime cannot deliver joined rows, so the four tables that make up a
  /// menu are watched for *changes* (all carry cafeteria_id), and each burst
  /// of changes triggers one joined re-fetch. A slow tick also re-fetches so a
  /// special that starts or ends while the page is open appears or goes.
  Stream<List<MenuItem>> watchHallMenu(String cafeteriaId) {
    final subscriptions = <StreamSubscription<Object?>>[];
    Timer? debounce;
    Timer? tick;
    late final StreamController<List<MenuItem>> controller;

    Future<void> refresh() async {
      try {
        final items = await fetchHallMenu(cafeteriaId);
        if (!controller.isClosed) controller.add(items);
      } catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      }
    }

    void schedule() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 150), refresh);
    }

    controller = StreamController<List<MenuItem>>(
      onListen: () {
        for (final table in const [
          'menu_items',
          'menu_item_variants',
          'menu_specials',
          'combo_components',
        ]) {
          subscriptions.add(
            _client
                .from(table)
                .stream(primaryKey: ['id'])
                .eq('cafeteria_id', cafeteriaId)
                .listen((_) => schedule(), onError: controller.addError),
          );
        }
        tick = Timer.periodic(const Duration(minutes: 1), (_) => schedule());
      },
      onCancel: () async {
        debounce?.cancel();
        tick?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// One joined read of a hall's menu, name ascending.
  Future<List<MenuItem>> fetchHallMenu(String cafeteriaId) async {
    final rows = await _client
        .from('menu_items')
        .select(itemEmbeds)
        .eq('cafeteria_id', cafeteriaId)
        .order('name');
    return rows.map<MenuItem>((r) => MenuItem.fromMap(r)).toList();
  }

  /// REQ-33 / REQ-34: live cafeteria list in name order.
  Stream<List<Cafeteria>> watchCafeterias() => _client
      .from('cafeterias')
      .stream(primaryKey: ['id'])
      .order('name')
      .map((rows) => rows.map(Cafeteria.fromMap).toList());

  /// REQ-38 / REQ-39: live menu for one cafeteria, name ascending.
  Stream<List<MenuItem>> watchMenu(String cafeteriaId) => _client
      .from('menu_items')
      .stream(primaryKey: ['id'])
      .eq('cafeteria_id', cafeteriaId)
      .order('name')
      .map((rows) => rows.map(MenuItem.fromMap).toList());

  Future<List<Cafeteria>> fetchCafeterias() async {
    final rows = await _client.from('cafeterias').select().order('name');
    return rows.map<Cafeteria>((r) => Cafeteria.fromMap(r)).toList();
  }

  /// REQ-43 / REQ-44: search item names across every cafeteria, ignoring case,
  /// carrying each result's cafeteria name and trading status.
  ///
  /// Filtering happens in the database rather than by fetching the whole menu
  /// and filtering in Dart, which is what the old `FoodSearchDelegate` did with
  /// no limit at all.
  Future<List<MenuItem>> searchMenuItems(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final rows = await _client
        .from('menu_items')
        .select(itemEmbeds)
        .ilike('name', '%$term%')
        .order('name')
        .limit(50);

    return rows.map<MenuItem>((r) => MenuItem.fromMap(r)).toList();
  }

  // ------------------------------------------------------------ specials --

  /// Every special, or one cafeteria's, live-updating. Includes scheduled,
  /// paused and ended ones; callers filter with [MenuSpecial.status].
  Stream<List<MenuSpecial>> watchSpecials({String? cafeteriaId}) {
    final table = _client.from('menu_specials').stream(primaryKey: ['id']);
    final filtered =
        cafeteriaId == null ? table : table.eq('cafeteria_id', cafeteriaId);
    return filtered
        .order('created_at', ascending: false)
        .map((rows) => rows.map(MenuSpecial.fromMap).toList());
  }

  /// The home carousel: live specials joined to their item and cafeteria,
  /// cheapest discount first. Items that cannot be ordered are left out, so
  /// students are never shown a deal they cannot take.
  Future<List<MenuSpecial>> fetchLiveSpecials() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client
        .from('menu_specials')
        .select('*, menu_items!menu_item_id($itemEmbeds)')
        .eq('is_active', true)
        .lte('starts_at', now)
        .or('ends_at.is.null,ends_at.gt.$now')
        .order('created_at', ascending: false)
        .limit(20);

    final at = DateTime.now();
    final specials = rows
        .map<MenuSpecial>((r) => MenuSpecial.fromMap(r))
        .where((s) =>
            s.isLiveAt(at) &&
            s.item != null &&
            s.item!.availability().canOrder)
        .toList();

    // One card per item: keep the best special where an item has several.
    final byItem = <String, MenuSpecial>{};
    for (final special in specials) {
      final best = MenuSpecial.bestFor(
        special.item!,
        [?byItem[special.menuItemId], special],
        at,
      );
      if (best != null) byItem[special.menuItemId] = best;
    }
    return byItem.values.toList();
  }

  Future<void> createSpecial({
    required String menuItemId,
    required SpecialKind kind,
    int? percentOff,
    int? specialPriceCents,
    String? headline,
    DateTime? startsAt,
    DateTime? endsAt,
    bool isActive = true,
  }) async {
    await _client.from('menu_specials').insert({
      'menu_item_id': menuItemId,
      ..._specialFields(
        kind: kind,
        percentOff: percentOff,
        specialPriceCents: specialPriceCents,
        headline: headline,
        startsAt: startsAt,
        endsAt: endsAt,
        isActive: isActive,
      ),
    });
  }

  Future<void> updateSpecial({
    required String id,
    required String menuItemId,
    required SpecialKind kind,
    int? percentOff,
    int? specialPriceCents,
    String? headline,
    DateTime? startsAt,
    DateTime? endsAt,
    bool isActive = true,
  }) async {
    await _client.from('menu_specials').update({
      'menu_item_id': menuItemId,
      ..._specialFields(
        kind: kind,
        percentOff: percentOff,
        specialPriceCents: specialPriceCents,
        headline: headline,
        startsAt: startsAt,
        endsAt: endsAt,
        isActive: isActive,
      ),
    }).eq('id', id);
  }

  Future<void> setSpecialActive({required String id, required bool isActive}) =>
      _client.from('menu_specials').update({'is_active': isActive}).eq('id', id);

  Future<void> deleteSpecial(String id) =>
      _client.from('menu_specials').delete().eq('id', id);

  /// Sends only the value the kind uses; the table's check constraint refuses
  /// a percent special that also carries a price, and so on.
  Map<String, dynamic> _specialFields({
    required SpecialKind kind,
    required int? percentOff,
    required int? specialPriceCents,
    required String? headline,
    required DateTime? startsAt,
    required DateTime? endsAt,
    required bool isActive,
  }) {
    final trimmed = headline?.trim();
    return {
      'kind': kind.wire,
      'percent_off': kind == SpecialKind.percent ? percentOff : null,
      'special_price_cents':
          kind == SpecialKind.fixedPrice ? specialPriceCents : null,
      'headline': trimmed == null || trimmed.isEmpty ? null : trimmed,
      'starts_at': (startsAt ?? DateTime.now()).toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'is_active': isActive,
    };
  }

  // ---------------------------------------------------------- staff writes --
  // Every write below is additionally gated by RLS: the caller must be bound to
  // the owning cafeteria through staff_cafeterias (REQ-76, BR-3).

  /// The cafeterias this staff member may manage. REQ-36: the old dropdown
  /// listed every outlet and let staff change any of them.
  Future<List<Cafeteria>> fetchMyCafeterias() async {
    final rows = await _client
        .from('staff_cafeterias')
        .select('cafeterias(id, name, is_open, image_url)');

    return rows
        .map((row) => row['cafeterias'])
        .whereType<Map<String, dynamic>>()
        .map(Cafeteria.fromMap)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// REQ-82 / REQ-83.
  Future<void> setTradingStatus({
    required String cafeteriaId,
    required bool isOpen,
  }) async {
    await _client
        .from('cafeterias')
        .update({'is_open': isOpen})
        .eq('id', cafeteriaId);
  }

  /// The cafeteria's cover photo on the student home page. Null removes it.
  Future<void> setCafeteriaImage({
    required String cafeteriaId,
    required String? imageUrl,
  }) async {
    await _client
        .from('cafeterias')
        .update({'image_url': imageUrl})
        .eq('id', cafeteriaId);
  }

  /// REQ-80.
  static const int maxImageBytes = 5 * 1024 * 1024;

  /// Lets staff pick a photo from the gallery and uploads it to the
  /// `menu-images` bucket. Returns its public URL, or null if they cancelled.
  ///
  /// Namespaced by cafeteria so the storage policy can scope writes, with a
  /// collision-proof name (REQ-10, REQ-77).
  Future<String?> pickAndUploadImage({
    required String cafeteriaId,
    String prefix = '',
  }) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // REQ-80: the picker downscales before we ever read the bytes, which is
      // cheaper than compressing a full-resolution image afterwards.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    if (bytes.lengthInBytes > maxImageBytes) {
      throw const AppError(
          'That image is larger than 5 MB. Please choose a smaller one.');
    }

    final extension = picked.name.split('.').last.toLowerCase();
    final objectPath = '$cafeteriaId/$prefix'
        '${DateTime.now().millisecondsSinceEpoch}-'
        '${picked.name.hashCode.toUnsigned(32)}.$extension';

    final storage = _client.storage.from('menu-images');
    await storage.uploadBinary(objectPath, bytes);
    return storage.getPublicUrl(objectPath);
  }

  /// REQ-70 / REQ-73. Returns the new item's id, so its varieties or combo
  /// parts can be saved next.
  Future<String> createMenuItem({
    required String cafeteriaId,
    required String name,
    required int priceCents,
    required int stockCount,
    required bool isAvailable,
    MenuCategory category = MenuCategory.meal,
    String? description,
    String? imageUrl,
  }) async {
    final row = await _client
        .from('menu_items')
        .insert({
          'cafeteria_id': cafeteriaId,
          'name': name.trim(),
          'price_cents': priceCents,
          'stock_count': stockCount,
          'is_available': isAvailable,
          'category': category.wire,
          'description': _blankToNull(description),
          'image_url': imageUrl,
        })
        .select('id')
        .single();
    return row['id'].toString();
  }

  /// REQ-71.
  Future<void> updateMenuItem({
    required String id,
    required String name,
    required int priceCents,
    required int stockCount,
    required bool isAvailable,
    MenuCategory category = MenuCategory.meal,
    String? description,
    String? imageUrl,
  }) async {
    await _client.from('menu_items').update({
      'name': name.trim(),
      'price_cents': priceCents,
      'stock_count': stockCount,
      'is_available': isAvailable,
      'category': category.wire,
      'description': _blankToNull(description),
      'image_url': imageUrl,
    }).eq('id', id);
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Makes [itemId]'s varieties exactly [variants]: rows with an id are
  /// updated, rows without one are created, and any others are removed.
  ///
  /// Removal runs first so a renamed variety can take a name another one
  /// just gave up. A removed variety held in a cart drops its hold (there is
  /// nothing left to return stock to).
  Future<void> saveVariants(String itemId, List<MenuItemVariant> variants) async {
    final keepIds = [
      for (final v in variants)
        if (v.id.isNotEmpty) v.id,
    ];

    final removal =
        _client.from('menu_item_variants').delete().eq('menu_item_id', itemId);
    if (keepIds.isEmpty) {
      await removal;
    } else {
      await removal.not('id', 'in', '(${keepIds.join(',')})');
    }

    for (var index = 0; index < variants.length; index++) {
      final variant = variants[index];
      final fields = {
        'name': variant.name.trim(),
        'price_delta_cents': variant.priceDeltaCents,
        'stock_count': variant.stockCount,
        'is_available': variant.isAvailable,
        'sort_order': index,
      };
      if (variant.id.isEmpty) {
        await _client
            .from('menu_item_variants')
            .insert({...fields, 'menu_item_id': itemId});
      } else {
        await _client
            .from('menu_item_variants')
            .update(fields)
            .eq('id', variant.id);
      }
    }
  }

  /// Makes [comboId]'s parts exactly [parts], in order.
  Future<void> saveComboComponents(
    String comboId,
    List<({String itemId, int quantity})> parts,
  ) async {
    await _client.from('combo_components').delete().eq('combo_item_id', comboId);
    if (parts.isEmpty) return;
    await _client.from('combo_components').insert([
      for (var index = 0; index < parts.length; index++)
        {
          'combo_item_id': comboId,
          'component_item_id': parts[index].itemId,
          'quantity': parts[index].quantity,
          'sort_order': index,
        },
    ]);
  }

  /// REQ-75. Also removes the stored image (REQ-81) — the old code had no
  /// delete path at all, so orphaned objects accumulated in the bucket.
  Future<void> deleteMenuItem(MenuItem item) async {
    await _client.from('menu_items').delete().eq('id', item.id);
    await deleteImageIfOwned(item.imageUrl);
  }

  /// REQ-81: removes a storage object given its public URL. Silently ignores
  /// anything that is not one of ours.
  Future<void> deleteImageIfOwned(String? publicUrl) async {
    if (publicUrl == null || publicUrl.isEmpty) return;

    const marker = '/storage/v1/object/public/menu-images/';
    final index = publicUrl.indexOf(marker);
    if (index == -1) return;

    final objectPath = Uri.decodeComponent(
      publicUrl.substring(index + marker.length).split('?').first,
    );
    if (objectPath.isEmpty) return;

    try {
      await _client.storage.from('menu-images').remove([objectPath]);
    } catch (_) {
      // A failed cleanup must not fail the user's action; the object is
      // orphaned at worst.
    }
  }
}
