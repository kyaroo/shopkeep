// ARCH-3 — the typed client/UI contract.
//
// The server speaks snake_case maps; the app now speaks CatalogRow /
// CatalogPrefill. These tests pin the mapping so a renamed server field is a
// failing test rather than a silent null in the UI.
//
// Run: flutter test test/unit/catalog_row_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/models/catalog_prefill.dart';
import 'package:myhanout/models/catalog_row.dart';

void main() {
  group('CatalogRow.fromMap', () {
    test('maps the server snake_case payload', () {
      final row = CatalogRow.fromMap({
        'barcode': '6111035001673',
        'name': 'Aïn Atlas 50cl',
        'name_ar': 'ماء أطلس',
        'name_en': 'Ain Atlas Water',
        'category': 'beverage',
        'brand': 'Ain Atlas',
        'quantity_text': '50cl',
        'image_url': 'https://example.com/x.jpg',
        'origin': 'owner',
        'license': 'owned',
        'updated_at': 1794490202276,
      });

      expect(row.barcode, '6111035001673');
      expect(row.name, 'Aïn Atlas 50cl');
      expect(row.nameAr, 'ماء أطلس');
      expect(row.nameEn, 'Ain Atlas Water');
      expect(row.category, 'beverage');
      expect(row.brand, 'Ain Atlas');
      expect(row.quantityText, '50cl');
      expect(row.imageUrl, 'https://example.com/x.jpg');
      expect(row.origin, 'owner');
      expect(row.isOwner, isTrue);
      expect(row.updatedAt, 1794490202276);
    });

    test('tolerates the optional fields the source catalog omits', () {
      final row = CatalogRow.fromMap({'barcode': '1'});
      expect(row.name, isNull);
      expect(row.origin, isNull);
      expect(row.isOwner, isFalse);
      expect(row.updatedAt, 0);
    });

    test('isOwner is false for a source row', () {
      final row = CatalogRow.fromMap({'barcode': '1', 'origin': 'source:off'});
      expect(row.isOwner, isFalse);
    });
  });

  group('CatalogSearchResult.fromMap', () {
    test('carries the page envelope and typed rows', () {
      final page = CatalogSearchResult.fromMap({
        'total': 12,
        'limit': 50,
        'offset': 0,
        'products': [
          {'barcode': 'a', 'name': 'A'},
          {'barcode': 'b', 'name': 'B', 'origin': 'owner'},
        ],
      });

      expect(page.total, 12);
      expect(page.limit, 50);
      expect(page.products, hasLength(2));
      expect(page.products.first.barcode, 'a');
      expect(page.products.last.isOwner, isTrue);
    });

    test('an empty/malformed page yields an empty list, not a crash', () {
      final page = CatalogSearchResult.fromMap({});
      expect(page.total, 0);
      expect(page.products, isEmpty);
    });
  });

  group('CatalogPrefill', () {
    test('carries the fields the capture form needs', () {
      const prefill = CatalogPrefill(
        barcode: '6111035001673',
        name: 'Aïn Atlas 50cl',
        nameAr: 'ماء أطلس',
        category: 'beverage',
        origin: 'local',
      );

      expect(prefill.barcode, '6111035001673');
      expect(prefill.name, 'Aïn Atlas 50cl');
      expect(prefill.origin, 'local');
      expect(prefill.photo, isNull);
    });
  });

  group('CatalogBrowseResult', () {
    test('keeps the envelope for the browse list', () {
      const result = CatalogBrowseResult(
        total: 1,
        limit: 50,
        offset: 0,
        products: [CatalogPrefill(barcode: 'a', name: 'A')],
      );

      expect(result.total, 1);
      expect(result.products.single.name, 'A');
    });
  });
}
