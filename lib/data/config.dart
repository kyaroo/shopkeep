import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
    } catch (_) {
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
