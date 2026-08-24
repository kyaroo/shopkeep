/// Result of an external barcode lookup (e.g. Open Food Facts).
/// Only the fields we can trust from the source are mapped; the shop
/// manager always supplies price and stock themselves.
class ProductLookupResult {
  final String barcode;
  final String name;
  final String? brand;
  final String? category;
  final String? quantity;
  final String? imageUrl;

  ProductLookupResult({
    required this.barcode,
    required this.name,
    this.brand,
    this.category,
    this.quantity,
    this.imageUrl,
  });

  /// Human-readable title used to pre-fill the product form.
  String get displayName {
    final b = brand?.trim();
    if (b != null && b.isNotEmpty && !name.toLowerCase().contains(b.toLowerCase())) {
      return '$name ($b)';
    }
    return name;
  }
}
