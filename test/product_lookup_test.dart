import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/open_food_facts_source.dart';
import 'package:myhanout/data/upc_item_db_source.dart';

void main() {
  group('OpenFoodFactsSource.parse', () {
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
      final r = OpenFoodFactsSource.parse(json);
      expect(r, isNotNull);
      expect(r!.barcode, '6111243860383');
      expect(r.name, 'ice POMME 1.5l');
      expect(r.brand, 'ice');
      expect(r.quantity, '1.5 L');
      // brand "ice" is contained in the name -> not appended
      expect(r.displayName, 'ice POMME 1.5l');
    });

    test('returns null when status != 1', () {
      expect(OpenFoodFactsSource.parse('{"status":0,"product":{}}'), isNull);
    });

    test('returns null when product_name missing', () {
      const json = '{"status":1,"product":{"code":"123","brands":"x"}}';
      expect(OpenFoodFactsSource.parse(json), isNull);
    });

    test('returns null on invalid JSON', () {
      expect(OpenFoodFactsSource.parse('not json'), isNull);
    });
  });

  group('UpcItemDbSource.parse', () {
    test('maps a trial payload', () {
      const json = '''
      {
        "code": "OK",
        "total": 1,
        "items": [{
          "upc": "0123456789012",
          "title": "BRAT & SAUSAGE ROLLS",
          "brand": "Rica Produce",
          "category": "Home & Garden > Lighting",
          "size": "12 oz",
          "images": ["https://img.example.com/a.png"]
        }]
      }''';
      final r = UpcItemDbSource.parse(json);
      expect(r, isNotNull);
      expect(r!.barcode, '0123456789012');
      expect(r.name, 'BRAT & SAUSAGE ROLLS');
      expect(r.brand, 'Rica Produce');
      expect(r.category, 'Home & Garden > Lighting');
      expect(r.quantity, '12 oz');
      expect(r.imageUrl, 'https://img.example.com/a.png');
    });

    test('returns null when code != OK', () {
      expect(UpcItemDbSource.parse('{"code":"ERROR"}'), isNull);
    });

    test('returns null when items empty (e.g. unknown barcode)', () {
      const json = '{"code":"OK","total":0,"items":[]}';
      expect(UpcItemDbSource.parse(json), isNull);
    });

    test('returns null on invalid JSON', () {
      expect(UpcItemDbSource.parse('nope'), isNull);
    });
  });
}
