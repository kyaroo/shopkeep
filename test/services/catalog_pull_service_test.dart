// Phase 1 — admin pull: multi-generation diff, one transaction, version
// advance only on full success.
//
// The HTTP client is faked (no network); the repository is an in-memory
// [TransactionalCatalogRepository] that records how many atomic applies
// happened and can be told to fail.
//
// Run: flutter test test/services/catalog_pull_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_pull_service.dart';

import '../helpers/fake_settings.dart';

CatalogEntry _entry(String barcode, {int version = 2}) => CatalogEntry(
      barcode: barcode,
      name: 'Product $barcode',
      category: 'grocery',
      createdAt: 1,
      updatedAt: version,
    );

CatalogDiffChange _upsert(String barcode, int version) => CatalogDiffChange(
      version: version,
      barcode: barcode,
      op: 'upsert',
      row: _entry(barcode, version: version),
    );

CatalogDiffChange _delete(String barcode, int version) => CatalogDiffChange(
      version: version,
      barcode: barcode,
      op: 'delete',
      row: null,
    );

class _FakeClient extends CatalogSyncClient {
  final List<CatalogDiffPage> pages;
  final Object? failAtCall;

  _FakeClient(this.pages, {this.failAtCall})
      : super(baseUrl: '', token: '', deviceId: 'test');

  int _call = 0;
  final List<int> offsets = [];

  @override
  Future<CatalogDiffPage> catalogDiff({
    required int fromVersion,
    int limit = 100,
    int offset = 0,
  }) async {
    offsets.add(offset);
    if (failAtCall != null && _call + 1 == failAtCall) {
      _call++;
      throw SyncException('page $offset failed');
    }
    final page = pages[_call];
    _call++;
    return page;
  }

  @override
  void close() {}
}

class _FakeRepo implements TransactionalCatalogRepository {
  int applyCalls = 0;
  List<CatalogEntry> lastUpserts = const [];
  List<String> lastDeletes = const [];
  Object? failWith;
  final Map<String, CatalogEntry> rows = {};

