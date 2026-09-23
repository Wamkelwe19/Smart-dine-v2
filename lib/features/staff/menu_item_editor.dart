import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/category_icon.dart';

/// Create or edit a menu item (REQ-70, REQ-71, REQ-72): its category, its
/// varieties (flavours or sizes, each with its own stock and price), or — for
/// a combo — which of this hall's items it is made of.
///
/// The old dialog used bare unstyled `TextFormField`s while the rest of the app
/// used a themed field, validated only for emptiness (so a negative price or a
/// letter in the price field reached `double.parse` and threw), and uploaded
/// images to the bucket root under a key containing colons.
class MenuItemEditor extends StatefulWidget {
  const MenuItemEditor({
    super.key,
    required this.cafeteria,
    this.item,
    this.menu = const [],
  });

  final Cafeteria cafeteria;
  final MenuItem? item;

  /// This hall's items, to build a combo from.
  final List<MenuItem> menu;

  @override
  State<MenuItemEditor> createState() => _MenuItemEditorState();
}

/// A variety row being edited. [id] is empty until it is saved.
class _VarietyDraft {
  _VarietyDraft({
    this.id = '',
    String name = '',
    int deltaCents = 0,
    int stock = 0,
    this.onSale = true,
  })  : name = TextEditingController(text: name),
        delta = TextEditingController(
            text: deltaCents == 0 ? '' : (deltaCents / 100).toStringAsFixed(2)),
        stock = TextEditingController(text: stock.toString());

  factory _VarietyDraft.from(MenuItemVariant v) => _VarietyDraft(
        id: v.id,
        name: v.name,
        deltaCents: v.priceDeltaCents,
        stock: v.stockCount,
        onSale: v.isAvailable,
      );

  final String id;
  final TextEditingController name;
  final TextEditingController delta;
  final TextEditingController stock;
  bool onSale;

  MenuItemVariant toVariant(String itemId) => MenuItemVariant(
        id: id,
        menuItemId: itemId,
        name: name.text.trim(),
        priceDeltaCents: delta.text.trim().isEmpty
            ? 0
            : Money.centsFromRands(double.parse(delta.text.trim())),
        stockCount: int.parse(stock.text.trim()),
        isAvailable: onSale,
      );

  void dispose() {
    name.dispose();
    delta.dispose();
    stock.dispose();
  }
}

class _MenuItemEditorState extends State<MenuItemEditor> {
  final _formKey = GlobalKey<FormState>();
  final _catalog = CatalogRepository();

  late final TextEditingController _name =
      TextEditingController(text: widget.item?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.item?.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.item == null
        ? ''
        : (widget.item!.priceCents / 100).toStringAsFixed(2),
  );
  late final TextEditingController _stock = TextEditingController(
    text: widget.item?.stockCount.toString() ?? '',
  );

  late MenuCategory _category = widget.item?.category ?? MenuCategory.meal;
  late bool _available = widget.item?.isAvailable ?? true;
  late String? _imageUrl = widget.item?.imageUrl;
  String? _originalImageUrl;

  late final List<_VarietyDraft> _varieties = [
    for (final v in widget.item?.variants ?? const <MenuItemVariant>[])
      _VarietyDraft.from(v),
  ];

  /// Combo parts: item id and quantity, in display order.
  late final List<({String itemId, int quantity})> _parts = [
    for (final c in widget.item?.components ?? const <ComboComponent>[])
      (itemId: c.item.id, quantity: c.quantity),
  ];

  bool _uploading = false;
  bool _saving = false;

  bool get _isEditing => widget.item != null;
  bool get _isCombo => _category == MenuCategory.combo;

  /// Items a combo may include: this hall's non-combo items, not itself.
  List<MenuItem> get _eligibleParts => widget.menu
      .where((m) => !m.isCombo && m.id != widget.item?.id)
      .toList();

