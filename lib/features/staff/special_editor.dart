import 'package:flutter/material.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/special_card.dart';

/// Create or edit a special on one of this cafeteria's items.
///
/// Shows a live preview built from the same [SpecialCard] students see, so
/// staff know exactly how the deal will read before publishing it.
class SpecialEditor extends StatefulWidget {
  const SpecialEditor({
    super.key,
    required this.cafeteria,
    required this.menu,
    this.special,
    this.initialItem,
  });

  final Cafeteria cafeteria;

  /// The cafeteria's items to choose from.
  final List<MenuItem> menu;

  /// Null creates a new special.
  final MenuSpecial? special;

  /// Pre-selects an item, for "Create special" from the Menu tab.
  final MenuItem? initialItem;

  @override
  State<SpecialEditor> createState() => _SpecialEditorState();
}

class _SpecialEditorState extends State<SpecialEditor> {
  final _formKey = GlobalKey<FormState>();
  final _catalog = CatalogRepository();

  late String? _itemId =
      widget.special?.menuItemId ?? widget.initialItem?.id ?? _firstItemId;
  late SpecialKind _kind = widget.special?.kind ?? SpecialKind.percent;

  late final TextEditingController _percent = TextEditingController(
    text: widget.special?.percentOff?.toString() ?? '20',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.special?.specialPriceCents == null
        ? ''
        : (widget.special!.specialPriceCents! / 100).toStringAsFixed(2),
  );
  late final TextEditingController _headline =
      TextEditingController(text: widget.special?.headline ?? '');

  /// Null start means "as soon as it is saved".
  late DateTime? _startsAt = _isEditing ? widget.special!.startsAt : null;
  late DateTime? _endsAt = widget.special?.endsAt;
  late bool _active = widget.special?.isActive ?? true;

  bool _saving = false;

  bool get _isEditing => widget.special != null;

  String? get _firstItemId => widget.menu.isEmpty ? null : widget.menu.first.id;

