import 'package:flutter/material.dart';
import '../data/catalog_sync_client.dart';
import '../data/sync_config.dart';
import '../models/catalog_entry.dart';

/// Owns the sync state and the manual "Sync now" action.
///
/// Extracted from [CatalogProvider] so that the provider owns only the catalog
/// entries and their lifecycle, while sync is owned by its own observable
/// [ChangeNotifier].
///
/// [syncNow] is repo-agnostic: it accepts any [CatalogDeltaRepository], the
/// resolved sync config and the current local entry snapshot. DA-3 done: the
/// delta-capability protocol replaced the old `is CatalogDb` type check.
class SyncService extends ChangeNotifier {
  bool _syncing = false;
  String? _syncMessage;
  SyncConfig? _syncConfig;

  bool get syncing => _syncing;
  String? get syncMessage => _syncMessage;
  SyncConfig? get syncConfig => _syncConfig;

  /// Loads the persisted sync config (URL + token + watermark) from
  /// shared preferences. Called once at app startup.
  Future<void> loadSyncConfig() async {
    _syncConfig = await SyncConfig.load();
    notifyListeners();
  }

  /// Persists the user-edited sync config and updates the cached copy.
  Future<void> saveSyncConfig(SyncConfig config) async {
    await config.save();
    _syncConfig = config;
    notifyListeners();
  }

  /// Manual "Sync now". Pushes [entries] newer than the last watermark, plus
  /// pending tombstones. Never triggered automatically.
  ///
  /// [repo] must be a [CatalogDeltaRepository] (e.g. [CatalogDb]); the delta
  /// methods are used directly — no `is` type check.
  Future<bool> syncNow({
    required CatalogDeltaRepository repo,
    required SyncConfig config,
    required List<CatalogEntry> entries,
  }) async {
    if (config == null || !config.isConfigured) {
      _syncMessage = 'Sync not configured. Set the server URL and token first.';
      notifyListeners();
      return false;
    }

    _syncing = true;
    _syncMessage = null;
    notifyListeners();

    try {
      final changed = await repo.changedSince(config.lastSyncedAt);
      final deletes = await repo.pendingDeletes();

      final client = config.client();
      final result = await client.push(
        entries: changed,
        deleted: deletes,
        lastSyncedAt: config.lastSyncedAt,
      );
      client.close();

      // Advance the watermark and clear synced tombstones on success.
      config.lastSyncedAt = result.serverNow;
      await config.save();
      for (final b in deletes) {
        await repo.clearPendingDelete(b);
      }

      final parts = <String>['Synced ${result.accepted}'];
      if (deletes.isNotEmpty) parts.add('${deletes.length} deleted');
      if (result.newerOnServer.isNotEmpty) {
        parts.add('${result.newerOnServer.length} newer on server (kept)');
      }
      _syncMessage = parts.join(', ');
      notifyListeners();
      return true;
    } on SyncAuthException {
      _syncMessage = 'Sync failed: bad token or URL.';
      notifyListeners();
      return false;
    } on SyncException catch (e) {
      _syncMessage = 'Sync failed: ${e.message}';
      notifyListeners();
      return false;
    } catch (e) {
      _syncMessage = 'Sync failed: $e';
      notifyListeners();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }
}
