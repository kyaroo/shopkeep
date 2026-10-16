class SaleItem {
  final int? id;
  final int saleId;
  final String productName;
  final int unitPriceCents;
  final int quantity;
  final int lineTotalCents;

  SaleItem({
    this.id,
    required this.saleId,
    required this.productName,
    required this.unitPriceCents,
    required this.quantity,
    required this.lineTotalCents,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_name': productName,
        'unit_price_cents': unitPriceCents,
        'quantity': quantity,
        'line_total_cents': lineTotalCents,
      };

  factory SaleItem.fromMap(Map<String, Object?> m) => SaleItem(
        id: m['id'] as int?,
        saleId: m['sale_id'] as int,
        productName: m['product_name'] as String,
        unitPriceCents: m['unit_price_cents'] as int,
        quantity: m['quantity'] as int,
        lineTotalCents: m['line_total_cents'] as int,
      );
}

class Sale {
  final int? id;
  final int createdAt; // unix epoch ms
  final int totalCents;
  final int itemCount;
  final List<SaleItem> items;

  Sale({
    this.id,
    required this.createdAt,
    required this.totalCents,
    required this.itemCount,
    this.items = const [],
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(createdAt);

  Map<String, Object?> toMap() => {
        'id': id,
        'created_at': createdAt,
        'total_cents': totalCents,
        'item_count': itemCount,
      };

  factory Sale.fromMap(Map<String, Object?> m, {List<SaleItem> items = const []}) =>
      Sale(
        id: m['id'] as int?,
        createdAt: m['created_at'] as int,
        totalCents: m['total_cents'] as int,
        itemCount: m['item_count'] as int,
        items: items,
      );
}
