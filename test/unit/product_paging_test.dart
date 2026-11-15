// ARCH-4 — the inventory query is bounded (paged) instead of unbounded.
//
// Run: flutter test test/unit/product_paging_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shop = 'paging-shop';

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

  Future<void> _seed(int count) async {
    final db = await Db.open(_shop);
    for (var i = 0; i < count; i++) {
      await db.insertProduct(
        _shop,
        Product(
          name: 'P$i',
          barcode: 'bc$i',
          priceCents: 100,
          stockQty: 1,
        ),
      );
    }
  }

  test('countProducts counts every row, not just the loaded page', () async {
    await _seed(120);
    final db = await Db.open(_shop);
    expect(await db.countProducts(_shop), 120);
  });

  test('getProducts pages with limit/offset', () async {
    await _seed(120);
    final db = await Db.open(_shop);

    final first = await db.getProducts(_shop, limit: 50);
    final second = await db.getProducts(_shop, limit: 50, offset: 50);
    final last = await db.getProducts(_shop, limit: 50, offset: 100);
    final beyond = await db.getProducts(_shop, limit: 50, offset: 200);

    expect(first, hasLength(50));
    expect(second, hasLength(50));
    expect(last, hasLength(20));
    expect(beyond, isEmpty);

    // Pages do not overlap.
    final ids = {...first.map((p) => p.barcode), ...second.map((p) => p.barcode)};
    expect(ids, hasLength(100));
  });

  test('no limit keeps the legacy full-list behaviour', () async {
    await _seed(120);
    final db = await Db.open(_shop);
    expect(await db.getProducts(_shop), hasLength(120));
  });

  test('search narrows both the page and the count', () async {
    await _seed(5);
    final db = await Db.open(_shop);
    await db.insertProduct(_shop,
        Product(name: 'Couscous', barcode: 'c1', priceCents: 100, stockQty: 1));
    await db.insertProduct(_shop,
        Product(name: 'Couscous 1kg', barcode: 'c2', priceCents: 100, stockQty: 1));

    expect(await db.countProducts(_shop, search: 'couscous'), 2);
    final page =
        await db.getProducts(_shop, search: 'couscous', limit: 1, offset: 0);
    expect(page, hasLength(1));
    expect(page.single.name, contains('Couscous'));
  });
}
