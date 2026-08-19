import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/models/entities.dart';
import 'package:sellora_mobile/data/sales/sale_cart.dart';

/// The cart is the one place the sale form and the counter agree about what a
/// second tap means and what happens when the shelf runs out. If these two
/// screens ever disagree, it will be because one of these rules got a second
/// implementation — so the rules are pinned here rather than in either screen.

Product _product({
  String id = 'prd_1',
  String name = 'Purified Refill',
  double price = 25,
  int stock = 10,
  bool trackStock = true,
  bool rental = false,
}) =>
    Product(
      id: id,
      businessId: 'biz',
      categoryId: null,
      name: name,
      description: '',
      sku: '',
      unit: 'pcs',
      price: price,
      stock: stock,
      trackStock: trackStock,
      rental: rental,
      active: true,
      createdAt: DateTime(2026),
    );

void main() {
  test('a second tap on the same product adds to the row it already has', () {
    final cart = SaleCart()
      ..add(_product())
      ..add(_product());

    expect(cart.lines.length, 1, reason: 'one product, one row');
    expect(cart.lines.single.qty, 2);
    expect(cart.itemCount, 2);
  });

  test('different products get their own rows', () {
    final cart = SaleCart()
      ..add(_product(id: 'a', name: 'Refill'))
      ..add(_product(id: 'b', name: 'Ice', price: 60));

    expect(cart.lines.length, 2);
    expect(cart.total, 85);
  });

  test('a tracked product cannot be taken past its stock', () {
    final cart = SaleCart();
    final water = _product(stock: 3);

    expect(cart.add(water, qty: 10), isTrue);
    // Clamped rather than refused: the owner asked for ten and can have three.
    expect(cart.lines.single.qty, 3);

    // Now it genuinely cannot take more, and says so.
    expect(cart.add(water), isFalse);
    expect(cart.lines.single.qty, 3);
  });

  test('an untracked product has no ceiling', () {
    final cart = SaleCart()
      ..add(_product(trackStock: false, stock: 0), qty: 99);
    expect(cart.lines.single.qty, 99);
    expect(cart.add(_product(trackStock: false, stock: 0)), isTrue);
    expect(cart.lines.single.qty, 100);
  });

  test('a product with none on the shelf never enters the cart', () {
    final cart = SaleCart();
    expect(cart.add(_product(stock: 0)), isFalse);
    expect(cart.isEmpty, isTrue);
  });

  test('setting a quantity clamps to stock', () {
    final cart = SaleCart()..add(_product(stock: 4));
    cart.setQuantity(cart.lines.single, 50);
    expect(cart.lines.single.qty, 4);
  });

  test('setting a quantity to zero removes the row', () {
    final cart = SaleCart()..add(_product());
    cart.setQuantity(cart.lines.single, 0);
    expect(cart.isEmpty, isTrue);
  });

  test('totals and counts follow the lines', () {
    final cart = SaleCart()
      ..add(_product(id: 'a', price: 25), qty: 2)
      ..add(_product(id: 'b', price: 60), qty: 3);

    expect(cart.itemCount, 5);
    expect(cart.total, 230);
  });

  test('quantityOf reports what the grid should badge', () {
    final cart = SaleCart()..add(_product(id: 'a'), qty: 4);
    expect(cart.quantityOf('a'), 4);
    expect(cart.quantityOf('b'), 0);
  });

  test('sale lines carry the price the product costs now', () {
    final cart = SaleCart()..add(_product(price: 25), qty: 2);
    final lines = cart.toSaleLines();

    expect(lines.length, 1);
    expect(lines.single.qty, 2);
    expect(lines.single.unitPrice, 25);
    expect(lines.single.name, 'Purified Refill');
  });

  test('a rental line multiplies by the days agreed', () {
    // Twenty chairs at ten pesos for three days is six hundred, not two
    // hundred. The whole rental feature is this one multiplication.
    final cart = SaleCart()
      ..add(_product(price: 10, stock: 50, rental: true), qty: 20);
    cart.setDays(cart.lines.single, 3);

    expect(cart.lines.single.subtotal, 600);
    expect(cart.total, 600);
    expect(cart.toSaleLines().single.days, 3);
  });

  test('a line starts at one day, so a plain sale is unaffected', () {
    final cart = SaleCart()..add(_product(price: 25), qty: 2);
    expect(cart.lines.single.days, 1);
    expect(cart.total, 50);
    expect(cart.toSaleLines().single.days, 1);
  });

  test('days below one are pulled back to one', () {
    // Nothing is rented for zero days, and a zero would zero the money.
    final cart = SaleCart()..add(_product(rental: true), qty: 1);
    cart.setDays(cart.lines.single, 0);
    expect(cart.lines.single.days, 1);
  });

  test('the cart knows whether anything on it is a rental', () {
    final cart = SaleCart()..add(_product(id: 'a'));
    expect(cart.hasRental, isFalse);

    cart.add(_product(id: 'b', rental: true));
    expect(cart.hasRental, isTrue);
  });

  test('days survive a quantity change', () {
    final cart = SaleCart()
      ..add(_product(price: 10, stock: 50, rental: true), qty: 5);
    cart.setDays(cart.lines.single, 4);
    cart.setQuantity(cart.lines.single, 10);

    expect(cart.lines.single.days, 4);
    expect(cart.total, 400);
  });

  group('rental periods are set by picking two dates', () {
    test('the day count is the span between them', () {
      // 19th to the 22nd is three days, and the 22nd is when it comes back.
      // Counting inclusively would make it four and quietly overcharge.
      final cart = SaleCart()
        ..add(_product(price: 10, stock: 50, rental: true), qty: 20);
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 22));

      expect(cart.lines.single.days, 3);
      expect(cart.total, 600, reason: '20 chairs x P10 x 3 days');
    });

    test('the end date comes back out of the day count unchanged', () {
      // The return screen derives the due date the same way, so if these two
      // ever disagreed the app would chase people up on the wrong day.
      final cart = SaleCart()..add(_product(rental: true));
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 22));

      expect(cart.lines.single.endsAt, DateTime(2026, 8, 22));
    });

    test('a period across a month end lands on a real date', () {
      final cart = SaleCart()..add(_product(rental: true));
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 30), DateTime(2026, 9, 2));

      expect(cart.lines.single.days, 3);
      expect(cart.lines.single.endsAt, DateTime(2026, 9, 2));
    });

    test('out and back the same day is charged as one', () {
      // Zero days would zero the money, and nobody hires chairs for nothing.
      final cart = SaleCart()..add(_product(price: 10, rental: true), qty: 5);
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 19));

      expect(cart.lines.single.days, 1);
      expect(cart.total, 50);
    });

    test('the time of day is discarded, so a period is whole days', () {
      final cart = SaleCart()..add(_product(rental: true));
      cart.setPeriod(cart.lines.single, DateTime(2026, 8, 19, 23, 59),
          DateTime(2026, 8, 22, 0, 1));

      expect(cart.lines.single.days, 3, reason: 'not 2, and not 4');
      expect(cart.lines.single.startsAt, DateTime(2026, 8, 19));
    });

    test('a second rental inherits the period already agreed', () {
      // Chairs and tables go out for the same weekend. Picking the dates once
      // per product would be the same tapping this feature exists to remove.
      final cart = SaleCart()..add(_product(id: 'chair', rental: true));
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 22));

      cart.add(_product(id: 'table', price: 20, rental: true));
      final table = cart.lines.last;

      expect(table.days, 3);
      expect(table.startsAt, DateTime(2026, 8, 19));
    });

    test('something sold outright takes no period from the cart', () {
      final cart = SaleCart()..add(_product(id: 'chair', rental: true));
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 22));

      cart.add(_product(id: 'ice', price: 60));
      final ice = cart.lines.last;

      expect(ice.days, 1);
      expect(ice.startsAt, isNull);
      expect(cart.toSaleLines().last.startsAt, isNull);
    });

    test('the period survives a quantity change', () {
      final cart = SaleCart()
        ..add(_product(price: 10, stock: 50, rental: true), qty: 5);
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 23));
      cart.setQuantity(cart.lines.single, 10);

      expect(cart.lines.single.days, 4);
      expect(cart.total, 400);
    });

    test('the drafts handed to the repository carry the start date', () {
      final cart = SaleCart()..add(_product(rental: true), qty: 2);
      cart.setPeriod(
          cart.lines.single, DateTime(2026, 8, 19), DateTime(2026, 8, 22));

      final draft = cart.toSaleLines().single;
      expect(draft.days, 3);
      expect(draft.startsAt, DateTime(2026, 8, 19));
    });
  });

  test('clear empties everything', () {
    final cart = SaleCart()
      ..add(_product(id: 'a'))
      ..add(_product(id: 'b'))
      ..clear();

    expect(cart.isEmpty, isTrue);
    expect(cart.total, 0);
    expect(cart.itemCount, 0);
  });
}
