import '../data/catalog_db.dart';
import '../data/catalog_delta.dart';
import '../data/catalog_sync_client.dart';
import '../data/settings_service.dart';
import '../data/sync_config.dart';
import '../models/catalog_entry.dart';

/// The full multi-generation diff between two catalog generations.
///
/// [changes] keeps the server's stable `(version, barcode)` order; use
/// [folded] for the last-writer-wins view the delta builder needs.
class CatalogDiffRange {
  final int fromVersion;
  final int toVersion;
  final int total;
  final List<CatalogDiffChange> changes;

  const CatalogDiffRange({
    required this.fromVersion,
    required this.toVersion,
    required this.total,
    required this.changes,
  });

  /// How many generations the range spans (`to - from`).
  int get difference => toVersion - fromVersion;

  /// Last change wins per barcode, in first-seen order.
  List<CatalogDiffChange> get folded {
    final byBarcode = <String, CatalogDiffChange>{};
    for (final c in changes) {
      byBarcode[c.barcode] = c;
    }
    return byBarcode.values.toList();
  }
}

/// Fetches **every** page of `GET /v1/catalog/diff` from [fromVersion] up to
/// the server's latest generation. Throws [SyncException] on any page failure;
/// the caller decides what to do (the pull path leaves the local catalog and
/// its version untouched).
Future<CatalogDiffRange> fetchCatalogDiff(
  CatalogSyncClient client, {
  required int fromVersion,
  int limit = 100,
}) async {
  var offset = 0;
  var toVersion = fromVersion;
  var total = 0;
  final changes = <CatalogDiffChange>[];
  while (true) {
    final page = await client.catalogDiff(
      fromVersion: fromVersion,
      limit: limit,
      offset: offset,
    );
    if (page.fromVersion != fromVersion) {
      throw SyncException('catalog diff from_version ${page.fromVersion} '
          'does not match requested $fromVersion');
    }
    if (page.toVersion < fromVersion) {
      throw SyncException('catalog diff to_version ${page.toVersion} is '
          'behind from_version $fromVersion');
    }
    toVersion = page.toVersion;
    total = page.total;
    changes.addAll(page.changes);

    final next = page.nextOffset ?? (offset + page.changes.length);
    if (page.changes.isEmpty || next <= offset) break;
    offset = next;
    if (total > 0 && offset >= total) break;
  }
  return CatalogDiffRange(
    fromVersion: fromVersion,
    toVersion: toVersion,
    total: total,
    changes: changes,
  );
}

/// Read-only outcome of a pull preview: what a confirmation dialog shows
/// before anything is written.
class CatalogPullPreview {
  final bool ok;
  final int fromVersion;
  final int toVersion;
  final int total;
  final int upserts;
  final int deletes;
  final String? error;

  const CatalogPullPreview._({
    required this.ok,
    required this.fromVersion,
    required this.toVersion,
    required this.total,
    required this.upserts,
    required this.deletes,
    this.error,
  });

  factory CatalogPullPreview.fromRange(CatalogDiffRange range) {
    final folded = range.folded;
    final deletes = folded.where((c) => c.isDelete).length;
    return CatalogPullPreview._(
      ok: true,
      fromVersion: range.fromVersion,
      toVersion: range.toVersion,
      total: range.total,
      upserts: folded.length - deletes,
      deletes: deletes,
    );
  }

  factory CatalogPullPreview.failure(int fromVersion, Object error) =>
      CatalogPullPreview._(
        ok: false,
        fromVersion: fromVersion,
        toVersion: fromVersion,
        total: 0,
        upserts: 0,
        deletes: 0,
        error: '$error',
      );

  int get difference => toVersion - fromVersion;
  bool get isEmpty => upserts == 0 && deletes == 0;
}

/// Outcome of an applied pull.
class CatalogPullResult {
  final bool ok;
  final bool applied;
  final int fromVersion;
  final int toVersion;
  final int upserts;
  final int deletes;
  final String? error;

