/// B1 gate — export a shop's listing to a `.myhanoutlisting` file and read it
/// back through the real verifier. The rows must come back identical, and the
/// file must carry no catalog field.
///
/// Run: flutter test test/services/listing_export_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/models/listing_row.dart';
import 'package:myhanout/services/listing_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/signing_trust.dart';

const _shopKey = 'hanouti';

void main() {
  late SigningTrust trust;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Config.init();
    await Config.setCurrentShopKey(_shopKey);
    await Config.setCatalogVersion(7);
    trust = await SigningTrust.create();

    await Db.open(_shopKey);
    final handle = await Db.databaseHandle(_shopKey);
    await handle.delete('products');
    const rows = [
      ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12),
      ListingRow(barcode: '6111053001673', priceCents: 150, stockQty: 0),
      ListingRow(barcode: '6111035001673', priceCents: 2200, stockQty: 3),
    ];
    for (final r in rows) {
      await handle.insert('products', {
        'name': 'p ${r.barcode}',
        'barcode': r.barcode,
        'price_cents': r.priceCents,
        'stock_qty': r.stockQty,
      });
    }
  });

  tearDown(() async {
    await Db.closeShop(_shopKey);
    final f = await Db.shopDbFile(_shopKey);
    if (await f.exists()) await f.delete();
  });

  test('export -> verify round-trips every row', () async {
    final result = await ListingExportBuilder.export(
      shopKey: _shopKey,
      signerId: SigningTrust.adminId,
      privateSeed: trust.seed(SigningTrust.adminId),
    );

    expect(result.rows, 3);
    expect(result.catalogVersion, 7);
    expect(result.fileName, 'listing_hanouti_v7.myhanoutlisting');
    expect(result.fileName,
        endsWith(ListingBundle.fileExtension));

    final v = await ListingBundle.verify(result.json,
        directory: trust.directory);
    expect(v.ok, isTrue, reason: v.error);
    expect(v.bundle!.shopKey, _shopKey);
    expect(v.bundle!.catalogVersion, 7);
    expect(v.bundle!.rows, const [
      ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12),
      ListingRow(barcode: '6111035001673', priceCents: 2200, stockQty: 3),
      ListingRow(barcode: '6111053001673', priceCents: 150, stockQty: 0),
    ]);
  });

  test('the export is deterministic apart from generated_at', () async {
    final a = await ListingExportBuilder.export(
        shopKey: _shopKey,
        signerId: SigningTrust.adminId,
        privateSeed: trust.seed(SigningTrust.adminId));
    final b = await ListingExportBuilder.export(
        shopKey: _shopKey,
        signerId: SigningTrust.adminId,
        privateSeed: trust.seed(SigningTrust.adminId));
    expect(a.rows, b.rows);
    expect(a.fileName, b.fileName);
  });
}
