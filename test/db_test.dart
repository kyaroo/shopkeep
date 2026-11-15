import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/product.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('products table has low_stock_threshold column', () async {
    const shopKey = 'test-shop';
    final db = await Db.open(shopKey);
    await db.database;
    final cols = await db.rawQuery('PRAGMA table_info(products)');
    final names = cols.map((c) => c['name']).toList();
    expect(names, contains('low_stock_threshold'));
  });

  test('insert/read preserves threshold', () async {
    const shopKey = 'test-shop-2';
    final db = await Db.open(shopKey);
    final id = await db.insertProduct(
      shopKey,
      Product(name: 'X', priceCents: 100, stockQty: 2, lowStockThreshold: 4),
    );
    final rows = await db.getProducts(shopKey);
    final p = rows.firstWhere((r) => r.id == id);
    expect(p.lowStockThreshold, 4);
  });
}
