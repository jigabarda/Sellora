import '../models/entities.dart';
import '../repositories/sale_repository.dart';

/// One product in a cart, and how many of it.
class CartLine {
  CartLine({
    required this.product,
    required this.qty,
    this.days = 1,
    this.startsAt,
  });

  final Product product;
  int qty;

  /// Days rented. Always 1 for something sold outright, so the subtotal below
  /// is one expression rather than a branch — a sold line is simply a rental
  /// of one day, arithmetically.
  int days;

  /// The day the rental period starts. Null until someone picks dates, in
  /// which case it starts when the sale is recorded.
  DateTime? startsAt;

  /// The day it is due back — the start plus the days agreed.
  ///
  /// This is the same arithmetic the return screen does, and it is the reason
  /// the day count is `end - start` rather than an inclusive count of calendar
  /// days: the return date has to come back out of the number unchanged.
  DateTime? get endsAt {
    final from = startsAt;
    if (from == null) return null;
    return DateTime(from.year, from.month, from.day + days);
  }

  bool get isRental => product.rental;

  double get subtotal => qty * product.price * days;

  /// Null means no ceiling: the product does not track stock.
  int? get max => product.trackStock ? product.stock : null;

  bool get atMax => max != null && qty >= max!;
}

/// The rules a cart follows, in one place.
///
/// Extracted when the counter view arrived. Both it and the sale form put lines
/// in a cart and hand them to `recordSale`, and the part that would quietly
/// drift between two copies is not the recording — it is *this*: whether a
/// second tap on the same product merges or adds a row, and what happens when
/// the shelf runs out. Two screens that answered those differently would let
/// one of them oversell.
///
/// Deliberately not a Riverpod notifier. A cart belongs to the screen that is
/// building it and dies with it; hoisting it into app state would mean a
/// half-built sale outliving the screen that started it.
class SaleCart {
  final List<CartLine> lines = [];

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  double get total => lines.fold(0.0, (sum, l) => sum + l.subtotal);
  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);

  /// How many of [product] are already in the cart.
  int quantityOf(String productId) {
    for (final line in lines) {
      if (line.product.id == productId) return line.qty;
    }
    return 0;
  }

  /// Adds [qty] of [product], merging with an existing row rather than
  /// starting a second one for the same thing.
  ///
  /// Returns false when nothing could be added because the shelf is already
  /// exhausted — the caller can then say so rather than silently doing nothing.
  bool add(Product product, {int qty = 1, int? days}) {
    if (qty < 1) return false;

    final max = product.trackStock ? product.stock : null;
    if (max != null && max < 1) return false;

    final existing = lines.indexWhere((l) => l.product.id == product.id);
    if (existing >= 0) {
      final line = lines[existing];
      if (days != null) line.days = days < 1 ? 1 : days;
      if (line.atMax) return false;
      line.qty = max == null ? line.qty + qty : (line.qty + qty).clamp(1, max);
      return true;
    }

    final agreed = product.rental ? period : null;
    final line = CartLine(
      product: product,
      qty: max == null ? qty : qty.clamp(1, max),
      // A rental with no period stated is one day, not zero: the customer has
      // it today whatever else happens.
      days: days == null || days < 1 ? 1 : days,
    );
    lines.add(line);
    // Inherited after the fact rather than in the constructor so an explicit
    // `days` argument still wins — the caller asked for something specific.
    if (agreed != null && days == null) {
      setPeriod(line, agreed.start, agreed.end);
    }
    return true;
  }

  /// Days apply per line, not per sale: chairs for three days and a table for
  /// one is an ordinary booking, and forcing one period on the whole cart
  /// would make the owner split it into two transactions.
  void setDays(CartLine line, int days) => line.days = days < 1 ? 1 : days;

  /// Sets a line's period from the two dates that were actually agreed.
  ///
  /// The day count is `end - start`, so picking the 19th and the 22nd is three
  /// days and the 22nd is when it comes back. Same-day is charged as one:
  /// nobody hires chairs for nothing, and a zero would zero the money.
  void setPeriod(CartLine line, DateTime start, DateTime end) {
    final from = DateTime(start.year, start.month, start.day);
    final to = DateTime(end.year, end.month, end.day);
    final span = to.difference(from).inDays;
    line.startsAt = from;
    line.days = span < 1 ? 1 : span;
  }

  /// The period already agreed on this cart, if any.
  ///
  /// A booking is usually one event: chairs and tables go out and come back
  /// together. New rental lines inherit this so the dates are picked once
  /// rather than once per product, while still being editable per line.
  ({DateTime start, DateTime end})? get period {
    for (final line in lines) {
      final from = line.startsAt;
      final to = line.endsAt;
      if (line.isRental && from != null && to != null) {
        return (start: from, end: to);
      }
    }
    return null;
  }

  /// True when anything in the cart goes out expecting to come back.
  bool get hasRental => lines.any((l) => l.isRental);

  /// Sets an exact quantity, clamped to the shelf. Zero removes the row, so a
  /// caller can wire "set to 0" to delete without a separate branch.
  void setQuantity(CartLine line, int qty) {
    if (qty < 1) {
      remove(line);
      return;
    }
    final max = line.max;
    line.qty = max == null ? qty : qty.clamp(1, max);
  }

  void remove(CartLine line) => lines.remove(line);

  void clear() => lines.clear();

  /// The shape `SaleRepository.recordSale` takes.
  ///
  /// The unit price is read off the product now rather than remembered from
  /// when it was added, so a cart left open across a price change records what
  /// the product costs today.
  List<SaleLineDraft> toSaleLines() => lines
      .map((l) => SaleLineDraft(
            productId: l.product.id,
            name: l.product.name,
            qty: l.qty,
            unitPrice: l.product.price,
            days: l.days,
            startsAt: l.isRental ? l.startsAt : null,
          ))
      .toList(growable: false);
}
