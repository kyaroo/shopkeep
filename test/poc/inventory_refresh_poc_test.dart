/// S5 — the inventory photo refresh is DISPLAY-ONLY.
///
/// A `.myhanout` delta fills the photo of matching inventory rows that have
/// none. It must never create rows, and never touch price / stock / name —
/// and it must leave a row that already has a photo completely alone.
///
/// Run: flutter test test/poc/inventory_refresh_poc_test.dart
library inventory_refresh_poc_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shop = 's5-shop';
final _existing = Uint8List.fromList([9, 9, 9]);
final _incoming = Uint8List.fromList([1, 2, 3, 4]);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await Db.closeShop(_shop);
    // Belt-and-braces: drop any file a previous run left behind (barcode is
    // UNIQUE, so a stale row would fail the insert rather than the assertion).
    final f = await Db.shopDbFile(_shop);
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${f.path}$suffix');
      if (await file.exists()) await file.delete();
    }
  });

  test('fills only missing photos; price/stock/name untouched', () async {
    final db = await Db.open(_shop);
    await db.insertProduct(_shop, Product(
      name: 'No photo',
      barcode: 's5-1',
      priceCents: 1234,
      stockQty: 7,
    ));
    await db.insertProduct(_shop, Product(
      name: 'Has photo',
      barcode: 's5-2',
      priceCents: 999,
      stockQty: 3,
      photo: _existing,
      photoSource: 'local',
    ));

    // Gap fill: the photo-less row receives the catalog photo only.
    final filled =
        await Db.applyCatalogPhoto(_shop, barcode: 's5-1', photo: _incoming);
    expect(filled, 1);
    final a = await db.getByBarcode(_shop, 's5-1');
    expect(a, isNotNull);
    expect(a!.photo, equals(_incoming));
    expect(a.photoSource, 'catalog');
    expect(a.priceCents, 1234, reason: 'price must never change');
    expect(a.stockQty, 7, reason: 'stock must never change');
    expect(a.name, 'No photo', reason: 'name must never change');

    // A row that already has a photo is skipped entirely.
    final skipped =
        await Db.applyCatalogPhoto(_shop, barcode: 's5-2', photo: _incoming);
    expect(skipped, 0);
    final b = await db.getByBarcode(_shop, 's5-2');
    expect(b, isNotNull);
    expect(b!.photo, equals(_existing));
    expect(b.photoSource, 'local');
    expect(b.priceCents, 999);
    expect(b.stockQty, 3);

    // An unknown barcode creates nothing.
    final none = await Db.applyCatalogPhoto(_shop, barcode: 's5-missing',
        photo: _incoming);
    expect(none, 0);

    // ignore: avoid_print
    print('S5 refresh: gap filled=1 (price/stock/name intact), '
        'existing photo skipped=0, unknown barcode=0');
  });
}
