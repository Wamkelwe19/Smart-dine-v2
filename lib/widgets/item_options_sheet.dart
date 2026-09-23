import 'package:flutter/material.dart';

import '../core/error/app_error.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import '../features/student/cart_controller.dart';
import 'app_widgets.dart';
import 'special_badge.dart';

/// Adds [item] to the cart, first asking for a variety or combo choices when
/// it needs them. Every "add" button in the student app goes through here, so
/// an item with options can never reach the cart without them.
Future<void> addItemToCart(
  BuildContext context, {
  required CartController cart,
  required MenuItem item,
  bool? parentCafeteriaOpen,
}) async {
  if (item.needsOptions) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ItemOptionsSheet(
        item: item,
        cart: cart,
        parentCafeteriaOpen: parentCafeteriaOpen,
      ),
    );
    return;
  }

  try {
    await cart.add(item);
    if (!context.mounted) return;
    context.showAppSuccess('${item.name} added to your cart');
  } catch (error) {
    if (!context.mounted) return;
    // "Sold out" is information the student needs, not a silent failure.
    context.showAppError(error);
  }
}

/// Choose a variety (Doritos: Sweet Chilli / Cheese), or the choices for each
/// part of a combo that has them (which drink), then the quantity.
class ItemOptionsSheet extends StatefulWidget {
  const ItemOptionsSheet({
    super.key,
    required this.item,
    required this.cart,
    this.parentCafeteriaOpen,
  });

  final MenuItem item;
  final CartController cart;
  final bool? parentCafeteriaOpen;

  @override
  State<ItemOptionsSheet> createState() => _ItemOptionsSheetState();
}

class _ItemOptionsSheetState extends State<ItemOptionsSheet> {
  MenuItemVariant? _variant;
  final Map<String, MenuItemVariant> _choices = {};
  int _quantity = 1;
  bool _adding = false;

  MenuItem get _item => widget.item;

  @override
  void initState() {
    super.initState();
    // Preselect when there is only one real choice, so a single-option item
    // is one tap away.
    final orderable = _item.variants.where((v) => v.canOrder).toList();
    if (!_item.isCombo && orderable.length == 1) _variant = orderable.single;
    for (final part in _item.components) {
      final options = part.item.variants
          .where((v) => v.isAvailable && v.stockCount >= part.quantity)
          .toList();
      if (options.length == 1) _choices[part.item.id] = options.single;
    }
  }

  CartSelection get _selection =>
      CartSelection(variant: _variant, componentVariants: Map.of(_choices));

  bool get _complete => _selection.isCompleteFor(_item);