  @override
  Future<void> applyDeltaAtomic({
    required List<CatalogEntry> upserts,
    required List<String> deletes,
  }) async {
    applyCalls++;
    lastUpserts = List<CatalogEntry>.of(upserts);
    lastDeletes = List<String>.of(deletes);
    if (failWith != null) throw failWith!;
    for (final e in upserts) {
      rows[e.barcode] = e;
    }
    for (final b in deletes) {
      rows.remove(b);
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => rows[barcode];

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async =>
      rows.values.toList();

  @override
  Future<void> upsert(CatalogEntry entry) async => rows[entry.barcode] = entry;

  @override
  Future<void> delete(String barcode) async => rows.remove(barcode);

  @override
  Future<int> count({String? search}) async => rows.length;
}

CatalogPullService _service(
  FakeSettingsService settings,
  _FakeRepo repo,
  _FakeClient client,
) =>
    CatalogPullService(
      settings: settings,
      repository: repo,
      clientFactory: () async => client,
    );

void main() {
  late FakeSettingsService settings;
  late _FakeRepo repo;

  setUp(() {
    settings = FakeSettingsService();
    repo = _FakeRepo();
  });

  test('pull applies every page in ONE transaction and advances the version',
      () async {
    settings.catalogVersion = 1;
    final client = _FakeClient([
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 3,
        limit: 2,
        offset: 0,
        nextOffset: 2,
        changes: [_upsert('A', 2), _upsert('B', 3)],
      ),
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 3,
        limit: 2,
        offset: 2,
        nextOffset: null,
        changes: [_delete('C', 3)],
      ),
    ]);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isTrue, reason: result.error);
    expect(result.applied, isTrue);
    expect(result.fromVersion, 1);
    expect(result.toVersion, 3);
    expect(result.upserts, 2);
    expect(result.deletes, 1);
    expect(settings.catalogVersion, 3);
    expect(repo.applyCalls, 1, reason: 'all pages must land in one transaction');
    expect(repo.lastUpserts.map((e) => e.barcode), ['A', 'B']);
    expect(repo.lastDeletes, ['C']);
    expect(client.offsets, [0, 2], reason: 'the diff must be paged');
  });

  test('a page failure leaves the catalog and the version untouched', () async {
    settings.catalogVersion = 1;
    final client = _FakeClient([
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 3,
        limit: 1,
        offset: 0,
        nextOffset: 1,
        changes: [_upsert('A', 2)],
      ),
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 3,
        limit: 1,
        offset: 1,
        nextOffset: null,
        changes: [_upsert('B', 3)],
      ),
    ], failAtCall: 2);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isFalse);
    expect(repo.applyCalls, 0, reason: 'nothing may be written on a fetch failure');
    expect(settings.catalogVersion, 1, reason: 'version must not advance');
  });

  test('an apply failure rolls back and leaves the version untouched', () async {
    settings.catalogVersion = 1;
    repo.failWith = StateError('disk full');
    final client = _FakeClient([
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 2,
        total: 1,
        limit: 100,
        offset: 0,
        nextOffset: null,
        changes: [_upsert('A', 2)],
      ),
    ]);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isFalse);
    expect(result.error, contains('disk full'));
    expect(settings.catalogVersion, 1);
  });

  test('last change wins per barcode (upsert then delete)', () async {
    settings.catalogVersion = 1;
    final client = _FakeClient([
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 2,
        limit: 100,
        offset: 0,
        nextOffset: null,
        changes: [_upsert('A', 2), _delete('A', 3)],
      ),
    ]);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isTrue, reason: result.error);
    expect(result.upserts, 0);
    expect(result.deletes, 1);
    expect(repo.lastDeletes, ['A']);
    expect(settings.catalogVersion, 3);
  });

  test('delete then upsert keeps the row (net upsert)', () async {
    settings.catalogVersion = 1;
    final client = _FakeClient([
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 2,
        limit: 100,
        offset: 0,
        nextOffset: null,
        changes: [_delete('A', 2), _upsert('A', 3)],
      ),
    ]);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isTrue, reason: result.error);
    expect(result.upserts, 1);
    expect(result.deletes, 0);
    expect(repo.lastUpserts.single.barcode, 'A');
  });

  test('up-to-date preview reports no changes and does not write', () async {
    settings.catalogVersion = 4;
    final client = _FakeClient([
      const CatalogDiffPage(
        fromVersion: 4,
        toVersion: 4,
        total: 0,
        limit: 100,
        offset: 0,
        nextOffset: null,
        changes: [],
      ),
    ]);

    final preview = await _service(settings, repo, client).preview();

    expect(preview.ok, isTrue);
    expect(preview.difference, 0);
    expect(preview.isEmpty, isTrue);
    expect(repo.applyCalls, 0);
  });

  test('preview counts upserts and deletes across pages', () async {
    settings.catalogVersion = 1;
    final client = _FakeClient([
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 3,
        limit: 2,
        offset: 0,
        nextOffset: 2,
        changes: [_upsert('A', 2), _delete('B', 2)],
      ),
      CatalogDiffPage(
        fromVersion: 1,
        toVersion: 3,
        total: 3,
        limit: 2,
        offset: 2,
        nextOffset: null,
        changes: [_upsert('C', 3)],
      ),
    ]);

    final preview = await _service(settings, repo, client).preview();

    expect(preview.ok, isTrue);
    expect(preview.fromVersion, 1);
    expect(preview.toVersion, 3);
    expect(preview.difference, 2);
    expect(preview.upserts, 2);
    expect(preview.deletes, 1);
    expect(repo.applyCalls, 0, reason: 'preview must not write');
  });

  test('a server generation behind the local one is refused', () async {
    settings.catalogVersion = 5;
    final client = _FakeClient([
      const CatalogDiffPage(
        fromVersion: 5,
        toVersion: 3,
        total: 0,
        limit: 100,
        offset: 0,
        nextOffset: null,
        changes: [],
      ),
    ]);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isFalse);
    expect(settings.catalogVersion, 5);
  });

  test('no changes but a newer generation still adopts the version', () async {
    settings.catalogVersion = 1;
    final client = _FakeClient([
      const CatalogDiffPage(
        fromVersion: 1,
        toVersion: 2,
        total: 0,
        limit: 100,
        offset: 0,
        nextOffset: null,
        changes: [],
      ),
    ]);

    final result = await _service(settings, repo, client).pull();

    expect(result.ok, isTrue);
    expect(result.applied, isFalse);
    expect(settings.catalogVersion, 2);
  });
}
