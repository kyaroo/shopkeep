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
  static String buildProvisioningToken(String shopKey, String businessName) {
    final payload = {
      'shop_key': shopKey,
      'business_name': businessName,
      'issued_at': DateTime.now().millisecondsSinceEpoch,
      'nonce': Provisioning.generateShopKey(length: 8),
    };
    return Provisioning.sign(payload);
  }
}