  /// The most of this choice that stock allows, so + stops at a real limit.
  int get _maxQuantity {
    if (_item.isCombo) {
      int? max;
      for (final part in _item.components) {
        final choice = _choices[part.item.id];
        final stock = choice?.stockCount ?? part.item.stockCount;
        final units = stock ~/ part.quantity;
        if (max == null || units < max) max = units;
      }
      return (max ?? 1).clamp(1, 20);
    }
    return (_variant?.stockCount ?? _item.stockCount).clamp(1, 20);
  }

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await widget.cart.add(_item, selection: _selection, quantity: _quantity);
      if (!mounted) return;
      // Shown through the app's messenger, so it outlives the sheet.
      context.showAppSuccess('${_item.name} added to your cart');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOrder = _item
        .availability(parentCafeteriaOpen: widget.parentCafeteriaOpen)
        .canOrder;
    final unitPrice = _item.priceForSelection(_selection);
    final regularUnit = _item.withSpecial(null).priceForSelection(_selection);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.lg),
              children: [
                _Header(item: _item),
                const SizedBox(height: AppSpacing.lg),
                if (_item.isCombo)
                  ..._comboSections(theme)
                else
                  ..._varietySection(theme),
              ],
            ),
          ),
          _AddBar(
            quantity: _quantity,
            maxQuantity: _maxQuantity,
            totalCents: unitPrice * _quantity,
            regularTotalCents: regularUnit * _quantity,
            enabled: canOrder && _complete && !_adding,
            busy: _adding,
            hint: !canOrder
                ? _item
                    .availability(parentCafeteriaOpen: widget.parentCafeteriaOpen)
                    .label
                : _complete
                    ? null
                    : _item.isCombo
                        ? 'Make your choices above'
                        : 'Choose an option above',
            onQuantity: (q) => setState(() => _quantity = q),
            onAdd: _add,
          ),
        ],
      ),
    );
  }

  List<Widget> _varietySection(ThemeData theme) => [
        Text('Choose an option', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final variant in _item.variants)
              _VarietyChip(
                label: variant.name,
                detail: variant.canOrder
                    ? (variant.priceDeltaCents == 0
                        ? null
                        : Money.format(_item.priceFor(variant)))
                    : 'Sold out',
                selected: _variant?.id == variant.id,
                enabled: variant.canOrder,
                onSelected: () => setState(() {
                  _variant = variant;
                  _quantity = 1;
                }),
              ),
          ],
        ),
      ];

  List<Widget> _comboSections(ThemeData theme) {
    final fixed = _item.components.where((c) => !c.item.hasVariants).toList();
    final choosable = _item.components.where((c) => c.item.hasVariants).toList();

    return [
      if (fixed.isNotEmpty) ...[
        Text('Included', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final part in fixed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(part.label, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
      for (final part in choosable) ...[
        Text(
          'Choose your ${part.item.name.toLowerCase()}'
          '${part.quantity > 1 ? ' (×${part.quantity})' : ''}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final variant in part.item.variants)
              _VarietyChip(
                label: variant.name,
                detail: variant.isAvailable && variant.stockCount >= part.quantity
                    ? variant.deltaLabel.isEmpty
                        ? null
                        : variant.deltaLabel
                    : 'Sold out',
                selected: _choices[part.item.id]?.id == variant.id,
                enabled:
                    variant.isAvailable && variant.stockCount >= part.quantity,
                onSelected: () => setState(() {
                  _choices[part.item.id] = variant;
                  _quantity = 1;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      color: AppColors.brandPale,
      child: const Icon(Icons.restaurant_menu, color: AppColors.primary, size: 32),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            height: 88,
            width: 88,
            child: item.imageUrl == null
                ? fallback
                : Image.network(item.imageUrl!,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.special != null) ...[
                SpecialBadge(special: item.special!),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(item.name, style: theme.textTheme.titleLarge),
              if (item.cafeteriaName != null)
                Text(
                  item.cafeteriaName!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              if (item.description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.description!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VarietyChip extends StatelessWidget {
  const _VarietyChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChoiceChip(
      selected: selected,
      onSelected: enabled ? (_) => onSelected() : null,
      showCheckmark: false,
      selectedColor: AppColors.primaryContainer,
      side: BorderSide(
        color: selected ? AppColors.primary : theme.colorScheme.outline,
        width: selected ? 2 : 1,
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: enabled ? null : AppColors.textDisabled,
              decoration: enabled ? null : TextDecoration.lineThrough,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: enabled ? AppColors.primary : AppColors.textDisabled,
              ),
            ),
        ],
      ),
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.quantity,
    required this.maxQuantity,
    required this.totalCents,
    required this.regularTotalCents,
    required this.enabled,
    required this.busy,
    required this.onQuantity,
    required this.onAdd,
    this.hint,
  });

  final int quantity;
  final int maxQuantity;
  final int totalCents;
  final int regularTotalCents;
  final bool enabled;
  final bool busy;
  final String? hint;
  final ValueChanged<int> onQuantity;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: AppElevation.sheet,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hint != null) ...[
                Text(hint!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  QuantityStepper(
                    quantity: quantity,
                    onDecrease: quantity > 1 && !busy
                        ? () => onQuantity(quantity - 1)
                        : null,
                    onIncrease: quantity < maxQuantity && enabled
                        ? () => onQuantity(quantity + 1)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: enabled ? onAdd : null,
                      child: busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text.rich(
                                TextSpan(
                                  text: 'Add · ${Money.format(totalCents)}',
                                  children: [
                                    if (regularTotalCents > totalCents)
                                      TextSpan(
                                        text: '  ${Money.format(regularTotalCents)}',
                                        style: const TextStyle(
                                          decoration: TextDecoration.lineThrough,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
