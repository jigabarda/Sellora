class Category {
  const Category({
    required this.id,
    required this.businessId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String name;
  final DateTime createdAt;

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        name: m['name']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class Product {
  const Product({
    required this.id,
    required this.businessId,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.sku,
    required this.unit,
    required this.price,
    required this.stock,
    required this.trackStock,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String? categoryId;
  final String name;
  final String description;
  final String sku;

  /// Unit of measure shown next to quantities: pcs, gallon, liter, kg...
  final String unit;
  final double price;

  /// Meaningless when [trackStock] is false; treat the product as unlimited.
  final int stock;

  /// Services and made-to-order items have no inventory. Sales of an untracked
  /// product skip the availability check, the decrement, and the ledger row.
  final bool trackStock;
  final bool active;
  final DateTime createdAt;

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        categoryId: m['category_id'] as String?,
        name: m['name']! as String,
        description: (m['description'] as String?) ?? '',
        sku: (m['sku'] as String?) ?? '',
        unit: (m['unit'] as String?) ?? 'pcs',
        price: (m['price'] as num).toDouble(),
        stock: (m['stock'] as num).toInt(),
        trackStock: ((m['track_stock'] as num?) ?? 1).toInt() == 1,
        active: ((m['active'] as num?) ?? 1).toInt() == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'sku': sku,
        'unit': unit,
        'price': price,
        'stock': stock,
        'track_stock': trackStock ? 1 : 0,
        'active': active ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class Customer {
  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.email,
    required this.notes,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String name;
  final String phone;
  final String email;
  final String notes;
  final DateTime createdAt;

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        name: m['name']! as String,
        phone: (m['phone'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'phone': phone,
        'email': email,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class SaleLine {
  const SaleLine({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  final String id;
  final String saleId;
  final String productId;
  final String name;
  final int qty;
  final double unitPrice;

  factory SaleLine.fromMap(Map<String, Object?> m) => SaleLine(
        id: m['id']! as String,
        saleId: m['sale_id']! as String,
        productId: m['product_id']! as String,
        name: m['name']! as String,
        qty: (m['qty'] as num).toInt(),
        unitPrice: (m['unit_price'] as num).toDouble(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'name': name,
        'qty': qty,
        'unit_price': unitPrice,
      };
}

class Sale {
  const Sale({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.total,
    required this.createdAt,
    this.lines = const [],
  });

  final String id;
  final String businessId;
  final String? customerId;
  final double total;
  final DateTime createdAt;
  final List<SaleLine> lines;

  factory Sale.fromMap(Map<String, Object?> m,
          {List<SaleLine> lines = const []}) =>
      Sale(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        customerId: m['customer_id'] as String?,
        total: (m['total'] as num).toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
        lines: lines,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'customer_id': customerId,
        'total': total,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class StockLedgerEntry {
  const StockLedgerEntry({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.delta,
    required this.reason,
    required this.refId,
    required this.note,
    required this.at,
  });

  final String id;
  final String businessId;
  final String productId;
  final int delta;
  final String reason;
  final String? refId;
  final String note;
  final DateTime at;

  factory StockLedgerEntry.fromMap(Map<String, Object?> m) => StockLedgerEntry(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        productId: m['product_id']! as String,
        delta: (m['delta'] as num).toInt(),
        reason: m['reason']! as String,
        refId: m['ref_id'] as String?,
        note: (m['note'] as String?) ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(m['at']! as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'product_id': productId,
        'delta': delta,
        'reason': reason,
        'ref_id': refId,
        'note': note,
        'at': at.millisecondsSinceEpoch,
      };
}

class Expense {
  const Expense({
    required this.id,
    required this.businessId,
    required this.amount,
    required this.category,
    required this.note,
    required this.at,
  });

  final String id;
  final String businessId;
  final double amount;
  final String category;
  final String note;
  final DateTime at;

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        amount: (m['amount'] as num).toDouble(),
        category: m['category']! as String,
        note: (m['note'] as String?) ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(m['at']! as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'amount': amount,
        'category': category,
        'note': note,
        'at': at.millisecondsSinceEpoch,
      };
}

class Refund {
  const Refund({
    required this.id,
    required this.businessId,
    required this.saleId,
    required this.amount,
    required this.note,
    required this.restock,
    required this.at,
  });

  final String id;
  final String businessId;
  final String? saleId;
  final double amount;
  final String note;
  final bool restock;
  final DateTime at;

  factory Refund.fromMap(Map<String, Object?> m) => Refund(
        id: m['id']! as String,
        businessId: m['business_id']! as String,
        saleId: m['sale_id'] as String?,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        restock: ((m['restock'] as num?) ?? 0).toInt() == 1,
        at: DateTime.fromMillisecondsSinceEpoch(m['at']! as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'sale_id': saleId,
        'amount': amount,
        'note': note,
        'restock': restock ? 1 : 0,
        'at': at.millisecondsSinceEpoch,
      };
}
