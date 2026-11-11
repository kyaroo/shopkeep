import 'package:shared_preferences/shared_preferences.dart';
import '../data/catalog_sync_client.dart';

/// Holds the sync server configuration. Reads/writes values the user sets.
/// All optional — the app works fully offline until a URL is configured.
class SyncConfig {
  static const _kUrl = 'sync_url';
  static const _kToken = 'sync_token';
  static const _kLastSync = 'sync_last_synced_at';
  static const _kDevice = 'sync_device_id';

  // Centralized defaults (override via SyncConfig.load(defaultUrl:/defaultToken:) for dev).
  static const String defaultUrl = 'https://catalog.myhanout.ma';
  static const String defaultToken =
      'a07d7ef88372d390615a90f1c8acfbcc89724f65a11283cd77e59a7c148b7e9c';

  String? url;
  String? token;
  int lastSyncedAt;
  String deviceId;

  SyncConfig({
    this.url,
    this.token,
    this.lastSyncedAt = 0,
    this.deviceId = 'mapper-owner-01',
  });

  bool get isConfigured =>
      (url != null && url!.trim().isNotEmpty) &&
      (token != null && token!.trim().isNotEmpty);

  static Future<SyncConfig> load({String? defaultUrl, String? defaultToken}) async {
    final prefs = await SharedPreferences.getInstance();
    return SyncConfig(
      url: prefs.getString(_kUrl) ?? defaultUrl ?? SyncConfig.defaultUrl,
      token: prefs.getString(_kToken) ?? defaultToken ?? SyncConfig.defaultToken,
      lastSyncedAt: prefs.getInt(_kLastSync) ?? 0,
      deviceId: prefs.getString(_kDevice) ?? 'mapper-owner-01',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null) await prefs.setString(_kUrl, url!.trim());
    if (token != null) await prefs.setString(_kToken, token!.trim());
    await prefs.setInt(_kLastSync, lastSyncedAt);
    await prefs.setString(_kDevice, deviceId);
  }

  CatalogSyncClient client() => clientFrom(this);

  /// Convenience factory: load persisted config (with app defaults) and return
  /// a ready-to-use client. Centralizes construction across screens/providers.
  static Future<CatalogSyncClient> defaultClient() async {
    final cfg = await load();
    return clientFrom(cfg);
  }

  static CatalogSyncClient clientFrom(SyncConfig cfg) {
    return CatalogSyncClient(
      baseUrl: (cfg.url ?? defaultUrl).trim(),
      token: (cfg.token ?? defaultToken).trim(),
      deviceId: cfg.deviceId,
    );
  }
}