  const CatalogPullResult._({
    required this.ok,
    required this.applied,
    required this.fromVersion,
    required this.toVersion,
    required this.upserts,
    required this.deletes,
    this.error,
  });

  factory CatalogPullResult.success({
    required int fromVersion,
    required int toVersion,
    required int upserts,
    required int deletes,
    required bool applied,
  }) =>
      CatalogPullResult._(
        ok: true,
        applied: applied,
        fromVersion: fromVersion,
        toVersion: toVersion,
        upserts: upserts,
        deletes: deletes,
      );

  factory CatalogPullResult.failure(int fromVersion, int toVersion,
          Object error) =>
      CatalogPullResult._(
        ok: false,
        applied: false,
        fromVersion: fromVersion,
        toVersion: toVersion,
        upserts: 0,
        deletes: 0,
        error: '$error',
      );
}

/// Admin-only catalog pull (« Update catalog »).
///
/// Fetches the server diff from the **local** generation, applies every page
/// in ONE transaction, and advances the local generation to `to_version` only
/// after the whole diff landed. On any failure the local catalog and its
/// version are left exactly as they were.
///
/// Manual only: nothing here schedules or auto-triggers a pull.
class CatalogPullService {
  final SettingsService _settings;
  final TransactionalCatalogRepository _repository;
  final CatalogSyncClientFactory _clientFactory;

  CatalogPullService({
    SettingsService? settings,
    TransactionalCatalogRepository? repository,
    CatalogSyncClientFactory? clientFactory,
  })  : _settings = settings ?? const ConfigSettingsService(),
        _repository = repository ?? CatalogDb.instance,
        _clientFactory = clientFactory ?? SyncConfig.defaultClient;

  /// Fetches the diff without writing anything (dialog data).
  Future<CatalogPullPreview> preview() async {
    final from = await _settings.getCatalogVersion();
    final client = await _clientFactory();
    try {
      return CatalogPullPreview.fromRange(
          await fetchCatalogDiff(client, fromVersion: from));
    } catch (e) {
      return CatalogPullPreview.failure(from, e);
    } finally {
      client.close();
    }
  }

  /// Fetches and applies the whole diff, then advances the local generation.
  Future<CatalogPullResult> pull() async {
    final from = await _settings.getCatalogVersion();
    final client = await _clientFactory();
    final CatalogDiffRange range;
    try {
      range = await fetchCatalogDiff(client, fromVersion: from);
    } catch (e) {
      client.close();
      return CatalogPullResult.failure(from, from, e);
    }
    client.close();

    if (range.toVersion < from) {
      return CatalogPullResult.failure(
          from, range.toVersion, 'server generation ${range.toVersion} is '
          'behind the local generation $from');
    }

    final folded = range.folded;
    final upserts = <CatalogEntry>[];
    final deletes = <String>[];
    for (final c in folded) {
      if (c.isDelete) {
        deletes.add(c.barcode);
      } else if (c.row != null) {
        upserts.add(c.row!);
      }
    }

    // No rows to apply: still adopt the server generation so the next pull
    // starts from it.
    if (upserts.isEmpty && deletes.isEmpty) {
      if (range.toVersion == from) {
        return CatalogPullResult.success(
            fromVersion: from,
            toVersion: from,
            upserts: 0,
            deletes: 0,
            applied: false);
      }
      await _settings.setCatalogVersion(range.toVersion);
      return CatalogPullResult.success(
          fromVersion: from,
          toVersion: range.toVersion,
          upserts: 0,
          deletes: 0,
          applied: false);
    }

    try {
      await _repository.applyDeltaAtomic(upserts: upserts, deletes: deletes);
    } catch (e) {
      return CatalogPullResult.failure(from, range.toVersion, e);
    }

    // Only now is the local generation allowed to move.
    await _settings.setCatalogVersion(range.toVersion);
    return CatalogPullResult.success(
      fromVersion: from,
      toVersion: range.toVersion,
      upserts: upserts.length,
      deletes: deletes.length,
      applied: true,
    );
  }
}
