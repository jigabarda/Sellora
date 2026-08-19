import '../models/entities.dart';

/// One product in a cart, and how many of it.
class CartLine {
  CartLine({required this.product, required this.qty});

  final Product product;
  int qty;

  double get subtotal => qty * product.price;

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
  bool add(Product product, {int qty = 1}) {
    if (qty < 1) return false;

    final max = product.trackStock ? product.stock : null;
    if (max != null && max < 1) return false;

    final existing = lines.indexWhere((l) => l.product.id == product.id);
    if (existing >= 0) {
      final line = lines[existing];
      if (line.atMax) return false;
      line.qty = max == null ? line.qty + qty : (line.qty + qty).clamp(1, max);
      return true;
    }

    lines.add(
      CartLine(product: product, qty: max == null ? qty : qty.clamp(1, max)),
    );
    return true;
  }

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
  List<({String productId, String name, int qty, double unitPrice})>
      toSaleLines() => lines
          .map((l) => (
                productId: l.product.id,
                name: l.product.name,
                qty: l.qty,
                unitPrice: l.product.price,
              ))
          .toList(growable: false);
}
