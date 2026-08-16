import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/models/entities.dart';
import 'package:sellora_mobile/data/quick_entry/quick_command.dart';
import 'package:sellora_mobile/data/quick_entry/quick_entry_parser.dart';

const parser = QuickEntryParser();

final products = [
  _product('prd_1', 'Purified 5-Gallon Refill', 25.0),
  _product('prd_2', 'Distilled 5-Gallon Refill', 30.0),
  _product('prd_3', 'Alkaline 1L Bottle', 45.0),
  _product('prd_4', 'Crushed Ice Bag', 60.0),
  _product('prd_5', 'Ice Tube Sack', 120.0),
  _product('prd_6', 'Home Delivery', 50.0),
  _product('prd_8', 'Old Blue Container', 250.0, active: false),
];

final customers = [
  _customer('cus_1', 'Aling Nena'),
  _customer('cus_2', 'Mang Tonyo'),
  _customer('cus_3', 'Sari-Sari ni Ate Baby'),
];

QuickCommand run(String input) =>
    parser.parse(input, products: products, customers: customers);

void main() {
  group('sales', () {
    test('quantity and product from a plain phrase', () {
      final c = run('2 purified refill') as RecordSaleCommand;
      expect(c.product.id, 'prd_1');
      expect(c.quantity, 2);
      expect(c.customer, isNull);
      expect(c.total, 50.0);
    });

    test('no number said means one, not none', () {
      final c = run('alkaline bottle') as RecordSaleCommand;
      expect(c.product.id, 'prd_3');
      expect(c.quantity, 1);
    });

    test('attaches a customer after kay', () {
      final c = run('2 purified refill kay aling nena') as RecordSaleCommand;
      expect(c.product.id, 'prd_1');
      expect(c.quantity, 2);
      expect(c.customer?.id, 'cus_1');
    });

    test('handles a Tagalog numeral with its linker', () {
      // "dalawa" becomes "dalawang" before a noun, and users type what they say.
      final c = run('dalawang ice tube') as RecordSaleCommand;
      expect(c.product.id, 'prd_5');
      expect(c.quantity, 2);
    });

    test('handles an English numeral word', () {
      final c = run('three crushed ice') as RecordSaleCommand;
      expect(c.product.id, 'prd_4');
      expect(c.quantity, 3);
    });

    test('tolerates filler and unit words', () {
      final c = run('2 pcs ng purified refill po') as RecordSaleCommand;
      expect(c.product.id, 'prd_1');
      expect(c.quantity, 2);
    });

    test('will not sell an inactive product', () {
      // It cannot be sold on the form either; matching it would offer the user
      // something the next screen refuses.
      expect(run('old blue container'), isA<UnparsedCommand>());
    });
  });

  group('declines rather than guessing', () {
    test('an ambiguous product name matches nothing', () {
      // "refill" fits Purified and Distilled equally. Picking one is how the
      // wrong product reaches a receipt.
      expect(run('2 refill'), isA<UnparsedCommand>());
    });

    test('an unknown product matches nothing', () {
      expect(run('3 motor oil'), isA<UnparsedCommand>());
    });

    test('empty input matches nothing', () {
      expect(run('   '), isA<UnparsedCommand>());
    });

    test('a bare number matches nothing', () {
      expect(run('500'), isA<UnparsedCommand>());
    });
  });

  group('expenses', () {
    test('maps a spoken word onto a fixed category', () {
      final c = run('500 gas') as AddExpenseCommand;
      expect(c.amount, 500);
      expect(c.category, 'Transport');
    });

    test('understands Tagalog category words', () {
      final c = run('bayad kuryente 3400') as AddExpenseCommand;
      expect(c.amount, 3400);
      expect(c.category, 'Utilities');
    });

    test('keeps the utterance as the note', () {
      final c = run('8000 upa') as AddExpenseCommand;
      expect(c.category, 'Rent');
      expect(c.note, '8000 upa');
    });

    test('accepts a decimal amount', () {
      final c = run('sweldo 5250.50') as AddExpenseCommand;
      expect(c.amount, 5250.5);
      expect(c.category, 'Payroll');
    });

    test('a category with no amount is not an expense', () {
      // There is no expense without a number, so the empty form is the honest
      // answer rather than one with a zero in it.
      expect(run('gas'), isA<UnparsedCommand>());
    });
  });

  group('the customer clause does not steal tokens', () {
    test('"for" before a non-customer leaves the phrase intact', () {
      // The naive split would consume "gas" and lose the category entirely.
      final c = run('500 for gas') as AddExpenseCommand;
      expect(c.category, 'Transport');
      expect(c.amount, 500);
    });

    test('"for" before a real customer still splits', () {
      final c = run('2 purified refill for mang tonyo') as RecordSaleCommand;
      expect(c.customer?.id, 'cus_2');
      expect(c.product.id, 'prd_1');
    });

    test('a customer clause does not swallow the product', () {
      final c = run('ice tube sack kay ate baby') as RecordSaleCommand;
      expect(c.product.id, 'prd_5');
      expect(c.customer?.id, 'cus_3');
    });
  });

  test('a sale outranks an expense when both could fit', () {
    // "Home Delivery" is a product; "delivery" is also a Transport synonym.
    // Sales are far more frequent, and the mistake is visible on the form.
    final c = run('2 home delivery') as RecordSaleCommand;
    expect(c.product.id, 'prd_6');
    expect(c.quantity, 2);
  });
}

Product _product(String id, String name, double price, {bool active = true}) =>
    Product(
      id: id,
      businessId: 'biz_1',
      categoryId: null,
      name: name,
      description: '',
      sku: '',
      unit: 'pcs',
      price: price,
      stock: 50,
      trackStock: true,
      active: active,
      createdAt: DateTime(2026, 1, 1),
    );

Customer _customer(String id, String name) => Customer(
      id: id,
      businessId: 'biz_1',
      name: name,
      phone: '',
      email: '',
      notes: '',
      createdAt: DateTime(2026, 1, 1),
    );
