import '../models/entities.dart';
import '../text/fuzzy.dart' as fuzzy;
import 'quick_command.dart';

/// Turns a typed or spoken phrase into an intention, matched against the
/// business's own products, customers and expense categories.
///
/// Pure: no database, no clock, no I/O. The vocabulary it matches against is
/// passed in, which is what makes this a closed problem rather than open
/// language understanding — a typical business has ten products and ten
/// customers, not a dictionary.
///
/// Fails closed. When nothing scores well enough, or two things score equally,
/// it returns [UnparsedCommand] instead of its best guess.
class QuickEntryParser {
  const QuickEntryParser();

  QuickCommand parse(
    String input, {
    required List<Product> products,
    required List<Customer> customers,
  }) {
    final tokens = _tokenise(input);
    if (tokens.isEmpty) return UnparsedCommand(input);

    // Inactive products cannot be sold, so they must not be matchable — the
    // same exclusion the sale form and the low-stock rules already apply.
    final sellable = products.where((p) => p.active).toList();

    final number = _extractNumber(tokens);
    final words = tokens
        .where((t) => !_isNumberToken(t) && !_stopWords.contains(t))
        .toList();

    final (:customer, :remaining) = _splitCustomer(words, customers);

    final product = _bestMatch(remaining, sellable, (p) => p.name);
    final category = _matchCategory(remaining);

    // A sale needs a product; an expense needs both a category and an amount,
    // since an expense with no amount is not an expense.
    final canBeSale = product != null;
    final canBeExpense = category != null && number != null;

    if (canBeSale && canBeExpense) {
      // Both plausible. Prefer the sale: it is the far more frequent action,
      // and the mistake is visible on a form the user is already reading.
      return _sale(product, number, customer);
    }
    if (canBeSale) return _sale(product, number, customer);
    if (canBeExpense) {
      return AddExpenseCommand(
        amount: number.toDouble(),
        category: category,
        note: input.trim(),
      );
    }
    return UnparsedCommand(input);
  }

  RecordSaleCommand _sale(Product product, num? number, Customer? customer) {
    // No number said means one of the thing — "purified refill" is a sale of
    // one, not a sale of none.
    final qty = (number ?? 1).toInt();
    return RecordSaleCommand(
      product: product,
      quantity: qty < 1 ? 1 : qty,
      customer: customer,
    );
  }

  /// Splits a trailing customer clause off the utterance.
  ///
  /// `kay`/`for` separates "2 refills" from "Aling Nena". The tokens are only
  /// removed if something on the right actually matches a customer — otherwise
  /// "500 for gas" would lose the word that identifies the category.
  ({Customer? customer, List<String> remaining}) _splitCustomer(
    List<String> words,
    List<Customer> customers,
  ) {
    final at = words.indexWhere(_customerMarkers.contains);
    if (at < 0) return (customer: null, remaining: words);

    final left = words.sublist(0, at);
    final right = words.sublist(at + 1);
    final match = _bestMatch(right, customers, (c) => c.name);
    if (match == null) return (customer: null, remaining: words);
    return (customer: match, remaining: left);
  }

  T? _bestMatch<T>(
          List<String> query, List<T> candidates, String Function(T) name) =>
      fuzzy.bestMatch(query, candidates, name);

  String? _matchCategory(List<String> words) {
    for (final entry in _categorySynonyms.entries) {
      for (final word in words) {
        if (entry.value.any((s) => fuzzy.tokenMatches(word, s))) return entry.key;
      }
    }
    return null;
  }

  num? _extractNumber(List<String> tokens) {
    for (final token in tokens) {
      final digits = num.tryParse(token);
      if (digits != null) return digits;
      final word = _numberWord(token);
      if (word != null) return word;
    }
    return null;
  }

  bool _isNumberToken(String token) =>
      num.tryParse(token) != null || _numberWord(token) != null;

  /// English and Tagalog numerals, including the linker Tagalog attaches when
  /// counting — "dalawa" becomes "dalawang" before a noun, and users type it
  /// that way because that is how they say it.
  int? _numberWord(String token) {
    final direct = _numberWords[token];
    if (direct != null) return direct;
    if (token.endsWith('ng')) {
      return _numberWords[token.substring(0, token.length - 2)];
    }
    return null;
  }

  List<String> _tokenise(String input) => fuzzy.tokenise(input);
}

const _customerMarkers = {'kay', 'for', 'para', 'sa'};

/// Dropped before matching. `na`/`ng` are Tagalog linkers, and the rest are
/// filler that would otherwise dilute the score of a real match.
const _stopWords = {
  'na',
  'ng',
  'nga',
  'po',
  'yung',
  'ang',
  'the',
  'a',
  'an',
  'of',
  'and',
  'piece',
  'pieces',
  'pcs',
  'unit',
  'units',
  'x',
};

const _numberWords = <String, int>{
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'isa': 1,
  'dalawa': 2,
  'tatlo': 3,
  'apat': 4,
  'lima': 5,
  'anim': 6,
  'pito': 7,
  'walo': 8,
  'siyam': 9,
  'sampu': 10,
};

/// The six expense categories are fixed English words nobody says out loud.
/// This maps what people actually say — in either language — onto them. It can
/// be exhaustive precisely because the category list is closed.
const _categorySynonyms = <String, List<String>>{
  'Transport': [
    'transport',
    'gas',
    'gasolina',
    'fuel',
    'diesel',
    'fare',
    'pamasahe',
    'delivery',
    'padala',
    'tricycle',
    'jeep',
  ],
  'Utilities': [
    'utilities',
    'utility',
    'kuryente',
    'electricity',
    'electric',
    'tubig',
    'water',
    'internet',
    'wifi',
    'bill',
    'bills',
    'meralco',
  ],
  'Rent': ['rent', 'upa', 'arkila', 'renta', 'lease'],
  'Payroll': [
    'payroll',
    'sweldo',
    'suweldo',
    'salary',
    'wages',
    'wage',
    'allowance',
  ],
  'Supplies': [
    'supplies',
    'supply',
    'gamit',
    'materials',
    'material',
    'stocks',
    'inventory',
    'caps',
    'seals',
  ],
  'Other': ['other', 'others', 'iba', 'misc', 'miscellaneous'],
};
