// CAT3b — product provenance (`products.source`: 'catalog' vs 'local').
//
// Backend-only flag: no UI, no chip. A row resolved from the local catalog is
// 'catalog'; a row typed by hand is 'local'. Existing rows default to
// 'catalog' so an upgrade never relabels a shop's history.
//
// Run: flutter test test/unit/product_source_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _deleteShopFiles(String shop) async {
  final f = await Db.shopDbFile(shop);
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('${f.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

/// Creates a pre-CAT3b database at the shop path: `products` with photo and
/// photo_source but no `source`, at [version] (6 = what older runs left).
Future<void> _seedLegacyDb(String shop, {int version = 4}) async {
  final path = await Db.shopDbPath(shop);
  final dir = Directory(path).parent;
  await dir.create(recursive: true);
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT,
            price_cents INTEGER NOT NULL,
            stock_qty INTEGER NOT NULL DEFAULT 0,
            low_stock_threshold INTEGER NOT NULL DEFAULT 5,
            photo BLOB,
            photo_source TEXT NOT NULL DEFAULT 'catalog'
          )
        ''');
        // A real v4+ shop DB already had the audit trail; insertProduct logs to it.
        await db.execute('''
          CREATE TABLE audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_key TEXT NOT NULL,
            action TEXT NOT NULL,
            table_name TEXT NOT NULL,
            record_id INTEGER NOT NULL,
            old_values TEXT,
            new_values TEXT,
            changed_at INTEGER NOT NULL,
            changed_by TEXT NOT NULL
          )
        ''');
      },
    ),
  );
  await db.close();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await Db.closeShop('src-fresh');
    await Db.closeShop('src-legacy');
    await _deleteShopFiles('src-fresh');
    await _deleteShopFiles('src-legacy');
  });

  test('fresh database has the source column defaulting to catalog', () async {
    final db = await Db.open('src-fresh');
    final cols = await db.rawQuery('PRAGMA table_info(products)');
    final names = cols.map((c) => c['name']).toList();
    expect(names, contains('source'));

    final id = await db.insertProduct(
        'src-fresh', Product(name: 'X', priceCents: 100, stockQty: 1));
    final stored =
        (await db.getProducts('src-fresh')).firstWhere((p) => p.id == id);
    expect(stored.source, 'catalog');
    expect(stored.isLocal, isFalse);
  });

  test('a local addition is stored and read back as local', () async {
    final db = await Db.open('src-fresh');
    await db.insertProduct(
        'src-fresh',
        Product(
            name: 'Tapé à la main',
            priceCents: 250,
            stockQty: 3,
            source: 'local'));

    final rows = await db.getProducts('src-fresh');
    final local = rows.firstWhere((p) => p.name == 'Tapé à la main');
    expect(local.source, 'local');
    expect(local.isLocal, isTrue);
  });

  test('an existing row keeps its source through copyWith (edit path)',
      () async {
    final db = await Db.open('src-fresh');
    final id = await db.insertProduct(
        'src-fresh',
        Product(
            name: 'Local existant',
            priceCents: 100,
            stockQty: 1,
            source: 'local'));

    final stored = (await db.getProducts('src-fresh')).firstWhere((p) => p.id == id);
    final edited = stored.copyWith(priceCents: 999);
    expect(edited.source, 'local');
    expect(edited.priceCents, 999);
  });

  test('a version-6 database (what older runs left) gains the source column',
      () async {
    await _seedLegacyDb('src-legacy', version: 6);
    final db = await Db.open('src-legacy');
    final cols = await db.rawQuery('PRAGMA table_info(products)');
    expect(cols.map((c) => c['name']), contains('source'));
    await db.insertProduct(
        'src-legacy', Product(name: 'V6', priceCents: 100, stockQty: 1));
    expect((await db.getProducts('src-legacy')).single.source, 'catalog');
  });

  test('a pre-CAT3b database upgrades and keeps its rows as catalog', () async {
    await _seedLegacyDb('src-legacy');
    final db = await Db.open('src-legacy');

    final cols = await db.rawQuery('PRAGMA table_info(products)');
    expect(cols.map((c) => c['name']), contains('source'));
    // The already-present columns survived the version bump.
    final names = cols.map((c) => c['name']).toList();
    expect(names, containsAll(['photo', 'photo_source']));

    // A row written before the migration reads back with the default.
    await db.insertProduct(
        'src-legacy', Product(name: 'Avant', priceCents: 100, stockQty: 1));
    final rows = await db.getProducts('src-legacy');
    expect(rows.single.source, 'catalog');
  });
}
