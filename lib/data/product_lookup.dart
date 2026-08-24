import '../models/product_lookup_result.dart';
import 'barcode_source.dart';
import 'open_food_facts_source.dart';
import 'upc_item_db_source.dart';

/// Orchestrates barcode sources in priority order. Offline-first: callers
/// should only use this after a local SQLite miss. Returns the first
/// non-null result, or null if every source misses / fails.
class ProductLookup {
  final List<BarcodeSource> _sources;

  ProductLookup({List<BarcodeSource>? sources, String? upcItemDbKey})
      : _sources = sources ??
            [
              OpenFoodFactsSource(),
              UpcItemDbSource(apiKey: upcItemDbKey),
            ];

  Future<ProductLookupResult?> fetch(String barcode) async {
    for (final source in _sources) {
      final result = await source.fetch(barcode);
      if (result != null) return result;
    }
    return null;
  }
}
