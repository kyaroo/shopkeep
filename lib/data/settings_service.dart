import 'config.dart';

/// Injectable access to the app's persisted settings.
///
/// `Config` remains the static `SharedPreferences` implementation: bootstrap
/// code in `main()` needs it before any widget exists, and `CatalogSeedLoader`
/// needs it while the database is being created. Everything above that layer
/// (screens, services) receives a [SettingsService] instead of touching the
/// global, so the storage can be swapped in tests (architecture rules 15/33).
abstract class SettingsService {
  Future<List<String>> getShopList();
  Future<void> addShop(String shopKey, String businessName);
  Future<void> removeShop(String shopKey);

  Future<String> getCurrentShopKey();
  Future<void> setCurrentShopKey(String key);

  Future<String> getBusinessName();
  Future<void> saveBusinessName(String name);

  Future<String?> getShopBusinessName(String key);
  Future<void> saveShopBusinessName(String key, String name);
  Future<void> removeShopBusinessName(String key);

  /// Installed catalog generation (the `.myhanout` base-version guard).
  Future<int> getCatalogVersion();
  Future<void> setCatalogVersion(int value);

  /// Scanned signers-directory override (verbatim envelope).
  Future<String?> getSignersEnvelope();
  Future<void> saveSignersEnvelope(String value);

  /// Who provisioned a shop (attribution).
  Future<String?> getProvisionedBy(String shopKey);
  Future<String?> getProvisionedById(String shopKey);
  Future<void> saveProvisionedBy(String shopKey, String name, String signerId);

  /// Provisioning nonce replay guard.
  Future<bool> isNonceUsed(String nonce);
  Future<void> markNonceUsed(String nonce, Duration ttl);

  /// This device's own signer keypair.
  Future<List<int>?> getSignerKey(String signerId);
  Future<void> saveSignerKey(String signerId, List<int> seed);
  Future<String?> getActiveSignerId();
  Future<void> setActiveSignerId(String value);

  Future<bool> getAdminMode();
  Future<void> setAdminMode(bool value);
}

/// Production [SettingsService]: delegates to the static [Config] store.
class ConfigSettingsService implements SettingsService {
  const ConfigSettingsService();

  @override
  Future<List<String>> getShopList() => Config.getShopList();

  @override
  Future<void> addShop(String shopKey, String businessName) =>
      Config.addShop(shopKey, businessName);

  @override
  Future<void> removeShop(String shopKey) => Config.removeShop(shopKey);

  @override
  Future<String> getCurrentShopKey() => Config.getCurrentShopKey();

  @override
  Future<void> setCurrentShopKey(String key) => Config.setCurrentShopKey(key);

  @override
  Future<String> getBusinessName() => Config.getBusinessName();

  @override
  Future<void> saveBusinessName(String name) => Config.saveBusinessName(name);

  @override
  Future<String?> getShopBusinessName(String key) =>
      Config.getShopBusinessName(key);

  @override
  Future<void> saveShopBusinessName(String key, String name) =>
      Config.saveShopBusinessName(key, name);

  @override
  Future<void> removeShopBusinessName(String key) =>
      Config.removeShopBusinessName(key);

  @override
  Future<int> getCatalogVersion() => Config.getCatalogVersion();

  @override
  Future<void> setCatalogVersion(int value) => Config.setCatalogVersion(value);

  @override
  Future<String?> getSignersEnvelope() => Config.getSignersEnvelope();

  @override
  Future<void> saveSignersEnvelope(String value) =>
      Config.saveSignersEnvelope(value);

  @override
  Future<String?> getProvisionedBy(String shopKey) =>
      Config.getProvisionedBy(shopKey);

  @override
  Future<String?> getProvisionedById(String shopKey) =>
      Config.getProvisionedById(shopKey);

  @override
  Future<void> saveProvisionedBy(
          String shopKey, String name, String signerId) =>
      Config.saveProvisionedBy(shopKey, name, signerId);

  @override
  Future<bool> isNonceUsed(String nonce) => Config.isNonceUsed(nonce);

  @override
  Future<void> markNonceUsed(String nonce, Duration ttl) =>
      Config.markNonceUsed(nonce, ttl);

  @override
  Future<List<int>?> getSignerKey(String signerId) =>
      Config.getSignerKey(signerId);

  @override
  Future<void> saveSignerKey(String signerId, List<int> seed) =>
      Config.saveSignerKey(signerId, seed);

  @override
  Future<String?> getActiveSignerId() => Config.getActiveSignerId();

  @override
  Future<void> setActiveSignerId(String value) =>
      Config.setActiveSignerId(value);

  @override
  Future<bool> getAdminMode() => Config.getAdminMode();

  @override
  Future<void> setAdminMode(bool value) => Config.setAdminMode(value);
}
