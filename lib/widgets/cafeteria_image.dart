import 'package:flutter/material.dart';

import '../core/config/dining_images.dart';
import '../core/theme/app_colors.dart';
import '../data/models/models.dart';
import 'app_widgets.dart';

/// A dining hall's cover photo.
///
/// Resolves in order: the photo staff uploaded, the photo bundled with the app
/// (see [DiningImages]), then a branded placeholder, so a hall never renders
/// as a broken or empty frame.
class CafeteriaImage extends StatefulWidget {
  const CafeteriaImage({
    super.key,
    required this.cafeteria,
    this.heroTag,
  });

  final Cafeteria cafeteria;

  /// Shared with the hall page header so the photo carries across the push.
  final Object? heroTag;

  static String heroTagFor(Cafeteria cafeteria) => 'cafeteria-${cafeteria.id}';

  @override
  State<CafeteriaImage> createState() => _CafeteriaImageState();
}

class _CafeteriaImageState extends State<CafeteriaImage> {
  late Future<String?> _asset = DiningImages.assetFor(widget.cafeteria.name);

  @override
  void didUpdateWidget(covariant CafeteriaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cafeteria.name != widget.cafeteria.name) {
      _asset = DiningImages.assetFor(widget.cafeteria.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(name: widget.cafeteria.name);

    final Widget image = widget.cafeteria.imageUrl != null
        ? Image.network(
            widget.cafeteria.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _bundledOr(placeholder),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const AppSkeleton(height: double.infinity, radius: 0),
          )
        : _bundledOr(placeholder);

    final sized = SizedBox.expand(child: image);
    return widget.heroTag == null
        ? sized
        : Hero(tag: widget.heroTag!, child: sized);
  }

  Widget _bundledOr(Widget placeholder) => FutureBuilder<String?>(
        future: _asset,
        builder: (context, snapshot) {
          final path = snapshot.data;
          if (path == null) return placeholder;
          return Image.asset(
            path,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );
        },
      );
}

/// Warm brand gradient with the hall's initial: reads as intentional, not as
/// a missing photo.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandPale, AppColors.primaryContainer],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -24,
            bottom: -36,
            child: Text(
              initial,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 180,
                    height: 1,
                    color: AppColors.brand.withValues(alpha: 0.18),
                  ),
            ),
          ),
          const Center(
            child: Icon(Icons.storefront_outlined,
                size: 48, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
