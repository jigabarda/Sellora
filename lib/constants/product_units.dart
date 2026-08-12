/// Mirrors `unitOptions` in the web app's product form.
const kProductUnits = <String>[
  'pcs',
  'gallon',
  'liter',
  'kg',
  'bag',
  'set',
  'hour',
  'day',
];

const kDefaultProductUnit = 'pcs';

/// Picker options for a product whose stored [unit] may predate the current
/// list, so an unknown value stays selectable instead of tripping the
/// dropdown's "exactly one matching item" assertion.
List<String> withStoredUnit(String? unit) {
  if (unit == null || unit.isEmpty || kProductUnits.contains(unit)) {
    return kProductUnits;
  }
  return [...kProductUnits, unit];
}
