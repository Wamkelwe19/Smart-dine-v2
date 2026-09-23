import 'package:flutter/services.dart';

/// Bundled dining-hall photos: the default a staff upload overrides.
///
/// Drop a photo into `assets/dining/` named after the hall's slug — lowercase,
/// with anything that is not a letter or digit turned into a hyphen — and it is
/// picked up without a code change. "Main Dining Hall" looks for
/// `assets/dining/main-dining-hall.jpg` (or `.jpeg`, `.png`, `.webp`).
class DiningImages {
  const DiningImages._();

  static const _folder = 'assets/dining/';
  static const _extensions = ['jpg', 'jpeg', 'png', 'webp'];

  static Future<Set<String>>? _assets;

  static String slug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// The bundled photo for [cafeteriaName], or null when none was shipped.
  static Future<String?> assetFor(String cafeteriaName) async {
    final assets = await (_assets ??= _loadManifest());
    final base = '$_folder${slug(cafeteriaName)}';
    for (final extension in _extensions) {
      final path = '$base.$extension';
      if (assets.contains(path)) return path;
    }
    return null;
  }

  static Future<Set<String>> _loadManifest() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((path) => path.startsWith(_folder))
          .toSet();
    } catch (_) {
      // No manifest (tests) simply means no bundled photos.
      return const {};
    }
  }
}
