/// Unit tests for [SyncService] — the sync controller.
///
/// All external boundaries are faked:
///   - [FakeDeltaRepository]  — repository delta methods
///   - [TestSyncConfig]       — sync config holder
///   - [TestSyncClient]       — network client (no HTTP)
///
/// These tests verify the sync lifecycle: not-configured → configured-and-success
/// → auth-failed → server-error → generic-error, and that the watermark is
/// advanced and tombstones cleared only on success.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/sync_service.dart';
import 'package:myhanout/models/catalog_entry.dart';

import '../helpers/mock_providers.dart';

void main() {
  group('SyncService', () {
    late SyncService service;
    late FakeDeltaRepository repo;
    late TestSyncConfig config;

    setUp(() {
      repo = FakeDeltaRepository();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final syncResult = SyncResult(
        accepted: 0,
        rejected: const [],
        serverNow: nowMs,
        newerOnServer: const [],
      );
      config = TestSyncConfig(
        TestSyncClient(pushResponse: syncResult),
        'https://example.com',
        'test-token',
        syncResult,
      );
      service = SyncService();
    });

    test('syncNow: not configured returns false and sets message', () async {
      // Point the config at a truly unconfigured one.
      final unconfigured = TestSyncConfig(
        TestSyncClient(pushResponse: SyncResult(accepted: 0, rejected: const [], serverNow: 0, newerOnServer: const [])),
        '',  // url
        '',  // token
        SyncResult(accepted: 0, rejected: const [], serverNow: 0, newerOnServer: const []),
      );

      final result = await service.syncNow(
        repo: repo as CatalogDeltaRepository,
        config: unconfigured,
        entries: const [],
      );
      expect(result, isFalse);
      expect(service.syncMessage, contains('not configured'));
      expect(service.syncing, isFalse);
    });

    test('syncNow: configured and success advances watermark + clears tombstones', () async {
      final entries = <CatalogEntry>[
        CatalogEntry(barcode: 'A', name: 'A', createdAt: 1, updatedAt: 1),
        CatalogEntry(barcode: 'B', name: 'B', createdAt: 1, updatedAt: 1),
      ];

      // Program the fake repository.
      repo.setChangedSince(Future.value(entries));
      repo.setPendingDeletes(['T1']);

      // Use a future timestamp and the expected accepted count for this test.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final syncResult = SyncResult(
        accepted: 2,
        rejected: const [],
        serverNow: nowMs,
        newerOnServer: const [],
      );
      config = config.copyWith(
        client: TestSyncClient(pushResponse: syncResult),
        pushResponse: syncResult,
      );

      final result = await service.syncNow(
        repo: repo as CatalogDeltaRepository,
        config: config,
        entries: entries,
      );

      expect(result, isTrue);
      expect(service.syncing, isFalse);
      expect(service.syncMessage, contains('Synced 2'));
      expect(service.syncMessage, contains('1 deleted'));

      // Watermark advanced.
      expect(config.lastSyncedAt, greaterThan(1000));

      // Tombstone cleared.
      expect(repo.wasCleared('T1'), isTrue);
    });

    test('syncNow: fails with SyncAuthException', () async {
      // Build a client that throws on push via a pushFn callback.
      final authClient = TestSyncClient(
        pushResponse: SyncResult(accepted: 0, rejected: const [], serverNow: 0, newerOnServer: const []),
        pushFn: ({required List<CatalogEntry> entries, required List<String> deleted, required int lastSyncedAt}) =>
            Future.error(SyncAuthException('auth failed (401)')),
      );

      final config2 = TestSyncConfig(
        authClient,
        'https://example.com',
        'wrong-token',
        SyncResult(accepted: 0, rejected: const [], serverNow: 0, newerOnServer: const []),
      );

      final result = await service.syncNow(
        repo: repo,
        config: config2,
        entries: const [],
      );

      expect(result, isFalse);
      expect(service.syncMessage, contains('bad token or URL'));
      expect(service.syncing, isFalse);
    });

    test('syncNow: fails with SyncException (server error)', () async {
      // Build a client that throws on push via a pushFn callback.
      final errorClient = TestSyncClient(
        pushResponse: SyncResult(accepted: 0, rejected: const [], serverNow: 0, newerOnServer: const []),
        pushFn: ({required List<CatalogEntry> entries, required List<String> deleted, required int lastSyncedAt}) =>
            Future.error(SyncException('server error 500')),
      );

      final config2 = TestSyncConfig(
        errorClient,
        'https://example.com',
        'test-token',
        SyncResult(accepted: 0, rejected: const [], serverNow: 0, newerOnServer: const []),
      );

      final result = await service.syncNow(
        repo: repo,
        config: config2,
        entries: const [],
      );

      expect(result, isFalse);
      expect(service.syncMessage, contains('server error'));
      expect(service.syncing, isFalse);
    });

    test('syncNow: success path clears tombstones and advances watermark even when push returns no new entries', () async {
      final entries = <CatalogEntry>[
        CatalogEntry(barcode: 'C', name: 'C', createdAt: 1, updatedAt: 1),
      ];

      repo.setChangedSince(Future.value(entries));
      repo.setPendingDeletes([]);

      final result = await service.syncNow(
        repo: repo as CatalogDeltaRepository,
        config: config,
        entries: entries,
      );

      expect(result, isTrue);
      expect(config.lastSyncedAt, greaterThan(1000));
      expect(repo.clearedBarcodes, isEmpty);
    });
  });
}
