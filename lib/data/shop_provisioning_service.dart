import '../data/config.dart';
import '../data/provisioning.dart';
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
  }) async {
    final baseKey = (key == null || key.trim().isEmpty)
        ? slugify(name)
        : slugify(key);
    final finalKey = baseKey.isEmpty ? 'shop' : baseKey;

    final existing = await Config.getShopList();
    if (existing.contains(finalKey)) {
      throw const DuplicateShopKeyException();
    }

    await Config.addShop(finalKey, name);
    await Config.setCurrentShopKey(finalKey);
    await Config.saveBusinessName(name);
    await Config.saveShopBusinessName(finalKey, name);

    if (registerOnServer) {
      try {
        final client = await SyncConfig.defaultClient();
        await client.registerShop(finalKey, name);
        client.close();
      } catch (_) {
        // Server may be unreachable; local shop still created.
      }
    }
    return finalKey;
  }

  /// Builds the signed provisioning QR payload for a shop.
  ///
  /// [ttlSeconds] travels INSIDE the token (B4): the receiving device reads it
  /// and decides how long the code stays valid, so one shop can be given a
  /// 30-minute code and another a 7-day one without a server round-trip.
  static String buildProvisioningToken(String shopKey, String businessName,
      {int ttlSeconds = defaultProvisioningTtlSeconds}) {
    final payload = {
      'shop_key': shopKey,
      'business_name': businessName,
      'issued_at': DateTime.now().millisecondsSinceEpoch,
      'nonce': Provisioning.generateShopKey(length: 8),
      'ttl_seconds': ttlSeconds,
    };
    return Provisioning.sign(payload);
  }
}

/// Default QR validity when the caller does not choose one (30 minutes).
const int defaultProvisioningTtlSeconds = 1800;

/// The TTL choices offered when generating a provisioning QR.
/// Key = `ttl_seconds` placed in the token, value = i18n key.
const Map<int, String> provisioningTtlChoices = {
  1800: 'ttl30min',
  3600: 'ttl1h',
  86400: 'ttl1d',
  604800: 'ttl7d',
};