  MenuItem? get _item {
    for (final item in widget.menu) {
      if (item.id == _itemId) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Rebuild the preview as the values are typed.
    _percent.addListener(_refresh);
    _price.addListener(_refresh);
    _headline.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _percent.dispose();
    _price.dispose();
    _headline.dispose();
    super.dispose();
  }

  int? get _percentValue => int.tryParse(_percent.text.trim());

  int? get _priceValue {
    final parsed = double.tryParse(_price.text.trim());
    return parsed == null ? null : Money.centsFromRands(parsed);
  }

  /// The special as it would be saved, for the preview.
  MenuSpecial? _draft() {
    final item = _item;
    if (item == null) return null;
    final headline = _headline.text.trim();
    return MenuSpecial(
      id: widget.special?.id ?? 'preview',
      menuItemId: item.id,
      cafeteriaId: widget.cafeteria.id,
      kind: _kind,
      percentOff: _kind == SpecialKind.percent ? _percentValue : null,
      specialPriceCents: _kind == SpecialKind.fixedPrice ? _priceValue : null,
      headline: headline.isEmpty ? null : headline,
      startsAt: _startsAt ?? DateTime.now(),
      endsAt: _endsAt,
      isActive: _active,
      item: item,
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final item = _item;
    if (item == null) {
      context.showAppError(const AppError('Please choose an item first.'));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final start = _startsAt ?? DateTime.now();
    if (_endsAt != null && !_endsAt!.isAfter(start)) {
      context.showAppError(
          const AppError('The end time must be after the start time.'));
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await _catalog.updateSpecial(
          id: widget.special!.id,
          menuItemId: item.id,
          kind: _kind,
          percentOff: _percentValue,
          specialPriceCents: _priceValue,
          headline: _headline.text,
          startsAt: start,
          endsAt: _endsAt,
          isActive: _active,
        );
      } else {
        await _catalog.createSpecial(
          menuItemId: item.id,
          kind: _kind,
          percentOff: _percentValue,
          specialPriceCents: _priceValue,
          headline: _headline.text,
          startsAt: start,
          endsAt: _endsAt,
          isActive: _active,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      context.showAppSuccess(_isEditing ? 'Special updated' : 'Special published');
    } catch (error) {
      if (!mounted) return;
      context.showAppError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    final draft = _draft();

    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  _isEditing ? 'Edit special' : 'New special',
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  widget.cafeteria.name,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),

                if (draft != null) ...[
                  Text('Preview',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 290,
                    child: IgnorePointer(
                      child: SpecialCard(special: draft, now: draft.startsAt),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                DropdownButtonFormField<String>(
                  initialValue: _itemId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    prefixIcon: Icon(Icons.restaurant_menu),
                  ),
                  items: [
                    for (final menuItem in widget.menu)
                      DropdownMenuItem(
                        value: menuItem.id,
                        child: Text(
                          '${menuItem.name} · ${menuItem.priceLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _itemId = value),
                  validator: (value) =>
                      value == null ? 'Please choose an item.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),

                SegmentedButton<SpecialKind>(
                  segments: const [
                    ButtonSegment(
                      value: SpecialKind.percent,
                      label: Text('% off'),
                      icon: Icon(Icons.percent),
                    ),
                    ButtonSegment(
                      value: SpecialKind.fixedPrice,
                      label: Text('Price'),
                      icon: Icon(Icons.sell_outlined),
                    ),
                    ButtonSegment(
                      value: SpecialKind.featured,
                      label: Text('Featured'),
                      icon: Icon(Icons.star_outline_rounded),
                    ),
                  ],
                  selected: {_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: _saving
                      ? null
                      : (selection) => setState(() => _kind = selection.first),
                ),
                const SizedBox(height: AppSpacing.lg),

                ..._valueField(item),

                TextFormField(
                  controller: _headline,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Headline (optional)',
                    hintText: 'e.g. Friday Feast',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                Text('When', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _WhenTile(
                  icon: Icons.play_circle_outline,
                  label: 'Starts',
                  value: _startsAt == null
                      ? 'As soon as you publish'
                      : TimeAgo.dayClock(_startsAt!),
                  onTap: _saving
                      ? null
                      : () async {
                          final picked =
                              await _pickDateTime(_startsAt ?? DateTime.now());
                          if (picked != null) setState(() => _startsAt = picked);
                        },
                  onClear: _startsAt == null || _saving
                      ? null
                      : () => setState(() => _startsAt = null),
                ),
                const SizedBox(height: AppSpacing.sm),
                _WhenTile(
                  icon: Icons.stop_circle_outlined,
                  label: 'Ends',
                  value: _endsAt == null
                      ? 'No end date'
                      : TimeAgo.dayClock(_endsAt!),
                  onTap: _saving
                      ? null
                      : () async {
                          final base = _startsAt ?? DateTime.now();
                          final picked = await _pickDateTime(
                              _endsAt ?? base.add(const Duration(hours: 4)));
                          if (picked != null) setState(() => _endsAt = picked);
                        },
                  onClear: _endsAt == null || _saving
                      ? null
                      : () => setState(() => _endsAt = null),
                ),
                const SizedBox(height: AppSpacing.md),

                SwitchListTile(
                  value: _active,
                  onChanged: _saving ? null : (v) => setState(() => _active = v),
                  title: const Text('Active'),
                  subtitle: Text(
                    _active
                        ? 'Students see this special during its window.'
                        : 'Saved but hidden until you switch it on.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: _saving || widget.menu.isEmpty ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Publish special'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _valueField(MenuItem? item) {
    final theme = Theme.of(context);
    final base = item?.priceCents ?? 0;

    switch (_kind) {
      case SpecialKind.percent:
        final percent = _percentValue;
        return [
          TextFormField(
            controller: _percent,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Discount',
              suffixText: '% off',
              helperText: item == null || percent == null || percent < 1 || percent > 90
                  ? 'Between 1% and 90%.'
                  : '${item.priceLabel} → ${Money.format(item.withSpecial(_draft()).effectivePriceCents)}',
            ),
            validator: Validators.percent,
          ),
          const SizedBox(height: AppSpacing.lg),
        ];
      case SpecialKind.fixedPrice:
        return [
          TextFormField(
            controller: _price,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Special price',
              prefixText: 'R ',
              helperText: item == null ? null : 'Usually ${item.priceLabel}.',
            ),
            validator: (value) => Validators.specialPrice(value, base),
          ),
          const SizedBox(height: AppSpacing.lg),
        ];
      case SpecialKind.featured:
        return [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Row(
              children: [
                const Icon(Icons.star_outline_rounded,
                    color: AppColors.secondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Promoted on the home page at its usual price.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ];
    }
  }
}

class _WhenTile extends StatelessWidget {
  const _WhenTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.textSecondary)),
                    Text(value, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Icon(Icons.edit_calendar_outlined, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
