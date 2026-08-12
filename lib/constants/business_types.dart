/// Mirrors the `businessTypes` list in the web app's settings page.
///
/// Values are stored verbatim in `businesses.type`, so a business saved under
/// an older list can outlive it. Anything editing a stored type must tolerate a
/// value that is no longer here — see [withStoredBusinessType].
const kBusinessTypes = <String>[
  'Retail Store',
  'Food & Beverages',
  'Rental Business',
  'Water Station',
  'Wholesale & Distribution',
  'Services',
  'Manufacturing',
  'Other',
];

/// Picker options for a business whose stored [type] may predate the current
/// list. Keeps the old value selectable instead of tripping the dropdown's
/// "exactly one matching item" assertion or silently rewriting the record.
List<String> withStoredBusinessType(String? type) {
  if (type == null || type.isEmpty || kBusinessTypes.contains(type)) {
    return kBusinessTypes;
  }
  return [...kBusinessTypes, type];
}
