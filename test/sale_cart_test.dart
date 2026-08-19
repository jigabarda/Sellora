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
    final cart = SaleCart()..add(_product(trackStock: false, stock: 0), qty: 99);
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
