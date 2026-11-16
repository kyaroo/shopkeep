import '../data/provisioning.dart';
import '../utils/app_log.dart';
import '../data/settings_service.dart';
import '../data/sync_config.dart';
import '../data/catalog_sync_client.dart';
import '../utils/slug.dart';

/// Thrown when a shop key already exists.
class DuplicateShopKeyException implements Exception {
  const DuplicateShopKeyException();
}

/// Single source of truth for creating a shop (persistence + server
/// registration + provisioning token). Used by both admin setup and shop entry
/// so key generation and registration stay consistent.
class ShopProvisioningService {
  ShopProvisioningService._();

  /// Creates a shop and returns its final shop key.
  /// Throws [DuplicateShopKeyException] if the key already exists.
  static Future<String> createShop({
    required String name,
    String? key,
    bool registerOnServer = true,
    SettingsService? settings,
    CatalogSyncClientFactory? clientFactory,
  }) async {
    final baseKey = (key == null || key.trim().isEmpty)
        ? slugify(name)
        : slugify(key);
    final finalKey = baseKey.isEmpty ? 'shop' : baseKey;

    final store = settings ?? const ConfigSettingsService();
    final existing = await store.getShopList();
    if (existing.contains(finalKey)) {
      throw const DuplicateShopKeyException();
    }

    await store.addShop(finalKey, name);
    await store.setCurrentShopKey(finalKey);
    await store.saveBusinessName(name);
    await store.saveShopBusinessName(finalKey, name);

    if (registerOnServer) {
      try {
        final client = await (clientFactory ?? SyncConfig.defaultClient)();
        await client.registerShop(finalKey, name);
        client.close();
      } catch (e) {
        // Server may be unreachable; local shop still created.
        logWarning('shop registration on server failed', error: e);
      }
    }
    return finalKey;
  }

  /// Builds the signed provisioning QR envelope for a shop.
  ///
  /// [signerId] must be in the directory with a role allowed to provision
  /// (founder / admin / salesman); [privateSeed] is that signer's key.
  /// [ttlSeconds] travels INSIDE the token (B4), so one shop can be given a
  /// 30-minute code and another a 7-day one without a server round-trip.
  static Future<String> buildProvisioningToken(
    String shopKey,
    String businessName, {
    required String signerId,
    required List<int> privateSeed,
    int ttlSeconds = defaultProvisioningTtlSeconds,
  }) =>
      Provisioning.buildProvisioningToken(
        shopKey,
        businessName,
        signerId: signerId,
        privateSeed: privateSeed,
        ttlSeconds: ttlSeconds,
      );
}

/// The TTL choices offered when generating a provisioning QR.
/// Key = `ttl_seconds` placed in the token, value = i18n key.
const Map<int, String> provisioningTtlChoices = {
  1800: 'ttl30min',
  3600: 'ttl1h',
  86400: 'ttl1d',
  604800: 'ttl7d',
};
