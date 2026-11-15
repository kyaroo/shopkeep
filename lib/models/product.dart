import 'dart:typed_data';

class Product {
  final int? id;
  final String name;
  final String? barcode;
  final int priceCents; // stored as integer cents to avoid float rounding
  final int stockQty;
  final int lowStockThreshold; // alert when stockQty <= this (default 5)

  /// Catalog photo (small JPEG, <=128px). Carried from the local catalog when
  /// the product is resolved by barcode, or captured by the shopkeeper.
  final Uint8List? photo;

  /// Where [photo] came from: 'catalog' (a delta/resolve) or 'local' (the
  /// shopkeeper captured it). A catalog refresh only fills rows with no photo.
  final String photoSource;

  Product({
    this.id,
    required this.name,
    this.barcode,
    required this.priceCents,
    required this.stockQty,
    this.lowStockThreshold = 5,
    this.photo,
    this.photoSource = 'catalog',
  });

  double get price => priceCents / 100.0;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'price_cents': priceCents,
        'stock_qty': stockQty,
        'low_stock_threshold': lowStockThreshold,
        'photo': photo,
        'photo_source': photoSource,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        name: m['name'] as String,
        barcode: m['barcode'] as String?,
        priceCents: m['price_cents'] as int,
        stockQty: m['stock_qty'] as int,
        lowStockThreshold: (m['low_stock_threshold'] as int?) ?? 5,
        photo: m['photo'] as Uint8List?,
        photoSource: (m['photo_source'] as String?) ?? 'catalog',
      );

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    int? priceCents,
    int? stockQty,
    int? lowStockThreshold,
    Uint8List? photo,
    String? photoSource,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        priceCents: priceCents ?? this.priceCents,
        stockQty: stockQty ?? this.stockQty,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        photo: photo ?? this.photo,
        photoSource: photoSource ?? this.photoSource,
      );

  /// At or below the per-product threshold (includes out of stock).
  bool get isLowStock => stockQty <= lowStockThreshold;

  /// No units left (a stricter subset of low stock).
  bool get isOutOfStock => stockQty <= 0;
}
