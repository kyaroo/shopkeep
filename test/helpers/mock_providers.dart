/// Mock helpers for the mocktail test suite.
///
/// The app's external boundaries are replaced here with in-memory fakes so
/// tests never touch SQLite, SharedPreferences, or the network.
///
/// Exports (public, re-exported for convenience):
///   MockCatalogRepository        mock of [CatalogRepository] (interface)
///   MockCatalogDeltaRepository   mock of [CatalogDeltaRepository] (interface)
///   TestSyncConfig               test double of [SyncConfig]
///   TestSyncClient               test double of [CatalogSyncClient]
///   MockCatalogSyncClient        mock of [CatalogSyncClient]
///
/// Usage in tests:
///   final repo = MockCatalogRepository();
///   when(() => repo.get('A')).thenAnswer((_) => Future.value(entry));
///   when(() => repo.all()).thenAnswer((_) => Future.value(entries));
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:myhanout/app_state.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/sync_config.dart';
import 'package:myhanout/data/catalog_sync_client.dart';

/// A mutable state holder for tests. Mirrors [AppState] so tests can feed
/// shop/business-name changes and observe [notifyListeners] without going
/// through the UI.
class TestAppState extends ChangeNotifier {
  String _shopKey = 'default';
  String _businessName = 'Test Shop';

  String get shopKey => _shopKey;
  String get businessName => _businessName;

  set shopKey(String v) {
    if (_shopKey == v) return;
    _shopKey = v;
    notifyListeners();
  }

  set businessName(String v) {
    if (_businessName == v) return;
    _businessName = v;
    notifyListeners();
  }
}

/// A test [SyncConfig] with controllable fields. Used to feed test values
/// into tests without touching the real SharedPreferences store.
class TestSyncConfig extends SyncConfig {
  TestSyncConfig(
    this._client,
    String url,
    String token,
    this.pushResponse,
  ) : _url = url,
       _token = token,
       super(url: url, token: token, lastSyncedAt: 1000, deviceId: 'test-device');

  final CatalogSyncClient _client;
  final String _url;
  final String _token;
  final SyncResult pushResponse;

  @override
  CatalogSyncClient client() => _client;

  @override
  String get url => _url;
  @override
  String get token => _token;

  TestSyncConfig copyWith({CatalogSyncClient? client, SyncResult? pushResponse}) {
    final currentPushResponse = this.pushResponse;
    return TestSyncConfig(
      client ?? _client,
      _url,
      _token,
      pushResponse ?? currentPushResponse,
    );
  }

  /// Test-safe override: SharedPreferences is not available in test isolates.
  @override
  Future<void> save() async {
    // No-op in tests; no need to touch the real SharedPreferences store.
  }
}

/// A simple in-memory fake repository for testing SyncService. No mocktail
/// reflection quirks — just returns pre-programmed responses.
class FakeDeltaRepository implements CatalogDeltaRepository {
  Future<List<CatalogEntry>>? _changedSince;
  List<String>? _pendingDeletes;
  List<String>? _cleared;

  void setChangedSince(Future<List<CatalogEntry>>? value) => _changedSince = value;
  void setPendingDeletes(List<String>? value) => _pendingDeletes = value;
  void clearDeleted(String barcode) => _cleared?.add(barcode);

  @override
  Future<List<CatalogEntry>> changedSince(int sinceMs) async =>
      _changedSince ?? Future.value(const []);

  @override
  Future<List<String>> pendingDeletes() async => _pendingDeletes ?? const [];

  @override
  Future<void> clearPendingDelete(String barcode) async {
    _cleared ??= [];
    _cleared!.add(barcode);
  }

  bool wasCleared(String barcode) => _cleared?.contains(barcode) ?? false;

  /// Returns all barcodes that were cleared (for test assertions).
  List<String> get clearedBarcodes => _cleared ?? const [];
}

/// A [CatalogSyncClient] with controllable [push] behavior.
/// Pass [pushFn] to override push with a custom behavior (e.g. throw an
/// exception); otherwise [pushResponse] is returned.
class TestSyncClient extends CatalogSyncClient {
  TestSyncClient({
    required this.pushResponse,
    this.pushFn,
    super.baseUrl = 'https://example.com',
    super.token = 'test-token',
    super.deviceId = 'test-device',
  });

  final SyncResult pushResponse;
  final Future<SyncResult> Function({
    required List<CatalogEntry> entries,
    required List<String> deleted,
    required int lastSyncedAt,
  })? pushFn;

  @override
  Future<SyncResult> push({
    required List<CatalogEntry> entries,
    required List<String> deleted,
    required int lastSyncedAt,
  }) async {
    if (pushFn != null) {
      return pushFn!(entries: entries, deleted: deleted, lastSyncedAt: lastSyncedAt);
    }
    return pushResponse;
  }
}

/// A mock for the full [CatalogRepository] interface.
class MockCatalogRepository extends Mock implements CatalogRepository {
  MockCatalogRepository();
}

/// A mock for the delta-sync subset of the repository interface.
class MockCatalogDeltaRepository extends Mock implements CatalogDeltaRepository {
  MockCatalogDeltaRepository();
}

/// A mock of [CatalogSyncClient].
class MockCatalogSyncClient extends Mock implements CatalogSyncClient {
  MockCatalogSyncClient();
}

/// A test config with in-memory store (stand-in for [Config] static class).
class TestConfig {
  final Map<String, String> _prefs = {};

  String? get shopKey => _prefs['shop_key'];
  String? get businessName => _prefs['business_name'];
  List<String> get shopList =>
      (_prefs['shop_list'] ?? '').split(',').where((s) => s.isNotEmpty).toList();

  void setShopKey(String v) => _prefs['shop_key'] = v;
  void setBusinessName(String v) => _prefs['business_name'] = v;
  void setShopList(List<String> v) => _prefs['shop_list'] = v.join(',');
  void clear() => _prefs.clear();
}

/// Clear all mock call records and reset stubs so one test never leaks
/// stubs into another.
void resetMocks({
  MockCatalogRepository? repository,
  MockCatalogDeltaRepository? deltaRepo,
  MockCatalogSyncClient? client,
}) {
  if (repository != null) reset(repository);
  if (deltaRepo != null) reset(deltaRepo);
  if (client != null) reset(client);
}

/// Convenience matcher that a repo is non-null.
Matcher isNotNullRepo() => isA<CatalogRepository>();
