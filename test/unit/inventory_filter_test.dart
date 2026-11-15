// G2 — the inventory 'Ajoutés localement' filter (pure logic).
//
// Precedence: the provider's SQL search narrows the rows first (and drives
// totalProducts); the chip is an in-memory predicate over the loaded page.
// The chips are mutually exclusive views, so lowStock and local are
// alternatives rather than stacked conditions.
//
// Run: flutter test test/unit/inventory_filter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/models/inventory_filter.dart';
import 'package:myhanout/models/product.dart';

Product _product(
  String name, {
  String source = 'catalog',
  int stockQty = 10,
  int threshold = 5,
  String photoSource = 'catalog',
}) =>
    Product(
      name: name,
      priceCents: 100,
      stockQty: stockQty,
      lowStockThreshold: threshold,
      source: source,
      photoSource: photoSource,
    );

void main() {
  group('InventoryFilter', () {
    test('should keep every row in the all view', () {
      final rows = [
        _product('Catalogue'),
        _product('Local', source: 'local'),
        _product('Local rupture', source: 'local', stockQty: 0),
      ];

      final shown = InventoryFilter.all.apply(rows);

      expect(shown, hasLength(3));
      expect(shown.map((p) => p.name),
          containsAll(['Catalogue', 'Local', 'Local rupture']));
    });

    test('should keep only rows at or below their threshold in lowStock', () {
      final rows = [
        _product('Sain', stockQty: 10),
        _product('Au seuil', stockQty: 5),
        _product('Rupture', stockQty: 0),
      ];

      final names = InventoryFilter.lowStock.apply(rows).map((p) => p.name);

      expect(names, containsAll(['Au seuil', 'Rupture']));
      expect(names, isNot(contains('Sain')));
    });

    test('should keep only hand-typed rows in the local view', () {
      final rows = [
        _product('Catalogue'),
        _product('Catalogue bas', stockQty: 1),
        _product('Local', source: 'local'),
      ];

      final names = InventoryFilter.local.apply(rows).map((p) => p.name);

      expect(names, ['Local']);
    });

    test('should not confuse a locally captured photo with a local product', () {
      final rows = [
        // photoSource tracks the PHOTO, not the product: this row still came
        // from the catalog and must not be offered the recovery affordance.
        _product('Catalogue photo locale', photoSource: 'local'),
        _product('Local', source: 'local'),
      ];

      final names = InventoryFilter.local.apply(rows).map((p) => p.name);

      expect(names, ['Local']);
    });

    test('should apply after search (search narrows first, chip second)', () {
      final rows = [
        _product('Couscous catalogue'),
        _product('Couscous local', source: 'local'),
        _product('Thé local', source: 'local'),
      ];
      // What the provider hands the screen after `search: 'couscous'`.
      final searched = rows
          .where((p) => p.name.toLowerCase().contains('couscous'))
          .toList();

      final names = InventoryFilter.local.apply(searched).map((p) => p.name);

      expect(names, ['Couscous local']);
    });

    test('should treat lowStock and local as alternative views, not stacked', () {
      final rows = [
        _product('Local bas', source: 'local', stockQty: 1),
        _product('Local plein', source: 'local', stockQty: 9),
      ];

      expect(InventoryFilter.local.apply(rows), hasLength(2));
      expect(
          InventoryFilter.lowStock.apply(rows).map((p) => p.name), ['Local bas']);
    });
  });
}
