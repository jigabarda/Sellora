import '../models/entities.dart';
import '../text/fuzzy.dart' as fuzzy;
import 'notebook_line.dart';

/// Reads a photographed ledger page into candidate sales.
///
/// Pure: it takes recognised text, not an image. The recogniser is a separate,
/// thin adapter, which is what lets every rule in here be tested against fixed
/// strings rather than against a camera.
///
/// The idea it rests on: a notebook page is not free-form handwriting. It is a
/// closed vocabulary — ten products, ten customers, small whole quantities —
/// with a **checksum written on every line**. `Nena 2 refill 50` proves itself
/// against a ₱25 price. So the parser does not try to read well; it tries to
/// read *in a way that adds up*, and reports the lines that do not.
///
/// That inverts the usual confidence problem. Where general OCR gives a
/// per-character probability nobody can act on, this gives a per-line verdict
/// the owner can: either the arithmetic agrees with the price list, or the line
/// is held back for them to look at.
class NotebookParser {
  const NotebookParser();

  NotebookPage parse(
    String recognisedText, {
    required List<Product> products,
    required List<Customer> customers,
  }) {
    // Inactive products cannot be sold, so they must not be matchable — the
    // same exclusion the sale form and Quick Entry already apply.
    final sellable = products.where((p) => p.active && p.price > 0).toList();

    final lines = <NotebookLine>[];
    for (final raw in recognisedText.split('\n')) {
      if (raw.trim().isEmpty) continue;
      lines.add(_parseLine(raw, sellable, customers));
    }
    return NotebookPage(lines: lines);
  }

  NotebookLine _parseLine(
    String raw,
    List<Product> products,
    List<Customer> customers,
  ) {
    final tokens = fuzzy.tokenise(raw);
    if (tokens.isEmpty) {
      return NotebookLine(raw: raw, status: LineStatus.ignored);
    }

    final numbers = <double>[];
    final words = <String>[];
    for (final token in tokens) {
      final n = _asNumber(token);
      if (n != null) {
        numbers.add(n);
      } else if (!_noiseWords.contains(token)) {
        words.add(token);
      }
    }

    if (_isHeading(words, numbers)) {
      return NotebookLine(raw: raw, status: LineStatus.ignored);
    }

    final split = _splitCustomer(words, customers, products);
    final customer = split.customer;
    final productQuery = split.remaining;

    // A deliberately loose shortlist. Anything below the normal bar has to be
    // vouched for by the arithmetic before it is used.
    final shortlist = fuzzy.rank(
      productQuery,
      products,
      (p) => p.name,
      threshold: _looseScore,
    );

    final readings = _reconcile(shortlist, numbers);

    if (readings.length == 1) {
      final r = readings.single;
      return NotebookLine(
        raw: raw,
        status: LineStatus.reconciled,
        product: r.product,
        customer: customer,
        quantity: r.quantity,
        writtenAmount: r.amount,
      );
    }

    if (readings.length > 1) {
      // Two products whose prices both explain the number on the page. The
      // page cannot settle it and neither can we, so the owner does.
      final names = readings.map((r) => r.product.name).toSet().toList();
      final r = readings.first;
      return NotebookLine(
        raw: raw,
        status: LineStatus.needsReview,
        product: r.product,
        customer: customer,
        quantity: r.quantity,
        writtenAmount: r.amount,
        note: names.length > 1
            ? 'Could be ${names.take(2).join(' or ')} — both add up'
            : 'More than one way to read the quantity',
      );
    }

    return _unreconciled(raw, shortlist, numbers, customer);
  }

