import '../data/catalog_sync_client.dart';
import '../data/settings_service.dart';
import '../data/sync_config.dart';

/// Outcome of a publish.
class CatalogPublishResult {
  final bool ok;
  final int oldVersion;
  final int newVersion;
  final String? error;

  const CatalogPublishResult._({
    required this.ok,
    required this.oldVersion,
    required this.newVersion,
    this.error,
  });

  factory CatalogPublishResult.success({
    required int oldVersion,
    required int newVersion,
  }) =>
      CatalogPublishResult._(
        ok: true,
        oldVersion: oldVersion,
        newVersion: newVersion,
      );

  factory CatalogPublishResult.failure(int oldVersion, String error) =>
      CatalogPublishResult._(
        ok: false,
        oldVersion: oldVersion,
        newVersion: oldVersion,
        error: error,
      );

  bool get changed => ok && newVersion != oldVersion;
}

/// Admin-only publish (« Publish changes »).
///
/// Pushing local changes creates a new server generation. The local generation
/// is then advanced to the server's global version so the next distribution
/// targets it. If the push fails the local generation is left untouched.
class CatalogPublishService {
  final SettingsService _settings;
  final CatalogSyncClientFactory _clientFactory;

  CatalogPublishService({
    SettingsService? settings,
    CatalogSyncClientFactory? clientFactory,
  })  : _settings = settings ?? const ConfigSettingsService(),
        _clientFactory = clientFactory ?? SyncConfig.defaultClient;

  /// [push] performs the actual `POST /v1/sync` (injected so the caller owns
  /// the sync state and its user-facing message).
  Future<CatalogPublishResult> publish({
    required Future<bool> Function() push,
  }) async {
    final oldVersion = await _settings.getCatalogVersion();
    try {
      final pushed = await push();
      if (!pushed) {
        return CatalogPublishResult.failure(oldVersion, 'push rejected');
      }
      final client = await _clientFactory();
      try {
        final newVersion = await client.catalogVersion();
        if (newVersion > oldVersion) {
          await _settings.setCatalogVersion(newVersion);
        }
        return CatalogPublishResult.success(
          oldVersion: oldVersion,
          newVersion: newVersion,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      return CatalogPublishResult.failure(oldVersion, '$e');
    }
  }
}
