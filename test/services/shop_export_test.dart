// The three export artifacts: what they contain, and what they must never
// contain.
//
// The listing/history/catalog verbs are deliberately distinct — calling the
// shop's price/stock rows "the catalog" is what let a catalog export surface in
// the shopkeeper flavor. And no export may carry photos: the catalog's 13k
// images are a 49 MB file no shopkeeper can use, and the listing/history are
// per-shop rows.
//
// Run: flutter test test/services/shop_export_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/models/product.dart';
import 'package:myhanout/services/shop_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shop = 'export-shop';

Future<void> _cleanUp() async {
  await Db.closeShop(_shop);
  final f = await Db.shopDbFile(_shop);
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('${f.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

/// A one-page catalog repository; records the page size it was asked for so the
/// paging loop is exercised.
class _FakeCatalog implements CatalogRepository {
  _FakeCatalog(this.entries);
  final List<CatalogEntry> entries;
  final List<int> requestedLimits = [];

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => null;

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async {
    requestedLimits.add(limit!);
    return entries.skip(offset ?? 0).take(limit).toList();
  }

  @override
  Future<void> upsert(CatalogEntry entry) async {}

  @override
  Future<void> delete(String barcode) async {}

  @override
  Future<int> count({String? search}) async => entries.length;
}

CatalogEntry _entry(String barcode, {Uint8List? photo}) => CatalogEntry(
      barcode: barcode,
      name: 'Product $barcode',
      category: 'grocery',
      photo: photo,
      createdAt: 1,
      updatedAt: 2,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(_cleanUp);
  tearDown(_cleanUp);

  test('the listing export carries price and stock, and no photo', () async {
    final db = await Db.open(_shop);
    await db.insertProduct(
        _shop,
        Product(
            name: 'Tabasco Habanero',
            barcode: '0011210006508',
            priceCents: 1250,
            stockQty: 7));
    await db.insertProduct(
        _shop,
        Product(
            name: 'Ain Atlas 50cl',
            barcode: '6111053001673',
            priceCents: 800,
            stockQty: 0));

    final map = jsonDecode(await ShopExportService.listingJson(_shop))
        as Map<String, dynamic>;
    expect(map['format'], ShopExportService.listingFormat);
    expect(map['shop_key'], _shop);
    expect(map['count'], 2);

    final rows = (map['rows'] as List)
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => (a['barcode'] as String).compareTo(b['barcode'] as String));
    expect(rows.first,
        {'barcode': '0011210006508', 'name': 'Tabasco Habanero',
         'price_cents': 1250, 'stock_qty': 7});
    // No photo key at all — not null, absent.
    expect(rows.first.containsKey('photo'), isFalse);
    expect(jsonEncode(map).contains('photo'), isFalse);
  });

  test('the history export carries each sale with its line items', () async {
    final db = await Db.open(_shop);
    await db.insertSale(_shop, 2500, [
      {'productName': 'Tabasco Habanero', 'unitPriceCents': 1250,
       'quantity': 2, 'lineTotalCents': 2500},
    ]);

    final map = jsonDecode(await ShopExportService.historyJson(_shop))
        as Map<String, dynamic>;
    expect(map['format'], ShopExportService.historyFormat);
    expect(map['count'], 1);
    final sales = (map['sales'] as List).cast<Map<String, dynamic>>();
    expect(sales.single['total_cents'], 2500);
    expect((sales.single['items'] as List), isNotEmpty);
    expect(jsonEncode(map).contains('photo'), isFalse);
  });

  test('the catalog export is metadata only and pages through the repository',
      () async {
    final photo = Uint8List.fromList([1, 2, 3]);
    final repo = _FakeCatalog([
      _entry('0011210006508'),
      _entry('6111053001673', photo: photo),
    ]);

    final map = jsonDecode(await ShopExportService.catalogJson(repo: repo))
        as Map<String, dynamic>;
    expect(map['format'], ShopExportService.catalogFormat);
    expect(map['count'], 2);
    // The repository was paged, not read in one unbounded call.
    expect(repo.requestedLimits, isNotEmpty);
    expect(repo.requestedLimits.every((l) => l <= 2000), isTrue);

    final rows = (map['products'] as List).cast<Map<String, dynamic>>();
    expect(rows.first,
        {'barcode': '0011210006508', 'name': 'Product 0011210006508',
         'name_ar': null, 'name_en': null, 'category': 'grocery'});
    // The entry had a photo; the export must not.
    expect(rows.last.containsKey('photo'), isFalse);
    expect(jsonEncode(map).contains('photo'), isFalse);
  });

  test('file names distinguish the three artifacts', () {
    expect(ShopExportService.fileName(ShopExportService.listingFormat, 'h'),
        'listing_h.json');
    expect(ShopExportService.fileName(ShopExportService.historyFormat, 'h'),
        'history_h.json');
    expect(ShopExportService.fileName(ShopExportService.catalogFormat, 'h'),
        'catalog_h.json');
  });
}
