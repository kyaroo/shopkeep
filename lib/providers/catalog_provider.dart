import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/catalog_entry.dart';
import '../data/catalog_db.dart';
import '../data/sync_config.dart';
import '../data/sync_service.dart';

/// App-wide catalog state. UI talks to this; this talks to [CatalogRepository].
/// Swapping SQLite for the remote API later changes only the repository the
/// constructor receives — no UI or provider logic changes.
class CatalogProvider with ChangeNotifier {
  final CatalogRepository _repo;
  final CatalogDeltaRepository _deltaRepo;
  final SyncService _sync;
  List<CatalogEntry> _entries = [];
  bool _loading = false;
  String _search = '';

  /// [repo] is the catalog SSOT; [deltaRepo] is the delta-sync capability
  /// used by [syncNow] (DA-3: typed to the protocol, no runtime cast).
  /// Both default to the shared [CatalogDb] singleton. A provided [repo]
  /// that itself implements [CatalogDeltaRepository] is reused for delta
  /// sync when [deltaRepo] is omitted.
  CatalogProvider(
      {CatalogRepository? repo,
      CatalogDeltaRepository? deltaRepo,
      SyncService? sync})
      : _repo = repo ?? CatalogDb.instance,
        _deltaRepo = _resolveDeltaRepo(repo, deltaRepo),
        _sync = sync ?? SyncService();

  /// Picks the delta-sync capability: an explicit [deltaRepo] wins; a [repo]
  /// that itself implements [CatalogDeltaRepository] is reused; otherwise the
  /// shared [CatalogDb] singleton (which implements both protocols).
  static CatalogDeltaRepository _resolveDeltaRepo(
          CatalogRepository? repo, CatalogDeltaRepository? deltaRepo) =>
      deltaRepo ??
      switch (repo) {
        final CatalogDeltaRepository d => d,
        _ => CatalogDb.instance,
      };

  List<CatalogEntry> get entries => _entries;
  bool get loading => _loading;

  Future<void> init() => load();

  Future<void> load({String? search}) async {
    _search = search ?? _search;
    _loading = true;
    notifyListeners();
    _entries = await _repo.all(search: _search);
    _loading = false;
    notifyListeners();
  }

  Future<CatalogEntry?> get(String barcode) => _repo.get(barcode);

  /// Resolves a barcode against the server catalog, caches the result locally
  /// (so a later scan of the same barcode works offline), and returns the
  /// canonical fields for prefilling the capture form. Returns null on miss
  /// or any network/config error — the Mapper still works fully offline.
  ///
  /// This does NOT create an owner entry; it only seeds a local cache row and
  /// a prefill. The owner still taps Save to author it (origin=owner).
  Future<Map<String, dynamic>?> resolveFromServer(String barcode) async {
    final config = _sync.syncConfig ?? await SyncConfig.load();
    if (!config.isConfigured) return null;
    final client = config.client();
    try {
      final row = await client.resolve(barcode);
      client.close();
      if (row == null) return null;
      // Cache locally so the next scan of this barcode is offline-available.
      // Store as a source-derived entry; origin is implied by absence of an
      // owner row for the same barcode (read merge on the server, local cache
      // here is best-effort and overwritten by any owner save).
      final now = DateTime.now().millisecondsSinceEpoch;
      final cached = CatalogEntry(
        barcode: barcode,
        name: (row['name'] as String?)?.trim() ?? '',
        nameAr: _strOrNull(row['name_ar']),
        nameEn: _strOrNull(row['name_en']),
        category: _strOrNull(row['category']),
        createdAt: now,
        updatedAt: (row['updated_at'] as num?)?.toInt() ?? now,
      );
      if (cached.name.isNotEmpty) {
        await _repo.upsert(cached);
        await load();
      }
      return {
        'name': cached.name,
        'name_ar': cached.nameAr,
        'name_en': cached.nameEn,
        'category': cached.category,
        'brand': row['brand'],
        'quantity_text': row['quantity_text'],
        'image_url': row['image_url'],
        'origin': row['origin'],
      };
    } on Exception {
      // Network down / auth / server error — stay offline, no crash.
      return null;
    }
  }

  static String? _strOrNull(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  /// Browses/searches the server catalog. Returns the raw result map
  /// {total, limit, offset, products:[...]} or null on any error/offline.
  /// Additive — does not touch local entries; the browse screen renders the
  /// server result directly.
  Future<Map<String, dynamic>?> browseServer({
    String q = '',
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    final config = _sync.syncConfig ?? await SyncConfig.load();
    if (!config.isConfigured) return null;
    final client = config.client();
    try {
      final result = await client.search(
        q: q,
        category: category,
        limit: limit,
        offset: offset,
      );
      client.close();
      return result;
    } on Exception {
      return null;
    }
  }

  /// Inserts or updates by barcode. Sets created_at/updated_at.
  /// [name] is the French/Latin primary; [nameAr] the Arabic script;
  /// [nameEn] only when it differs from [name] (null = same as French).
  Future<void> save({
    required String barcode,
    required String name,
    String? nameAr,
    String? nameEn,
    String? category,
    dynamic photo,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _repo.get(barcode);
    final entry = CatalogEntry(
      barcode: barcode,
      name: name.trim(),
      nameAr: (nameAr != null && nameAr.trim().isNotEmpty)
          ? nameAr.trim()
          : null,
      nameEn: (nameEn != null &&
              nameEn.trim().isNotEmpty &&
              nameEn.trim() != name.trim())
          ? nameEn.trim()
          : null,
      category: (category != null && category.trim().isNotEmpty)
          ? category.trim()
          : null,
      photo: photo ?? existing?.photo,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _repo.upsert(entry);
    await load();
  }

  Future<void> delete(String barcode) async {
    await _repo.delete(barcode);
    await load();
  }

  bool get configured {
    final c = _sync.syncConfig;
    return c != null && c.isConfigured;
  }

  /// Read-only local browse (no network). Returns the same shape as
  /// [browseServer] so BrowsePage can render either source.
  Future<Map<String, dynamic>?> browseLocal({
    String q = '',
    int limit = 50,
    int offset = 0,
  }) async {
    await _repo.init();
    final entries = await _repo.all(search: q, limit: limit, offset: offset);
    final total = await _repo.count(search: q);
    return {
      'total': total,
      'limit': limit,
      'offset': offset,
      'products': entries
          .map((e) => {
                'barcode': e.barcode,
                'name': e.name,
                'name_ar': e.nameAr,
                'name_en': e.nameEn,
                'category': e.category,
                'origin': 'local',
                'image_url': null,
                // Local catalog photo (already downscaled to <=128px by
                // processPhoto). Null when the entry has none.
                'photo_base64':
                    e.photo == null ? null : base64Encode(e.photo!),
              })
          .toList(),
    };
  }

  Future<int> count() => _repo.count();

  // ---- sync (on-demand only) -------------------------------------------

  Future<void> loadSyncConfig() async {
    await _sync.loadSyncConfig();
    notifyListeners();
  }

  Future<void> saveSyncConfig(SyncConfig config) async {
    await _sync.saveSyncConfig(config);
    notifyListeners();
  }

  /// Delegates to [SyncService]; the sync state lives there.
  Future<bool> syncNow() async {
    final config = _sync.syncConfig ?? await SyncConfig.load();
    return _sync.syncNow(repo: _deltaRepo, config: config, entries: _entries);
  }
}