  MenuItem? _menuItem(String id) {
    for (final m in widget.menu) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _originalImageUrl = widget.item?.imageUrl;
    // The combo "bought separately" line follows the price as it is typed.
    _price.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    for (final v in _varieties) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _uploading = true);
    try {
      final url =
          await _catalog.pickAndUploadImage(cafeteriaId: widget.cafeteria.id);

      if (!mounted) return;
      setState(() {
        if (url != null) _imageUrl = url;
        _uploading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      context.showAppError(error);
    }
  }

  /// Checks the field validators cannot: unique variety names, and a combo
  /// with at least two items in it.
  String? _crossCheck() {
    if (_isCombo) {
      final units = _parts.fold(0, (sum, p) => sum + p.quantity);
      if (units < 2) return 'A combo needs at least two items in it.';
      if (_parts.any((p) => _menuItem(p.itemId) == null)) {
        return 'One of the combo items was removed from the menu. '
            'Take it out of the combo first.';
      }
      return null;
    }
    final names = <String>{};
    for (final v in _varieties) {
      if (!names.add(v.name.text.trim().toLowerCase())) {
        return 'Two varieties are both called "${v.name.text.trim()}".';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final problem = _crossCheck();
    if (problem != null) {
      context.showAppError(AppError(problem));
      return;
    }

    setState(() => _saving = true);
    try {
      final priceCents = Money.centsFromRands(double.parse(_price.text.trim()));
      // Stock lives on the varieties, or on a combo's parts, when there are any.
      final ownStock = _isCombo || _varieties.isNotEmpty
          ? 0
          : int.parse(_stock.text.trim());

      final String id;
      if (_isEditing) {
        id = widget.item!.id;
        await _catalog.updateMenuItem(
          id: id,
          name: _name.text,
          priceCents: priceCents,
          stockCount: ownStock,
          isAvailable: _available,
          category: _category,
          description: _description.text,
          imageUrl: _imageUrl,
        );
        // REQ-81: the replaced object is removed rather than orphaned.
        if (_originalImageUrl != null && _originalImageUrl != _imageUrl) {
          await _catalog.deleteImageIfOwned(_originalImageUrl);
        }
      } else {
        id = await _catalog.createMenuItem(
          cafeteriaId: widget.cafeteria.id,
          name: _name.text,
          priceCents: priceCents,
          stockCount: ownStock,
          isAvailable: _available,
          category: _category,
          description: _description.text,
          imageUrl: _imageUrl,
        );
      }

      // A combo has parts and no varieties; anything else the reverse.
      if (_isCombo) {
        if (widget.item?.hasVariants ?? false) {
          await _catalog.saveVariants(id, const []);
        }
        await _catalog.saveComboComponents(id, _parts);
      } else {
        if (widget.item?.isCombo ?? false) {
          await _catalog.saveComboComponents(id, const []);
        }
        if (_varieties.isNotEmpty || (widget.item?.hasVariants ?? false)) {
          await _catalog.saveVariants(
            id,
            [for (final v in _varieties) v.toVariant(id)],
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      context.showAppSuccess(_isEditing ? 'Item updated' : 'Item added');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPart() async {
    final taken = _parts.map((p) => p.itemId).toSet();
    final options = _eligibleParts.where((m) => !taken.contains(m.id)).toList();
    if (options.isEmpty) {
      context.showAppError(const AppError(
          'Add meals, drinks or snacks to your menu first, then build the '
          'combo from them.'));
      return;
    }

    final picked = await showModalBottomSheet<MenuItem>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.sm),
                child: Text('Add to combo',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
              ),
              for (final option in options)
                ListTile(
                  leading: Icon(categoryIcon(option.category),
                      color: AppColors.primary),
                  title: Text(option.name),
                  subtitle: Text([
                    option.priceLabel,
                    ?option.optionsSummary,
                  ].join(' · ')),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _parts.add((itemId: picked.id, quantity: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _saving || _uploading;

    // REQ-79: the sheet cannot be dismissed mid-upload.
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, controller) => Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(AppSpacing.gutter),
              children: [
                Text(
                  _isEditing ? 'Edit item' : 'New item',
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  widget.cafeteria.name,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),

                _imagePicker(theme),
                const SizedBox(height: AppSpacing.xl),

                Text('Category', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final category in MenuCategory.values)
                      ChoiceChip(
                        avatar: Icon(categoryIcon(category), size: 18),
                        label: Text(category.singular),
                        selected: _category == category,
                        showCheckmark: false,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => _category = category),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _name,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: _isCombo ? 'Combo name' : 'Item name',
                    hintText: _isCombo ? 'e.g. Burger Meal Deal' : null,
                    prefixIcon: Icon(categoryIcon(_category)),
                  ),
                  validator: (v) => Validators.required(v, 'item name'),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _description,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  maxLength: 140,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        enabled: !busy,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: _isCombo ? 'Combo price' : 'Price',
                          prefixText: 'R ',
                        ),
                        // REQ-74.
                        validator: Validators.price,
                      ),
                    ),
                    if (!_isCombo && _varieties.isEmpty) ...[
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: TextFormField(
                          controller: _stock,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Stock'),
                          validator: Validators.stock,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                if (_isCombo)
                  ..._comboSection(theme, busy)
                else
                  ..._varietySection(busy),

                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: _available,
                  onChanged: busy ? null : (v) => setState(() => _available = v),
                  title: const Text('On sale'),
                  subtitle: Text(
                    _available
                        ? 'Students can order this item.'
                        : 'Hidden from ordering, but kept on the menu.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: busy ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add to menu'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- varieties --

  List<Widget> _varietySection(bool busy) => [
        _SectionTitle(
          title: 'Varieties',
          subtitle: _varieties.isEmpty
              ? 'Optional. Add flavours or sizes (e.g. Sweet Chilli, Cheese) '
                  'and students must pick one.'
              : 'Stock is tracked per variety. Price ± is added to the price '
                  'above; leave it empty for the same price.',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < _varieties.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _VarietyRow(
              key: ObjectKey(_varieties[i]),
              draft: _varieties[i],
              enabled: !busy,
              onChanged: _refresh,
              onRemove: () => setState(() => _varieties.removeAt(i).dispose()),
            ),
          ),
        OutlinedButton.icon(
          onPressed:
              busy ? null : () => setState(() => _varieties.add(_VarietyDraft())),
          icon: const Icon(Icons.add),
          label: Text(_varieties.isEmpty ? 'Add varieties' : 'Add another variety'),
        ),
      ];

  // ------------------------------------------------------------ combos --

  List<Widget> _comboSection(ThemeData theme, bool busy) {
    final separately = _parts.fold<int>(0, (sum, part) {
      final item = _menuItem(part.itemId);
      return sum + (item?.priceCents ?? 0) * part.quantity;
    });
    final typed = double.tryParse(_price.text.trim());
    final comboCents = typed == null ? null : Money.centsFromRands(typed);

    return [
      const _SectionTitle(
        title: "What's included",
        subtitle: 'Built from items on your menu. Ordering the combo takes '
            'stock from each of them, and students choose the variety for '
            'any item that has them.',
      ),
      const SizedBox(height: AppSpacing.sm),
      for (var i = 0; i < _parts.length; i++)
        _PartRow(
          item: _menuItem(_parts[i].itemId),
          quantity: _parts[i].quantity,
          enabled: !busy,
          onQuantity: (q) => setState(
              () => _parts[i] = (itemId: _parts[i].itemId, quantity: q)),
          onRemove: () => setState(() => _parts.removeAt(i)),
        ),
      OutlinedButton.icon(
        onPressed: busy ? null : _addPart,
        icon: const Icon(Icons.add),
        label: const Text('Add an item'),
      ),
      if (_parts.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Text(
            comboCents == null || comboCents >= separately
                ? 'Bought separately: ${Money.format(separately)}'
                : 'Bought separately: ${Money.format(separately)} · students '
                    'save ${Money.format(separately - comboCents)}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    ];
  }

  Widget _imagePicker(ThemeData theme) {
    return Column(
      children: [
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.brandPale,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: theme.colorScheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: _uploading
              ? const Center(child: CircularProgressIndicator())
              : _imageUrl == null
                  ? const Center(
                      child: Icon(Icons.add_photo_alternate_outlined,
                          size: 44, color: AppColors.primary),
                    )
                  // REQ-78: preview before saving.
                  : Image.network(
                      _imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 44, color: AppColors.primary),
                      ),
                    ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading || _saving ? null : _pickImage,
                icon: const Icon(Icons.upload_outlined),
                label: Text(_imageUrl == null ? 'Add photo' : 'Replace photo'),
              ),
            ),
            if (_imageUrl != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: _uploading || _saving
                    ? null
                    : () => setState(() => _imageUrl = null),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        Text(
          'Up to 5 MB. Large photos are resized automatically.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _VarietyRow extends StatelessWidget {
  const _VarietyRow({
    super.key,
    required this.draft,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final _VarietyDraft draft;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.name,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Variety',
                    hintText: 'e.g. Sweet Chilli',
                    isDense: true,
                  ),
                  validator: Validators.varietyName,
                ),
              ),
              IconButton(
                tooltip: 'Remove variety',
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.delta,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Price ±',
                    prefixText: 'R ',
                    hintText: '0.00',
                    isDense: true,
                  ),
                  validator: Validators.priceDelta,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  controller: draft.stock,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Stock', isDense: true),
                  validator: Validators.stock,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                children: [
                  Text('On sale', style: theme.textTheme.labelSmall),
                  Switch(
                    value: draft.onSale,
                    onChanged: enabled
                        ? (v) {
                            draft.onSale = v;
                            onChanged();
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.item,
    required this.quantity,
    required this.enabled,
    required this.onQuantity,
    required this.onRemove,
  });

  /// Null when the item has since been deleted from the menu.
  final MenuItem? item;
  final int quantity;
  final bool enabled;
  final ValueChanged<int> onQuantity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = this.item;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Icon(
              item == null ? Icons.help_outline : categoryIcon(item.category),
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item?.name ?? 'Removed item',
                      style: theme.textTheme.titleSmall),
                  Text(
                    item == null
                        ? 'Remove this and pick another'
                        : item.hasVariants
                            ? 'Student chooses: '
                                '${item.variants.map((v) => v.name).join(', ')}'
                            : item.priceLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // At one, minus takes the item out of the combo.
            QuantityStepper(
              quantity: quantity,
              onDecrease: enabled
                  ? (quantity > 1 ? () => onQuantity(quantity - 1) : onRemove)
                  : null,
              onIncrease:
                  enabled && quantity < 9 ? () => onQuantity(quantity + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}
