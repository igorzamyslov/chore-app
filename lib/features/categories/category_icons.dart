/// The fixed set of icon identifiers the settings category-edit icon
/// picker offers.
library;

/// Every identifier `categoryIcon` (`lib/app/theme.dart`) maps to its own
/// distinct icon, in the picker's display order.
///
/// Kept as a hand-maintained list in sync with `categoryIcon`'s switch
/// cases: anything not in this list (including the `'label'` identifier a
/// brand-new category starts with) falls through to `categoryIcon`'s
/// `default` branch (`Icons.label_outlined`) instead of a dedicated icon.
/// The sync in the other direction — every entry here having its own case
/// over there — is pinned by a test (`test/app/theme_test.dart`), because
/// a missing case is silent: the tile still renders, just with the wrong,
/// duplicated glyph.
///
/// The first fifteen entries are the identifiers `CategoryRepository`
/// seeds categories with; the last nine are picker-only additions with no
/// seeded category behind them (backlog G-5a).
const List<String> categoryIconIdentifiers = [
  'cleaning_services',
  'skillet',
  'local_laundry_service',
  'yard',
  'pets',
  'build',
  'directions_car',
  'nutrition',
  'egg',
  'set_meal',
  'bakery_dining',
  'ac_unit',
  'local_cafe',
  'home',
  'shopping_bag',
  'bathtub',
  'delete',
  'potted_plant',
  'child_care',
  'pedal_bike',
  'description',
  'celebration',
  'thermostat',
  'fitness_center',
];
