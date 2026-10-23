import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:myhanout/data/catalog_db.dart';
import 'package:myhanout/models/catalog_entry.dart';

CatalogEntry e(String barcode, String name, int updatedAt) => CatalogEntry(
      barcode: barcode,
      name: name,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // NOTE: CatalogDb.instance is a singleton against the default db path.
  // These tests use unique barcodes per run to stay independent of state.

  test('delete records a pending tombstone', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    await repo.upsert(e('TOMB1', 'To tombstone', 1000));
    await repo.delete('TOMB1');

    // Row gone from products...
    expect(await repo.get('TOMB1'), isNull);
    // ...but tombstone is pending.
    final pending = await repo.pendingDeletes();
    expect(pending, contains('TOMB1'));
  });

  test('clearPendingDelete removes the tombstone', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    await repo.upsert(e('TOMB2', 'Clear me', 1000));
    await repo.delete('TOMB2');
    await repo.clearPendingDelete('TOMB2');
    expect(await repo.pendingDeletes(), isNot(contains('TOMB2')));
  });

  test('changedSince returns only entries newer than the watermark', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    await repo.upsert(e('DELTA_OLD', 'Old', 1000));
    await repo.upsert(e('DELTA_NEW', 'New', 5000));

    final delta = await repo.changedSince(2000);
    final barcodes = delta.map((x) => x.barcode).toList();
    expect(barcodes, contains('DELTA_NEW'));
    expect(barcodes, isNot(contains('DELTA_OLD')));
  });

  test('changedSince with 0 returns everything', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    await repo.upsert(e('DELTA_ALL', 'All', 1000));
    final all = await repo.changedSince(0);
    expect(all.length, greaterThanOrEqualTo(1));
  });
}
