/// B2 gate — the round trip. Export a listing from one shop, import the file
/// into another, and the listing must come back identical. A rejected bundle
/// must leave the target untouched.
///
/// Run: flutter test test/services/listing_import_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/services/listing_export_service.dart';
import 'package:myhanout/services/listing_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/signing_trust.dart';

const _from = 'hanouti';
const _to = 's5-shop';

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
    await Config.setCatalogVersion(7);
    trust = await SigningTrust.create();
  });

  tearDown(() async {
    for (final key in [_from, _to]) {
      await Db.closeShop(key);
      final f = await Db.shopDbFile(key);
      if (await f.exists()) await f.delete();
    }
  });

  Future<void> seedSource() async {
    await Db.open(_from);
    final handle = await Db.databaseHandle(_from);
    await handle.delete('products');
    // The target shop must start empty too: `flutter test` shares one SQLite
    // factory across files, so a leftover listing from another file would
    // otherwise be counted as imported rows.
    await Db.open(_to);
    final target = await Db.databaseHandle(_to);
    await target.delete('products');
    const rows = [
      ['0011210006508', 'Tabasco Habanero', 890, 12],
      ['6111053001673', 'Ain Atlas', 150, 0],
      ['6111035001673', 'Couscous Dari', 2200, 3],
    ];
    for (final r in rows) {
      await handle.insert('products', {
        'name': r[1],
        'barcode': r[0],
        'price_cents': r[2],
        'stock_qty': r[3],
      });
    }
  }

  Future<List<Map<String, Object?>>> listingOf(String shopKey) async {
    await Db.open(shopKey);
    final handle = await Db.databaseHandle(shopKey);
    return handle.query('products', orderBy: 'barcode');
  }

  Future<String> export() async {
    final result = await ListingExportBuilder.export(
      shopKey: _from,
      signerId: SigningTrust.adminId,
      privateSeed: trust.seed(SigningTrust.adminId),
    );
    return result.json;
  }

  /// Re-signs an exported bundle for a different shop, keeping every row.
  Future<String> reshop(String artifactFile, String shopKey) async {
    final payload = Signing.splitArtifact(artifactFile).$1
      ..['shop_key'] = shopKey;
    return Signing.signArtifactFile(payload, trust.seed(SigningTrust.adminId));
  }

  test('export -> import reproduces the listing exactly', () async {
    await seedSource();
    final before = await listingOf(_from);
    // Import into a DIFFERENT shop: that is the real delivery path.
    final json = await reshop(await export(), _to);

    final outcome =
        await ListingImportService.apply(json, directory: trust.directory);

    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.shopKey, _to);
    expect(outcome.signerName, SigningTrust.adminId);
    expect(outcome.merge!.inserted, 3);
    expect(outcome.merge!.updated, 0);
    expect(outcome.merge!.unchanged, 0);

    final after = await listingOf(_to);
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      // D3: the listing is barcode + price + stock. The name comes from the
      // catalog on the receiving device, not from the bundle.
      expect(after[i]['barcode'], before[i]['barcode']);
      expect(after[i]['price_cents'], before[i]['price_cents']);
      expect(after[i]['stock_qty'], before[i]['stock_qty']);
    }
  });

  test('a re-signed bundle binds the shop it names, leaving the source alone',
      () async {
    await seedSource();
    final json = await reshop(await export(), _to);

    final outcome =
        await ListingImportService.apply(json, directory: trust.directory);

    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.shopKey, _to);
    expect(await Config.getCurrentShopKey(), _to);
    expect((await listingOf(_to)).length, 3);
    expect((await listingOf(_from)).length, 3);
  });

  test('a tampered bundle is rejected and writes nothing', () async {
    await seedSource();
    final map = jsonDecode(await export()) as Map<String, dynamic>;
    (map['rows'] as List).first['price_cents'] = 1;

    final outcome =
        await ListingImportService.apply(jsonEncode(map), directory: trust.directory);

    expect(outcome.ok, isFalse);
    expect(outcome.error, 'bad-signature');
    expect(outcome.merge, isNull);
    expect(outcome.shopKey, isNull);
  });

  test('a salesman-signed bundle is rejected (provision-only role)', () async {
    await seedSource();
    final result = await ListingExportBuilder.export(
      shopKey: _from,
      signerId: SigningTrust.salesmanId,
      privateSeed: trust.seed(SigningTrust.salesmanId),
    );

    final outcome =
        await ListingImportService.apply(result.json, directory: trust.directory);

    expect(outcome.ok, isFalse);
    expect(outcome.error, 'forbidden-role');
  });

  test('garbage is rejected without throwing', () async {
    for (final json in ['', '{', 'null']) {
      final outcome =
          await ListingImportService.apply(json, directory: trust.directory);
      expect(outcome.ok, isFalse, reason: json);
    }
  });
}
