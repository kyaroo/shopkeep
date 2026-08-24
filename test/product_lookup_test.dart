import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper/data/product_lookup.dart';

void main() {
  group('ProductLookup.parse', () {
    test('maps a real OFF payload', () {
      const json = '''
      {
        "status": 1,
        "product": {
          "code": "6111243860383",
          "product_name": "ice POMME 1.5l",
          "brands": "ice",
          "categories": "Sodas, Jus de fruits",
          "quantity": "1.5 L",
          "image_front_url": "https://images.openfoodfacts.org/x.jpg"
        }
      }''';
      final r = ProductLookup.parse(json);
      expect(r, isNotNull);
      expect(r!.barcode, '6111243860383');
      expect(r.name, 'ice POMME 1.5l');
      expect(r.brand, 'ice');
      expect(r.quantity, '1.5 L');
      expect(r.imageUrl, contains('openfoodfacts'));
      // displayName appends brand when not already in name (case-insensitive)
      expect(r.displayName, 'ice POMME 1.5l');
    });

    test('returns null when status != 1', () {
      expect(ProductLookup.parse('{"status":0,"product":{}}'), isNull);
    });

    test('returns null when product_name missing', () {
      const json = '{"status":1,"product":{"code":"123","brands":"x"}}';
      expect(ProductLookup.parse(json), isNull);
    });

    test('returns null on invalid JSON', () {
      expect(ProductLookup.parse('not json'), isNull);
    });

    test('displayName omits brand when name already contains it', () {
      const json = '''
      {"status":1,"product":{"product_name":"ice Cola","brands":"ice"}}''';
      final r = ProductLookup.parse(json)!;
      expect(r.displayName, 'ice Cola');
    });
  });
}
