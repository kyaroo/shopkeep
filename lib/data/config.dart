import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_log.dart';

/// Application configuration persistence layer.
///
/// Shared by both APKs (admin + shop). On Android, each APK has its own
/// `shared_preferences` namespace, so data never bleeds between them.
///
/// Key design:
/// - `shop_list`: JSON array of all shop keys ever created (admin-managed)
/// - `shop_key`: currently active shop (selected by the shopkeeper or admin)
/// - `business_name`: display name shown above the app (optional per shop)
class Config {
  static const _shopList = 'shop_list';
  static const _shopKey = 'shop_key';
  static const _businessName = 'business_name';
  static const _adminMode = 'admin_mode';

  static SharedPreferences? _instance;

  static Future<void> init() async {
    _instance = await SharedPreferences.getInstance();
  }

  // ---- Shop list (admin-managed) ----

  static List<String>? _cachedShopList;
  static Map<String, String>? _cachedShopNames;

  static Future<List<String>> getShopList() async {
    if (_cachedShopList != null) return List<String>.from(_cachedShopList!);
    final prefs = _instance;
    if (prefs == null) return [];
    final raw = prefs.getStringList(_shopList);
    _cachedShopList = raw?.where((s) => s.isNotEmpty).toList() ?? [];
    return List<String>.from(_cachedShopList!);
  }

  static Future<void> addShop(String shopKey, String businessName) async {
    final prefs = _instance;
    if (prefs == null) return;
    final list = await getShopList();
    if (!list.contains(shopKey)) {
      list.add(shopKey);
      await prefs.setStringList(_shopList, list);
      _cachedShopList = List<String>.from(list);
    }
  }

  static Future<void> removeShop(String shopKey) async {
    final prefs = _instance;
    if (prefs == null) return;
    final list = await getShopList();
    final updated = list.where((s) => s != shopKey).toList();
    await prefs.setStringList(_shopList, updated);
    _cachedShopList = List<String>.from(updated);
  }

