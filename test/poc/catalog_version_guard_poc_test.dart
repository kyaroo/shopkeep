/// S4 — base-version guard for `.myhanout` catalog deltas.
///
/// The device's installed catalog version lives in `Config.catalog_version`.
/// A delta whose `base_version` differs is rejected whole (never half-applied);
/// an accepted delta advances the version.
///
/// Run: flutter test test/poc/catalog_version_guard_poc_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_db.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/myhanout_file.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shopKey = 'hanouti';
const _shopId = 'shop-abc-123';
const _barcode = '0011210006508';
final _photo = Uint8List.fromList([1, 2, 3, 4, 5]);

CatalogDelta _delta(int base, int target) => CatalogDelta(
      shopKey: _shopKey,
      shopId: _shopId,
      baseVersion: base,
      targetVersion: target,
      generatedAt: target,
      upserts: [
        CatalogEntry(
          barcode: _barcode,
          name: 'Tabasco Habaneros hot',
          category: 'grocery',
          photo: _photo,
          createdAt: base,
          updatedAt: target,
        ),
      ],
    );

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
    await Config.setShopId(_shopId);
    // Let the catalog singleton initialize (seeding on first use) BEFORE the
    // test pins a version, otherwise the seed would overwrite it.
    await CatalogDb.instance.init();
  });

  test('stale deltas are rejected, an accepted one advances the version',
      () async {
    await Config.setCatalogVersion(1000);

    final next = await MyhanoutFile.applyJson(_delta(1000, 1001).toFileJson());
    expect(next, startsWith('applied 1 update(s)'));
    expect(await Config.getCatalogVersion(), 1001);

    // Replaying the same bundle is stale now.
    final replay =
        await MyhanoutFile.applyJson(_delta(1000, 1001).toFileJson());
    expect(replay, contains('catalog version mismatch'));
    expect(await Config.getCatalogVersion(), 1001);

    // A bundle built from an older generation is stale too.
    final older = await MyhanoutFile.applyJson(_delta(999, 1000).toFileJson());
    expect(older, contains('catalog version mismatch'));
    expect(await Config.getCatalogVersion(), 1001);

    // The next delta in the sequence applies and advances again.
    final third = await MyhanoutFile.applyJson(_delta(1001, 1002).toFileJson());
    expect(third, startsWith('applied 1 update(s)'));
    expect(await Config.getCatalogVersion(), 1002);

    // ignore: avoid_print
    print('S4 guard: 1000→1001 applied, 1000 rejected, 999 rejected, '
        '1001→1002 applied (device now ${await Config.getCatalogVersion()})');
  });
}
