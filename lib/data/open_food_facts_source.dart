import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_lookup_result.dart';
import 'barcode_source.dart';

/// Open Food Facts — free, no API key, strong for food & grocery.
class OpenFoodFactsSource implements BarcodeSource {
  static const String _base = 'https://world.openfoodfacts.org/api/v2/product';

  final http.Client _client;

  OpenFoodFactsSource({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get id => 'openfoodfacts';

  @override
  Future<ProductLookupResult?> fetch(String barcode) async {
    final uri = Uri.parse('$_base/${Uri.encodeComponent(barcode)}.json');
    try {
      final resp = await _client
          .get(uri, headers: {'User-Agent': 'myhanout/0.1 (shop app)'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      return parse(resp.body);
    } on Exception {
      return null;
    }
  }

  /// Pure parser (unit-testable, no network).
  static ProductLookupResult? parse(String jsonBody) {
    final Map<String, Object?> data;
    try {
      data = jsonDecode(jsonBody) as Map<String, Object?>;
    } on FormatException {
      return null;
    }
    if (data['status'] != 1) return null;
    final product = (data['product'] as Map<String, Object?>?) ?? {};
    final name = (product['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    String? str(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return ProductLookupResult(
      barcode: (product['code'] as String?)?.trim() ?? '',
      name: name,
      brand: str(product['brands'] as String?),
      category: str(product['categories'] as String?),
      quantity: str(product['quantity'] as String?),
      imageUrl: str(product['image_front_url'] as String?),
    );
  }
}
