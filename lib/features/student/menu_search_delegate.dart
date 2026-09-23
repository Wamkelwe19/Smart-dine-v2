import 'package:flutter/material.dart';

import '../../core/theme/app_dimens.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/menu_item_card.dart';

/// REQ-43 / REQ-44 / REQ-45: search item names across every cafeteria,
/// case-insensitively, showing each result's outlet and trading status.
///
/// The old delegate fetched the entire `menu_items` table once with no limit
/// and filtered it in Dart. Filtering now happens in the database.
class MenuSearchDelegate extends SearchDelegate<void> {
  MenuSearchDelegate({required this.catalog, required this.onAdd});

  final CatalogRepository catalog;
  final Future<void> Function(MenuItem item) onAdd;

  /// Cached per query string.
  ///
  /// `buildSuggestions` runs on every keystroke *and* on every unrelated
  /// rebuild. Handing `FutureBuilder` a freshly created future each time would
  /// fire a database round trip per frame and flash the spinner constantly.
  String? _cachedQuery;
  Future<List<MenuItem>>? _cachedResults;

  Future<List<MenuItem>> _search(String term) {
    if (_cachedQuery == term && _cachedResults != null) return _cachedResults!;
    _cachedQuery = term;
    _cachedResults = catalog.searchMenuItems(term);
    return _cachedResults!;
  }

  @override
  String get searchFieldLabel => 'Search all cafeterias';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    if (query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search the whole campus',
        message: 'Type a dish name to find it at any cafeteria.',
      );
    }

    return FutureBuilder<List<MenuItem>>(
      future: _search(query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? const <MenuItem>[];
        // REQ-45: an empty result set stated in words.
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            message: 'Nothing on any menu matches "${query.trim()}".',
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: AppBreakpoints.gridColumns(constraints.maxWidth),
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.lg,
              childAspectRatio: 0.64,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return MenuItemCard(
                item: item,
                showCafeteriaName: true,
                onAdd: () => onAdd(item),
              );
            },
          ),
        );
      },
    );
  }
}