  /// Nothing added up. Fall back to plain text matching, at the strict
  /// threshold, and say why the line is unconfirmed.
  NotebookLine _unreconciled(
    String raw,
    List<({Product item, double score})> shortlist,
    List<double> numbers,
    Customer? customer,
  ) {
    final confident =
        shortlist.where((s) => s.score >= fuzzy.minimumScore).toList();

    if (confident.isEmpty) {
      return NotebookLine(raw: raw, status: LineStatus.unreadable);
    }
    if (confident.length > 1 &&
        (confident[0].score - confident[1].score) < fuzzy.tieMargin) {
      return NotebookLine(
        raw: raw,
        status: LineStatus.unreadable,
        note: 'Could be '
            '${confident.take(2).map((s) => s.item.name).join(' or ')}',
      );
    }

    final product = confident.first.item;
    final (:quantity, :amount) = _fallbackFigures(numbers);
    final expected = product.price * quantity;

    return NotebookLine(
      raw: raw,
      status: LineStatus.needsReview,
      product: product,
      customer: customer,
      quantity: quantity,
      writtenAmount: amount,
      note: amount == null
          ? 'No amount written to check this against'
          : 'Page says ${_peso(amount)}, price list makes it ${_peso(expected)}',
    );
  }

  /// Reads quantity and amount out of the numbers when arithmetic could not.
  ///
  /// Two or more numbers on a ledger line is almost always quantity then
  /// amount. A single number is a quantity if it is small enough to be one and
  /// an amount otherwise — nobody sells 340 of anything out of a notebook.
  ({int quantity, double? amount}) _fallbackFigures(List<double> numbers) {
    if (numbers.isEmpty) return (quantity: 1, amount: null);
    if (numbers.length == 1) {
      final only = numbers.single;
      if (_isQuantity(only)) return (quantity: only.toInt(), amount: null);
      return (quantity: 1, amount: only);
    }
    final first = numbers.first;
    return (
      quantity: _isQuantity(first) ? first.toInt() : 1,
      amount: numbers.last,
    );
  }

  /// Every way of reading the line that makes the arithmetic come out right.
  ///
  /// Returning more than one is a real answer, not a failure to decide: it
  /// means the page genuinely does not distinguish them.
  List<({Product product, int quantity, double amount})> _reconcile(
    List<({Product item, double score})> shortlist,
    List<double> numbers,
  ) {
    final out = <({Product product, int quantity, double amount})>[];
    final seen = <String>{};

    void add(Product p, int qty, double amount) {
      if (seen.add('${p.id}:$qty')) {
        out.add((product: p, quantity: qty, amount: amount));
      }
    }

    for (final candidate in shortlist) {
      final p = candidate.item;

      // "2 refill 50" — a quantity and the amount it produced.
      for (var i = 0; i < numbers.length; i++) {
        if (!_isQuantity(numbers[i])) continue;
        final qty = numbers[i].toInt();
        for (var j = i + 1; j < numbers.length; j++) {
          if (_equal(p.price * qty, numbers[j])) add(p, qty, numbers[j]);
        }
      }

      // "refill 50" — only the amount survived, so divide it back out. This is
      // what recovers a quantity the recogniser dropped or mangled.
      for (final n in numbers) {
        final qty = n / p.price;
        final rounded = qty.round();
        if (rounded >= 1 && rounded <= _maxQuantity && _equal(qty, rounded)) {
          add(p, rounded, n);
        }
      }
    }
    return out;
  }

  /// Splits a leading customer name off the line.
  ///
  /// Ledger pages put the name first with no marker word — `Nena 2 refill 50`,
  /// not `2 refill kay Nena`. So instead of looking for a separator, every
  /// prefix is tried and scored jointly with the product left behind. Taking
  /// the customer match on its own would let a shop named "Ice House" swallow
  /// the word that identifies an ice sale.
  ({Customer? customer, List<String> remaining}) _splitCustomer(
    List<String> words,
    List<Customer> customers,
    List<Product> products,
  ) {
    if (words.isEmpty || customers.isEmpty) {
      return (customer: null, remaining: words);
    }

    final noSplit = _productConfidence(words, products);
    var best = (customer: null as Customer?, remaining: words, score: noSplit);

    final maxPrefix = words.length - 1 < _maxNameWords
        ? words.length - 1
        : _maxNameWords;
    for (var take = 1; take <= maxPrefix; take++) {
      final prefix = words.sublist(0, take);
      final rest = words.sublist(take);
      final match = fuzzy.bestMatch(prefix, customers, (c) => c.name);
      if (match == null) continue;

      // Both halves have to be worth believing, and the pair has to beat
      // leaving the line whole.
      final combined =
          fuzzy.score(prefix, match.name) + _productConfidence(rest, products);
      if (combined > best.score) {
        best = (customer: match, remaining: rest, score: combined);
      }
    }
    return (customer: best.customer, remaining: best.remaining);
  }

