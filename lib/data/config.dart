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

  static Future<List<String>> getShopList() async {
    final prefs = _instance;
    if (prefs == null) return [];
    final raw = prefs.getStringList(_shopList);
    return raw?.where((s) => s.isNotEmpty).toList() ?? [];
  }

  static Future<void> addShop(String shopKey, String businessName) async {
    final prefs = _instance;
    if (prefs == null) return;
    final list = await getShopList();
    if (!list.contains(shopKey)) {
      list.add(shopKey);
      await prefs.setStringList(_shopList, list);
    }
  }

  static Future<void> removeShop(String shopKey) async {
    final prefs = _instance;
    if (prefs == null) return;
    final list = await getShopList();
    await prefs.setStringList(_shopList, list.where((s) => s != shopKey).toList());
  }

  static Future<void> clearShopList() async {
    final prefs = _instance;
    if (prefs == null) return;
    await prefs.remove(_shopList);
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

  // ---- Admin mode toggle ----

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
