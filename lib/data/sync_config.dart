import 'package:shared_preferences/shared_preferences.dart';
import '../data/catalog_sync_client.dart';

/// Holds the sync server configuration. Reads/writes values the user sets.
/// All optional — the app works fully offline until a URL is configured.
class SyncConfig {
  static const _kUrl = 'sync_url';
  static const _kToken = 'sync_token';
  static const _kLastSync = 'sync_last_synced_at';
  static const _kDevice = 'sync_device_id';

  // Default server URL. NOT a secret — but the token is: it is entered in
  // Settings and persisted per install, never baked into the binary.
  static const String defaultUrl = 'https://catalog.myhanout.ma';

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

  static Future<SyncConfig> load({String? defaultUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    return SyncConfig(
      url: prefs.getString(_kUrl) ?? defaultUrl ?? SyncConfig.defaultUrl,
      // No baked default: an unset token means "not configured".
      token: prefs.getString(_kToken),
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
      // Callers must check isConfigured first; an empty token is never a valid
      // fallback for a baked secret.
      token: (cfg.token ?? '').trim(),
      deviceId: cfg.deviceId,
    );
  }
}
