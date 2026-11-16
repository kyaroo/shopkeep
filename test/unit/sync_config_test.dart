/// Unit tests for [SyncConfig] — the sync configuration holder.
///
/// These tests verify the basic configuration surface: defaults, isConfigured
/// flag, and client() factory. No network or SQLite is touched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/sync_config.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  group('SyncConfig', () {
    test('isConfigured is false when url/token empty', () {
      final cfg = SyncConfig(
        url: null,
        token: null,
        lastSyncedAt: 0,
        deviceId: 'test-device',
      );

      expect(cfg.isConfigured, isFalse);
    });

    test('isConfigured is true when url and token set', () {
      final cfg = SyncConfig(
        url: '  https://example.com  ',
        token: '  test-token  ',
        lastSyncedAt: 0,
        deviceId: 'test-device',
      );

      expect(cfg.isConfigured, isTrue);
    });

    test('no baked token default: load() with no prefs yields no token',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final loaded = await SyncConfig.load();
      expect(loaded.token, isNull, reason: 'the token must come from settings');
      expect(loaded.isConfigured, isFalse);
      expect(SyncConfig.defaultUrl, isNotEmpty);
    });

    test('client() returns a CatalogSyncClient and is re-created per call', () {
      final cfg = SyncConfig(
        url: 'https://example.com',
        token: 'test-token',
        lastSyncedAt: 0,
        deviceId: 'test-device',
      );

      final client1 = cfg.client();
      final client2 = cfg.client();

      expect(client1, isA<CatalogSyncClient>());
      expect(client2, isA<CatalogSyncClient>());
      // Each call returns a new instance.
      expect(client1, isNot(same(client2)));
    });
  });
}
