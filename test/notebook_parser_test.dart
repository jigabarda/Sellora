import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/models/entities.dart';
import 'package:sellora_mobile/data/notebook/notebook_line.dart';
import 'package:sellora_mobile/data/notebook/notebook_parser.dart';

const parser = NotebookParser();

// Deliberately the same catalogue as the Quick Entry tests. The two refills at
// ₱25 and ₱30 are the pair Quick Entry cannot separate from text alone, which
// is exactly what the arithmetic here is supposed to settle.
final products = [
  _product('prd_1', 'Purified 5-Gallon Refill', 25.0),
  _product('prd_2', 'Distilled 5-Gallon Refill', 30.0),
  _product('prd_3', 'Alkaline 1L Bottle', 45.0),
  _product('prd_4', 'Crushed Ice Bag', 60.0),
  _product('prd_5', 'Ice Tube Sack', 120.0),
  _product('prd_8', 'Old Blue Container', 250.0, active: false),
];

final customers = [
  _customer('cus_1', 'Aling Nena'),
  _customer('cus_2', 'Mang Tonyo'),
  _customer('cus_3', 'Sari-Sari ni Ate Baby'),
];

NotebookLine one(String text) {
  final page = parser.parse(text, products: products, customers: customers);
  expect(page.lines, hasLength(1), reason: 'fixture should be a single line');
  return page.lines.single;
}

