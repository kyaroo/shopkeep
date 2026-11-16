/// Regression tests for the client-side security fixes.
///
/// 1. No baked sync credentials — an unset token must mean "not configured".
/// 2. `shop_key` is a safe slug on every path (it becomes a filename).
/// 3. The server-calling catalog methods are admin-gated, so the shopkeeper
///    flavor no-ops even with a token present.
///
/// The end-to-end proof for (3) is the release-APK grep (no token / no server
/// host / no OFF host in `app-shopkeeper-release.apk`); these tests pin the
/// client-side behaviour.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/data/sync_config.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/utils/slug.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('no baked sync credentials', () {
    test('an unset token means not configured (no hardcoded default)', () async {
      SharedPreferences.setMockInitialValues({});
      final cfg = await SyncConfig.load();
      expect(cfg.token, isNull, reason: 'a baked token default must not exist');
      expect(cfg.isConfigured, isFalse);
    });

    test('a stored URL + token still configures the client', () async {
      SharedPreferences.setMockInitialValues({
        'sync_url': 'https://catalog.example.test',
        'sync_token': 'abc123',
      });
      final cfg = await SyncConfig.load();
      expect(cfg.isConfigured, isTrue);
    });
  });

  group('shop_key validation', () {
    test('accepts real shop keys', () {
      for (final k in [
        'hanouti',
        's5-shop',
        'test-shop-2',
        'default',
        'a',
        'x' * 63,
      ]) {
        expect(isValidShopKey(k), isTrue, reason: k);
      }
    });

    test('rejects traversal, separators, dots, uppercase, empty, too long', () {
      for (final k in [
        '',
        '..',
        '../evil',
        'a/b',
        'a\\b',
        'A',
        'x..y',
        'a b',
        'x' * 64,
      ]) {
        expect(isValidShopKey(k), isFalse, reason: k);
      }
    });

    test('Db.shopDbPath throws on a traversal key (last line of defence)',
        () async {
      await expectLater(
        () => Db.shopDbPath('../evil'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => Db.shopDbPath(''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('server calls are admin-gated', () {
    test('resolveFromServer / browseServer / syncNow no-op as shopkeeper',
        () async {
      // A configured token would let an unguarded call reach the network; the
      // guards must return before that. kIsAdmin is false under `flutter test`.
      SharedPreferences.setMockInitialValues({
        'sync_url': 'https://catalog.example.test',
        'sync_token': 'abc123',
      });
      final provider = CatalogProvider();

      expect(await provider.resolveFromServer('0011210006508'), isNull);
      expect(await provider.browseServer(), isNull);
      expect(await provider.syncNow(), isFalse);
    });
  });
}
