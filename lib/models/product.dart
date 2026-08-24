class Product {
  final int? id;
  final String name;
  final String? barcode;
  final int priceCents; // stored as integer cents to avoid float rounding
  final int stockQty;

  Product({
    this.id,
    required this.name,
    this.barcode,
    required this.priceCents,
    required this.stockQty,
  });

  double get price => priceCents / 100.0;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'price_cents': priceCents,
        'stock_qty': stockQty,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        name: m['name'] as String,
        barcode: m['barcode'] as String?,
        priceCents: m['price_cents'] as int,
        stockQty: m['stock_qty'] as int,
      );

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    int? priceCents,
    int? stockQty,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        priceCents: priceCents ?? this.priceCents,
        stockQty: stockQty ?? this.stockQty,
      );

  bool get isLowStock => stockQty <= 0;
}
