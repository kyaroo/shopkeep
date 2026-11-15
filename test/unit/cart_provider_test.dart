// View-state providers: CartProvider.findByBarcode + SalesProvider.
//
// Both are exercised against the real shop database (sqflite_common_ffi) —
// the point is that the provider, not a screen, is what touches the DB.
//
// Run: flutter test test/unit/cart_provider_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/product.dart';
import 'package:myhanout/providers/cart_provider.dart';
import 'package:myhanout/providers/sales_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shop = 'prov-shop';

Future<void> _cleanUp() async {
  await Db.closeShop(_shop);
  final f = await Db.shopDbFile(_shop);
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('${f.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _cleanUp();
  });

  tearDown(() async {
    await _cleanUp();
  });

  group('CartProvider.findByBarcode', () {
    test('finds a stored product by barcode', () async {
      final cart = CartProvider(_shop);
      final db = await Db.open(_shop);
      await db.insertProduct(
        _shop,
        Product(
            name: 'Couscous', barcode: '6111000000456', priceCents: 1200, stockQty: 5),
      );

      final found = await cart.findByBarcode('6111000000456');
      expect(found, isNotNull);
      expect(found!.name, 'Couscous');
      expect(found.priceCents, 1200);
    });

    test('returns null for an unknown barcode', () async {
      final cart = CartProvider(_shop);
      expect(await cart.findByBarcode('0000000000000'), isNull);
    });
  });

  group('SalesProvider', () {
    test('loads the day sales and derives stats', () async {
      final db = await Db.open(_shop);
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      await db.insertSale(_shop, 3500, [
        {'productName': 'Couscous', 'unitPriceCents': 1200, 'quantity': 1, 'lineTotalCents': 1200},
        {'productName': 'Thé', 'unitPriceCents': 2300, 'quantity': 1, 'lineTotalCents': 2300},
      ]);

      final provider = SalesProvider(
        _shop,
        start: start,
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
      await provider.ready;

      expect(provider.loading, isFalse);
      expect(provider.sales, hasLength(1));
      expect(provider.stats['saleCount'], 1);
      expect(provider.stats['totalItems'], 2);
      expect(provider.stats['totalRevenueCents'], 3500);
    });

    test('setRange narrows the window and reloads', () async {
      final db = await Db.open(_shop);
      final now = DateTime.now();
      await db.insertSale(_shop, 1000, [
        {'productName': 'X', 'unitPriceCents': 1000, 'quantity': 1, 'lineTotalCents': 1000},
      ]);

      final emptyDay = DateTime(2000, 1, 1);
      final provider = SalesProvider(
        _shop,
        start: emptyDay,
        end: DateTime(2000, 1, 1, 23, 59, 59),
      );
      await provider.ready;
      expect(provider.sales, isEmpty);

      final today = DateTime(now.year, now.month, now.day);
      await provider.setRange(today, today);
      expect(provider.sales, hasLength(1));
    });
  });
}
