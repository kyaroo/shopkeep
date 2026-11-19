/// In-memory [SettingsService] for signer-import tests.
///
/// No SharedPreferences, no SQLite, no network. Tests inject it directly so a
/// throwaway trust anchor can be used without ever touching the real
/// `assets/signers.json` or the founder's real seeds.
library;

import 'package:myhanout/data/settings_service.dart';

class FakeSettingsService implements SettingsService {
  final List<String> shops = [];
  final Map<String, String> shopNames = {};
  final Map<String, List<int>> signerKeys = {};
  String currentShop = '';
  String businessName = 'Maison du Marché';
  int catalogVersion = 0;
  String? signersEnvelope;
  String? activeSignerId;
  final Map<String, String> provisioned = {};
  final Set<String> usedNonces = {};
  bool adminMode = false;

  @override
  Future<List<String>> getShopList() async => List.unmodifiable(shops);

  @override
  Future<void> addShop(String shopKey, String businessName) async {
    if (!shops.contains(shopKey)) shops.add(shopKey);
  }

  @override
  Future<void> removeShop(String shopKey) async => shops.remove(shopKey);

  @override
  Future<String> getCurrentShopKey() async => currentShop;

  @override
  Future<void> setCurrentShopKey(String key) async => currentShop = key;

  @override
  Future<String> getBusinessName() async => businessName;

  @override
  Future<void> saveBusinessName(String name) async => businessName = name;

  @override
  Future<String?> getShopBusinessName(String key) async => shopNames[key];

  @override
  Future<void> saveShopBusinessName(String key, String name) async =>
      shopNames[key] = name;

  @override
  Future<void> removeShopBusinessName(String key) async => shopNames.remove(key);

  @override
  Future<int> getCatalogVersion() async => catalogVersion;

  @override
  Future<void> setCatalogVersion(int value) async => catalogVersion = value;

  @override
  Future<String?> getSignersEnvelope() async => signersEnvelope;

  @override
  Future<void> saveSignersEnvelope(String value) async =>
      signersEnvelope = value;

  @override
  Future<String?> getProvisionedBy(String shopKey) async =>
      provisioned['$shopKey:name'];

  @override
  Future<String?> getProvisionedById(String shopKey) async =>
      provisioned['$shopKey:id'];

  @override
  Future<void> saveProvisionedBy(
      String shopKey, String name, String signerId) async {
    provisioned['$shopKey:name'] = name;
    provisioned['$shopKey:id'] = signerId;
  }

  @override
  Future<bool> isNonceUsed(String nonce) async => usedNonces.contains(nonce);

  @override
  Future<void> markNonceUsed(String nonce, Duration ttl) async =>
      usedNonces.add(nonce);

  @override
  Future<List<int>?> getSignerKey(String signerId) async =>
      signerKeys[signerId] == null ? null : List.unmodifiable(signerKeys[signerId]!);

  @override
  Future<void> saveSignerKey(String signerId, List<int> seed) async =>
      signerKeys[signerId] = List.unmodifiable(seed);

  @override
  Future<String?> getActiveSignerId() async => activeSignerId;

  @override
  Future<void> setActiveSignerId(String value) async => activeSignerId = value;

  @override
  Future<bool> getAdminMode() async => adminMode;

  @override
  Future<void> setAdminMode(bool value) async => adminMode = value;
}
