import 'package:flutter/material.dart';

import '../data/models/models.dart';

/// The icon for a menu category, shared by the hall tabs and staff screens.
IconData categoryIcon(MenuCategory category) => switch (category) {
      MenuCategory.meal => Icons.dinner_dining_outlined,
      MenuCategory.combo => Icons.fastfood_outlined,
      MenuCategory.beverage => Icons.local_cafe_outlined,
      MenuCategory.snack => Icons.cookie_outlined,
    };
