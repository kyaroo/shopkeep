import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_lookup_result.dart';
import 'barcode_source.dart';

/// UPCitemDB — broad consumer-goods coverage (non-food friendly).
/// Uses the keyless `/prod/trial/lookup` endpoint by default; pass a key to
/// use the authenticated `/prod/v1/lookup` endpoint for higher limits.
class UpcItemDbSource implements BarcodeSource {
  static const String _trial = 'https://api.upcitemdb.com/prod/trial/lookup';
  static const String _v1 = 'https://api.upcitemdb.com/prod/v1/lookup';

  final http.Client _client;
  final String? _apiKey;

  UpcItemDbSource({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = apiKey;

  @override
  String get id => 'upcitemdb';

  @override
  Future<ProductLookupResult?> fetch(String barcode) async {
    final uri = Uri.parse(_apiKey == null ? _trial : _v1)
        .replace(queryParameters: {'upc': barcode});
    try {
      final headers = <String, String>{};
      if (_apiKey != null) headers['Authorization'] = 'Bearer $_apiKey';
      final resp = await _client
          .get(uri, headers: headers)
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
    if (data['code'] != 'OK') return null;
    final items = (data['items'] as List?) ?? [];
    if (items.isEmpty) return null;
    final item = items.first as Map<String, Object?>;
    final title = (item['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    String? str(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    String? image;
    final imgs = (item['images'] as List?) ?? [];
    if (imgs.isNotEmpty) image = str(imgs.first as String?);

    // Best-effort quantity: prefer explicit size, fall back to weight.
    final quantity = str(item['size'] as String?) ?? str(item['weight'] as String?);

    return ProductLookupResult(
      barcode: barcodeFrom(item) ?? '',
      name: title,
      brand: str(item['brand'] as String?),
      category: str(item['category'] as String?),
      quantity: quantity,
      imageUrl: image,
    );
  }

  static String? barcodeFrom(Map<String, Object?> item) {
    final v = item['upc'] ?? item['code'] ?? item['ean'];
    return v?.toString();
  }
}
