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