void main() {
  group('a line that adds up', () {
    test('name, quantity, item and amount', () {
      final l = one('Nena 2 purified refill 50');
      expect(l.status, LineStatus.reconciled);
      expect(l.product?.id, 'prd_1');
      expect(l.customer?.id, 'cus_1');
      expect(l.quantity, 2);
      expect(l.writtenAmount, 50.0);
      expect(l.total, 50.0);
      expect(l.isRecordable, isTrue);
    });

    test('no customer is not a failure', () {
      final l = one('3 alkaline bottle 135');
      expect(l.status, LineStatus.reconciled);
      expect(l.customer, isNull);
      expect(l.quantity, 3);
    });

    test('the raw text is kept verbatim for the owner to compare against', () {
      // They are holding the notebook. A cleaned-up rendering they cannot match
      // against the paper is worse than none.
      final l = one('  Nena 2 purified refill 50  ');
      expect(l.raw, '  Nena 2 purified refill 50  ');
    });
  });

  group('arithmetic as the tie-breaker', () {
    // The headline claim of the design: the amount on the page separates two
    // products that the text alone cannot.
    test('the amount picks the cheaper refill', () {
      final l = one('2 refill 50');
      expect(l.status, LineStatus.reconciled);
      expect(l.product?.id, 'prd_1');
      expect(l.quantity, 2);
    });

    test('the amount picks the dearer refill', () {
      final l = one('2 refill 60');
      expect(l.status, LineStatus.reconciled);
      expect(l.product?.id, 'prd_2');
      expect(l.quantity, 2);
    });

    test('an ambiguous line with no amount is held back, not guessed', () {
      // Without the checksum this is the Quick Entry tie case, and the answer
      // has to be the same: decline.
      final l = one('2 refill');
      expect(l.status, isNot(LineStatus.reconciled));
      expect(l.isRecordable, isFalse);
    });
  });

  group('recovering what the recogniser lost', () {
    test('a dropped quantity is divided back out of the amount', () {
      final l = one('purified refill 75');
      expect(l.status, LineStatus.reconciled);
      expect(l.product?.id, 'prd_1');
      expect(l.quantity, 3);
    });

    test('a mangled digit is repaired when the line then adds up', () {
      // Handwritten 50 comes back as 5O often enough to be worth repairing.
      final l = one('Nena 2 purified refill 5O');
      expect(l.status, LineStatus.reconciled);
      expect(l.quantity, 2);
      expect(l.writtenAmount, 50.0);
    });

    test('a word made only of confusable letters is left alone', () {
      // "SO" must stay a word. Only tokens already containing a real digit are
      // repaired, or the map would wreck product names.
      final page = parser.parse('so purified refill 50',
          products: products, customers: customers);
      final l = page.lines.single;
      expect(l.product?.id, 'prd_1');
      expect(l.quantity, 2, reason: '50 / 25, not a quantity read out of "so"');
    });
  });

  group('lines that do not add up', () {
    test('a mismatch is flagged and priced from the catalogue, not the page',
        () {
      // Honouring ₱45 would bake a reading error into the books.
      final l = one('Nena 2 purified refill 45');
      expect(l.status, LineStatus.needsReview);
      expect(l.quantity, 2);
      expect(l.writtenAmount, 45.0);
      expect(l.total, 50.0);
      expect(l.note, contains('45'));
      expect(l.note, contains('50'));
    });

    test('a line with no amount says so', () {
      final l = one('4 alkaline bottle');
      expect(l.status, LineStatus.needsReview);
      expect(l.quantity, 4);
      expect(l.writtenAmount, isNull);
      expect(l.note, contains('No amount'));
    });

    test('needs-review lines are still recordable, deliberately', () {
      // The preview leaves them unticked; the owner may still opt in.
      expect(one('4 alkaline bottle').isRecordable, isTrue);
    });
  });

  group('lines that are not sales', () {
    test('a date header is skipped', () {
      final l = one('Aug 16');
      expect(l.status, LineStatus.ignored);
    });

    test('a running total is skipped, not read as a huge quantity', () {
      final l = one('Total 1250');
      expect(l.status, LineStatus.ignored);
    });

    test('column titles are skipped', () {
      expect(one('Name Item Qty Amount').status, LineStatus.ignored);
    });

    test('an unrecognisable line is reported rather than dropped', () {
      final l = one('qwerty zxcvb');
      expect(l.status, LineStatus.unreadable);
      expect(l.isRecordable, isFalse);
    });

    test('an inactive product cannot be sold off a page either', () {
      final l = one('1 old blue container 250');
      expect(l.status, LineStatus.unreadable);
    });
  });

  group('customer splitting', () {
    test('a name at the front does not swallow the product', () {
      final l = one('Ate Baby 1 ice tube sack 120');
      expect(l.product?.id, 'prd_5');
      expect(l.customer?.id, 'cus_3');
      expect(l.status, LineStatus.reconciled);
    });

    test('a two-word name is taken whole', () {
      final l = one('Mang Tonyo 1 crushed ice bag 60');
      expect(l.customer?.id, 'cus_2');
      expect(l.product?.id, 'prd_4');
    });

    test('a line with no name keeps all its words for the product', () {
      final l = one('1 crushed ice bag 60');
      expect(l.customer, isNull);
      expect(l.product?.id, 'prd_4');
    });
  });

  group('the page as a whole', () {
    test('reads a realistic page and counts what proved itself', () {
      final page = parser.parse(
        '''
Aug 16
Nena 2 purified refill 50
Mang Tonyo 1 ice tube sack 120
Ate Baby 3 purified refill 75
4 alkaline bottle
Total 245
''',
        products: products,
        customers: customers,
      );

      // Blank lines are not emitted; everything else is, including the parts
      // that are not transactions.
      expect(page.lines, hasLength(6));
      expect(page.reconciledCount, 3);
      expect(page.needsReviewCount, 1);
      expect(page.lines.where((l) => l.status == LineStatus.ignored), hasLength(2));
      expect(page.recordable, hasLength(4));
      expect(page.isBlank, isFalse);
    });

    test('a photo of nothing is blank rather than wrong', () {
      final page = parser.parse('Aug 16\nTotal 245',
          products: products, customers: customers);
      expect(page.isBlank, isTrue);
      expect(page.recordable, isEmpty);
    });

    test('empty recognised text produces no lines at all', () {
      final page =
          parser.parse('', products: products, customers: customers);
      expect(page.lines, isEmpty);
      expect(page.isBlank, isTrue);
    });
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
