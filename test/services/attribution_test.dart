/// Attribution gate — both local logs are read, merged newest-first, and
/// attributed to the signer who caused them.
///
/// Run: flutter test test/services/attribution_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_db.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/models/listing_row.dart';
import 'package:myhanout/services/attribution_service.dart';
import 'package:myhanout/services/listing_merge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/signing_trust.dart';

const _shopKey = 'hanouti';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Config.init();
    await Config.setCurrentShopKey(_shopKey);
    await CatalogDb.instance.init();
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

  test('both sources are merged, attributed, and sorted newest-first',
      () async {
    // Catalog side: a delta applied by a named signer.
    await CatalogDb.instance.logSigner(
      version: 999,
      signedBy: 'Omar',
      signedById: SigningTrust.salesmanId,
      entryCount: 5,
      appliedOnShop: _shopKey,
    );

    // Listing side: a merge writes audit rows carrying its signer.
    await Db.open(_shopKey);
    final handle = await Db.databaseHandle(_shopKey);
    await handle.insert('products', {
      'name': 'Tabasco Habanero',
      'barcode': '0011210006508',
      'price_cents': 890,
      'stock_qty': 12,
    });
    await ListingMergeService.merge(
      ListingBundle(
        signerId: SigningTrust.adminId,
        shopKey: _shopKey,
        catalogVersion: 999,
        generatedAt: 1,
        rows: const [
          ListingRow(barcode: '0011210006508', priceCents: 950, stockQty: 4),
        ],
      ),
      changedBy: 'Sara',
    );

    final entries = await AttributionService.recent(shopKey: _shopKey);

    expect(
        entries.any((e) =>
            e.kind == 'catalog' && e.actor == 'Omar' && e.detail.contains('v999')),
        isTrue,
        reason: 'the catalog push must be attributed');
    expect(
        entries.any((e) =>
            e.kind == 'listing' &&
            e.actor == 'Sara' &&
            e.detail.startsWith('update')),
        isTrue,
        reason: 'the listing change must be attributed');
    for (var i = 1; i < entries.length; i++) {
      expect(entries[i - 1].at, greaterThanOrEqualTo(entries[i].at),
          reason: 'newest first');
    }
  });

  test('the trail is capped and the shop rows are all present', () async {
    for (var i = 0; i < 8; i++) {
      await insertProduct(_shopKey, '001121000650$i');
    }
    // A different price on every row so each one produces an audit row.
    await ListingMergeService.merge(
      ListingBundle(
        signerId: SigningTrust.adminId,
        shopKey: _shopKey,
        catalogVersion: 1,
        generatedAt: 1,
        rows: [
          for (var i = 0; i < 8; i++)
            ListingRow(barcode: '001121000650$i', priceCents: 100, stockQty: 1),
        ],
      ),
      changedBy: 'Sara',
    );

    // The catalog side is a device-wide singleton shared across test files, so
    // the assertions are on the cap and on this shop's own rows.
    expect((await AttributionService.recent(shopKey: _shopKey, limit: 3)).length, 3);
    final all = await AttributionService.recent(shopKey: _shopKey, limit: 50);
    expect(all.length, lessThanOrEqualTo(50));
    expect(all.where((e) => e.kind == 'listing').length, 8);
  });
}

Future<void> insertProduct(String shopKey, String barcode) async {
  final handle = await Db.databaseHandle(shopKey);
  await handle.insert('products', {
    'name': 'p $barcode',
    'barcode': barcode,
    'price_cents': 0,
    'stock_qty': 0,
  });
}
