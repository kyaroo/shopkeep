import 'package:myhanout/data/catalog_sync_client.dart';

/// Reports the catalog version of a shop to the server.
///
/// The server is the single source of truth for catalog versions: when the
/// admin pushes a delta to a shop, it records the target version so the
/// server (not the device) knows which generation each shop is on.
class CatalogVersionService {
  final CatalogSyncClient _client;

  CatalogVersionService(this._client);

  /// Records that [shopKey] is now at [version] of the catalog.
  /// Best-effort: the admin reports the version after pushing a delta.
  Future<void> report(String shopKey, int version) async {
    await _client.setCatalogVersion(shopKey, version);
  }
}
