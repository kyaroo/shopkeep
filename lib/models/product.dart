class Product {
  final int? id;
  final String name;
  final String? barcode;
  final int priceCents; // stored as integer cents to avoid float rounding
  final int stockQty;
  final int lowStockThreshold; // alert when stockQty <= this (default 5)

  Product({
    this.id,
    required this.name,
    this.barcode,
    required this.priceCents,
    required this.stockQty,
    this.lowStockThreshold = 5,
  });

  double get price => priceCents / 100.0;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'price_cents': priceCents,
        'stock_qty': stockQty,
        'low_stock_threshold': lowStockThreshold,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        name: m['name'] as String,
        barcode: m['barcode'] as String?,
        priceCents: m['price_cents'] as int,
        stockQty: m['stock_qty'] as int,
        lowStockThreshold: (m['low_stock_threshold'] as int?) ?? 5,
      );

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    int? priceCents,
    int? stockQty,
    int? lowStockThreshold,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        priceCents: priceCents ?? this.priceCents,
        stockQty: stockQty ?? this.stockQty,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      );

  /// At or below the per-product threshold (includes out of stock).
  bool get isLowStock => stockQty <= lowStockThreshold;

  /// No units left (a stricter subset of low stock).
  bool get isOutOfStock => stockQty <= 0;
}
