import '../models/product_lookup_result.dart';

/// A pluggable barcode database. Implementations map their own JSON shape
/// into the app-neutral [ProductLookupResult].
abstract class BarcodeSource {
  /// Human-readable id, used for logging/debugging.
  String get id;

  /// Returns a mapped result, or null if the product is unknown / request fails.
  Future<ProductLookupResult?> fetch(String barcode);
}
