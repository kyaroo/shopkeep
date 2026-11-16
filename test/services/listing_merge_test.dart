/// B3 gate — the merge policy. Every assertion here is one of the locked
/// decisions D3 (only price/stock by barcode), D4 (never delete), D5 (atomic),
/// B-1 (a new row needs a name) or attribution (audit rows carry changed_by).
///
/// Run: flutter test test/services/listing_merge_test.dart
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/models/listing_row.dart';
import 'package:myhanout/services/listing_merge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shopKey = 'hanouti';

class _MemoryCatalog implements CatalogRepository {
  final _entries = <String, CatalogEntry>{};

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => _entries[barcode];

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async =>
      _entries.values.toList();

  @override
  Future<void> upsert(CatalogEntry entry) async => _entries[entry.barcode] = entry;

  @override
  Future<void> delete(String barcode) async => _entries.remove(barcode);

  @override
  Future<int> count({String? search}) async => _entries.length;
}

void main() {
  late _MemoryCatalog catalog;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Config.init();
    await Config.setCurrentShopKey(_shopKey);
    catalog = _MemoryCatalog();
    await Db.open(_shopKey);
    final handle = await Db.databaseHandle(_shopKey);
    await handle.delete('products');
    await handle.delete('audit_log');
  });

  tearDown(() async {
    await Db.closeShop(_shopKey);
    final f = await Db.shopDbFile(_shopKey);
    if (await f.exists()) await f.delete();
  });

  Future<void> seedProduct(String barcode, String name, int price, int stock,
      {List<int>? photo}) async {
    final handle = await Db.databaseHandle(_shopKey);
    await handle.insert('products', {
      'name': name,
      'barcode': barcode,
      'price_cents': price,
      'stock_qty': stock,
      'photo': photo,
      'source': 'catalog',
    });
  }

  Future<List<Map<String, Object?>>> products() async {
    final handle = await Db.databaseHandle(_shopKey);
    return handle.query('products', orderBy: 'barcode');
  }

  Future<List<Map<String, Object?>>> audit() async {
    final handle = await Db.databaseHandle(_shopKey);
    return handle.query('audit_log', orderBy: 'id');
  }

  ListingBundle bundle(List<ListingRow> rows) => ListingBundle(
        signerId: 'admin-1',
        shopKey: _shopKey,
        catalogVersion: 7,
        generatedAt: 1,
        rows: rows,
      );

  test('a new barcode is inserted with its name from the catalog (B-1)', () async {
    await catalog.upsert(CatalogEntry(
        barcode: '0011210006508',
        name: 'Tabasco Habanero',
        category: 'grocery',
        createdAt: 1,
        updatedAt: 1));

    final r = await ListingMergeService.merge(
        bundle(const [
          ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12)
        ]),
        changedBy: 'Admin',
        catalog: catalog);

    expect(r.inserted, 1);
    expect(r.namedFromCatalog, 1);
    expect(r.notInCatalog, 0);
    final row = (await products()).single;
    expect(row['name'], 'Tabasco Habanero');
    expect(row['price_cents'], 890);
    expect(row['stock_qty'], 12);
    expect(row['source'], 'catalog');
  });

  test('a barcode in no catalog is flagged for recovery', () async {
    final r = await ListingMergeService.merge(
        bundle(const [
          ListingRow(barcode: '9999999999999', priceCents: 100, stockQty: 1)
        ]),
        changedBy: 'Admin',
        catalog: catalog);

    expect(r.inserted, 1);
    expect(r.notInCatalog, 1);
    expect(r.namedFromCatalog, 0);
    final row = (await products()).single;
    // `products.name` is NOT NULL, so the barcode is the display fallback.
    expect(row['name'], '9999999999999');
    expect(row['source'], 'listing');
  });

  test('an existing row is updated and its catalog fields are never touched',
      () async {
    await seedProduct('0011210006508', 'Tabasco Habanero', 500, 3,
        photo: Uint8List.fromList([1, 2, 3, 4]));

    final r = await ListingMergeService.merge(
        bundle(const [
          ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12)
        ]),
        changedBy: 'Admin',
        catalog: catalog);

    expect(r.updated, 1);
    expect(r.inserted, 0);
    final row = (await products()).single;
    expect(row['price_cents'], 890);
    expect(row['stock_qty'], 12);
    // D3: name and photo belong to the catalog, not the listing.
    expect(row['name'], 'Tabasco Habanero');
    expect(row['photo'], [1, 2, 3, 4]);
  });

  test('an identical row is left alone (no write, no audit)', () async {
    await seedProduct('0011210006508', 'Tabasco Habanero', 890, 12);

    final r = await ListingMergeService.merge(
        bundle(const [
          ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12)
        ]),
        changedBy: 'Admin',
        catalog: catalog);

    expect(r.unchanged, 1);
    expect(r.touched, 0);
    expect(await audit(), isEmpty);
  });

  test('import never deletes (D4)', () async {
    await seedProduct('0011210006508', 'Tabasco Habanero', 890, 12);
    await seedProduct('6111053001673', 'Ain Atlas', 150, 0);

    await ListingMergeService.merge(
        bundle(const [
          ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12)
        ]),
        changedBy: 'Admin',
        catalog: catalog);

    expect((await products()).length, 2);
  });

  test('every change writes an audit row carrying the signer', () async {
    await catalog.upsert(CatalogEntry(
        barcode: '0011210006508',
        name: 'Tabasco Habanero',
        category: 'grocery',
        createdAt: 1,
        updatedAt: 1));
    await seedProduct('6111053001673', 'Ain Atlas', 150, 0);

    await ListingMergeService.merge(
        bundle(const [
          ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12),
          ListingRow(barcode: '6111053001673', priceCents: 200, stockQty: 5),
        ]),
        changedBy: 'Omar',
        catalog: catalog);

    final rows = await audit();
    expect(rows.length, 2);
    expect(rows.every((r) => r['changed_by'] == 'Omar'), isTrue);
    expect(rows.every((r) => r['table_name'] == 'products'), isTrue);
    expect(rows.map((r) => r['action']).toSet(), {'insert', 'update'});
    // The old values are recorded, so a price change can be reviewed.
    expect(rows.firstWhere((r) => r['action'] == 'update')['old_values'],
        '{"price_cents":150,"stock_qty":0}');
  });
}