  static Future<void> clearShopList() async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.remove(_shopList);
    _cachedShopList = <String>[];
  }

  // ---- Current shop (shopkeeper-selected) ----

  static Future<String> getCurrentShopKey() async {
    final prefs = _instance;
    if (prefs == null) return 'default';
    return prefs.getString(_shopKey) ?? 'default';
  }

  static Future<void> setCurrentShopKey(String key) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setString(_shopKey, key);
  }

  // ---- Business name (displayed above the app) ----

  static Future<String> getBusinessName() async {
    final prefs = _instance;
    if (prefs == null) return 'Maison du Marché';
    return prefs.getString(_businessName) ?? 'Maison du Marché';
  }

  static Future<void> saveBusinessName(String name) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setString(_businessName, name);
  }

  static const _shopNames = 'shop_names';
  static const _shopId = 'shop_id';

  /// Per-shop random id. Catalog delta files (`.myhanout`) and QR codes are
  /// bound to it, so one shop's payload cannot update another shop.
  static Future<String> getShopId() async {
    final prefs = _instance;
    if (prefs == null) return '';
    return prefs.getString(_shopId) ?? '';
  }

  static Future<void> setShopId(String value) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setString(_shopId, value);
  }

  // ---- Catalog version (base-version guard for `.myhanout` deltas) ----

  static const _catalogVersion = 'catalog_version';

  /// Version of the catalog snapshot installed on this device.
  ///
  /// Starts at the bundled seed's version and advances every time a
  /// `.myhanout` delta is applied. A delta whose `base_version` differs is
  /// rejected as stale, so an out-of-order or cross-generation bundle can
  /// never half-apply.
  static Future<int> getCatalogVersion() async =>
      _instance?.getInt(_catalogVersion) ?? 0;

  static Future<void> setCatalogVersion(int value) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setInt(_catalogVersion, value);
  }

  // ---- Signers directory (trust material, QR-distributed) ----

  static const _signersEnvelope = 'signers_envelope';

  /// The scanned directory override, persisted verbatim. Re-verified against
  /// the baked root key on every load — a tampered store must never win.
  static Future<String?> getSignersEnvelope() async =>
      _instance?.getString(_signersEnvelope);

  static Future<void> saveSignersEnvelope(String value) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setString(_signersEnvelope, value);
  }

  // ---- Provisioning attribution ----

  static const _provisionedBy = 'provisioned_by';

  /// `shopKey → {"name": …, "id": …}` — who joined/provisioned the shop.
  static Future<String?> getProvisionedBy(String shopKey) async {
    final raw = _instance?.getString(_provisionedBy);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[shopKey];
      if (entry is Map) return '${entry['name'] ?? ''}';
    } catch (_) {}
    return null;
  }

  static Future<String?> getProvisionedById(String shopKey) async {
    final raw = _instance?.getString(_provisionedBy);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[shopKey];
      if (entry is Map) return '${entry['id'] ?? ''}';
    } catch (_) {}
    return null;
  }

  static Future<void> saveProvisionedBy(
    String shopKey,
    String name,
    String signerId,
  ) async {
    final prefs = _instance;
    if (prefs == null) return;
    final raw = prefs.getString(_provisionedBy);
    Map<String, dynamic> map = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    map[shopKey] = {'name': name, 'id': signerId};
    await prefs.setString(_provisionedBy, jsonEncode(map));
  }

  // ---- Provisioning nonce replay guard ----

  static const _usedNonces = 'used_nonces';

  static List<Map<String, dynamic>> _readNonces() {
    final raw = _instance?.getString(_usedNonces);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isNonceUsed(String nonce) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _readNonces().any((e) =>
        e['nonce'] == nonce && (e['expires_at'] as int? ?? 0) > now);
  }

  static Future<void> markNonceUsed(String nonce, Duration ttl) async {
    final prefs = _instance;
    if (prefs == null) return;
    final now = DateTime.now();
    final rows = _readNonces()
        .where((e) => (e['expires_at'] as int? ?? 0) > now.millisecondsSinceEpoch)
        .toList();
    rows.add({
      'nonce': nonce,
      'expires_at': now.add(ttl).millisecondsSinceEpoch,
    });
    await prefs.setString(_usedNonces, jsonEncode(rows));
  }

  // ---- Signer private keys (this device's own keypairs) ----

  static const _signerKeys = 'signer_keys';

  static Future<List<int>?> getSignerKey(String signerId) async {
    final raw = _instance?.getString(_signerKeys);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final b64 = map[signerId] as String?;
      if (b64 == null) return null;
      return base64Url.decode(base64Url.normalize(b64));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSignerKey(String signerId, List<int> seed) async {
    final prefs = _instance;
    if (prefs == null) return;
    final raw = prefs.getString(_signerKeys);
    Map<String, dynamic> map = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    map[signerId] = base64Url.encode(seed);
    await prefs.setString(_signerKeys, jsonEncode(map));
  }

  static Future<String?> getActiveSignerId() async =>
      _instance?.getString('active_signer_id');

  static Future<void> setActiveSignerId(String value) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setString('active_signer_id', value);
  }

  static Future<Map<String, String>> getShopNames() async {
    if (_cachedShopNames != null) {
      return Map<String, String>.from(_cachedShopNames!);
    }
    final prefs = _instance;
    if (prefs == null) return {};
    final raw = prefs.getString(_shopNames);
    if (raw == null || raw.isEmpty) {
      _cachedShopNames = {};
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cachedShopNames = decoded.map((k, v) => MapEntry(k, v.toString()));
      return Map<String, String>.from(_cachedShopNames!);
    } catch (e) {
      logWarning('shop names corrupt — reset', error: e);
      _cachedShopNames = {};
      return {};
    }
  }

  static Future<String?> getShopBusinessName(String key) async {
    final names = await getShopNames();
    return names[key];
  }

  static Future<void> removeShopBusinessName(String key) async {
    final prefs = _instance;
    if (prefs == null) return;
    final names = await getShopNames();
    names.remove(key);
    _cachedShopNames = Map<String, String>.from(names);
    await prefs.setString(_shopNames, jsonEncode(names));
  }

  static Future<void> saveShopBusinessName(String key, String name) async {
    final prefs = _instance;
    if (prefs == null) return;
    final names = await getShopNames();
    names[key] = name;
    _cachedShopNames = Map<String, String>.from(names);
    await prefs.setString(_shopNames, jsonEncode(names));
  }

  static Future<bool> getAdminMode() async {
    final prefs = _instance;
    if (prefs == null) return false;
    return prefs.getBool(_adminMode) ?? false;
  }

  static Future<void> setAdminMode(bool value) async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.setBool(_adminMode, value);
  }
}
