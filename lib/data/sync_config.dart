import 'package:shared_preferences/shared_preferences.dart';
import '../data/catalog_sync_client.dart';

/// Holds the sync server configuration. Reads/writes values the user sets.
/// All optional — the app works fully offline until a URL is configured.
class SyncConfig {
  static const _kUrl = 'sync_url';
  static const _kToken = 'sync_token';
  static const _kLastSync = 'sync_last_synced_at';
  static const _kDevice = 'sync_device_id';

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
      url: prefs.getString(_kUrl) ?? defaultUrl,
      token: prefs.getString(_kToken) ?? defaultToken,
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

  CatalogSyncClient client() => CatalogSyncClient(
        baseUrl: url!.trim(),
        token: token!.trim(),
        deviceId: deviceId,
      );
}