  double _productConfidence(List<String> words, List<Product> products) {
    final ranked = fuzzy.rank(words, products, (p) => p.name,
        threshold: _looseScore);
    return ranked.isEmpty ? 0 : ranked.first.score;
  }

  /// A number that could plausibly be a count of things rather than pesos.
  bool _isQuantity(double n) =>
      n >= 1 && n <= _maxQuantity && _equal(n, n.roundToDouble());

  bool _equal(num a, num b) => (a - b).abs() < 0.005;

  /// Digits, including the ones the recogniser mangles.
  ///
  /// `50` written by hand comes back as `5O` often enough to be worth
  /// repairing. The repair only runs on tokens that already contain a real
  /// digit, so "SO" stays the word it is and only "5O" becomes fifty.
  double? _asNumber(String token) {
    final direct = double.tryParse(token);
    if (direct != null) return direct;
    if (!token.contains(RegExp(r'[0-9]'))) return null;

    final repaired = token.split('').map((c) => _confusions[c] ?? c).join();
    return double.tryParse(repaired);
  }

  /// Dates, column titles and running totals are not transactions.
  bool _isHeading(List<String> words, List<double> numbers) {
    if (words.isEmpty && numbers.isEmpty) return true;
    if (words.isEmpty) return false;
    return words.every((w) => _headingWords.contains(w));
  }

  String _peso(double amount) => '₱${amount.toStringAsFixed(2)}';
}

/// Below the normal matching bar, but reachable when the amount on the page
/// confirms it. Nothing at this level is accepted on the strength of the text
/// alone.
const _looseScore = 0.34;

/// Above this, a number is money rather than a count.
const _maxQuantity = 99;

/// Customer names run to "Aling Nena" but not much further.
const _maxNameWords = 2;

const _confusions = <String, String>{
  'o': '0',
  'l': '1',
  'i': '1',
  's': '5',
  'b': '8',
  'z': '2',
  'g': '9',
  'q': '9',
};

/// Words that mark a line as structure rather than a sale. A line made only of
/// these is skipped no matter what numbers sit beside it — `Total 1250` is a
/// sum of the page, not a sale of 1,250 things.
const _headingWords = {
  'jan', 'january', 'feb', 'february', 'mar', 'march', 'apr', 'april', //
  'may', 'jun', 'june', 'jul', 'july', 'aug', 'august', 'sep', 'sept',
  'september', 'oct', 'october', 'nov', 'november', 'dec', 'december',
  'mon', 'monday', 'tue', 'tues', 'tuesday', 'wed', 'wednesday', 'thu',
  'thurs', 'thursday', 'fri', 'friday', 'sat', 'saturday', 'sun', 'sunday',
  'total', 'totals', 'kabuuan', 'sum', 'date', 'petsa', 'page', 'pahina',
  'name', 'pangalan', 'item', 'items', 'qty', 'quantity', 'amount', 'halaga',
  'price', 'presyo',
};

/// Column noise that carries no meaning on a ledger line.
const _noiseWords = {
  'x', 'pcs', 'pc', 'pieces', 'piece', 'unit', 'units', 'php', 'p', 'ea',
  'the', 'a', 'an', 'ng', 'na', 'po',
};
