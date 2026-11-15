import 'package:flutter/services.dart';

import 'catalog_delta.dart';
import 'catalog_db.dart';
import 'config.dart';
import 'db.dart';
import 'settings_service.dart';

/// Entry point for `.myhanout` catalog delta files.
///
/// Android routes a VIEW intent for such a file to [MainActivity], which
/// captures the URI and exposes it over the `myhanout/view` method channel.
/// This class reads the file, verifies its signature + shop binding, and
/// applies it to the local catalog — all offline.
class MyhanoutFile {
  static const MethodChannel _channel = MethodChannel('myhanout/view');

  /// Handles the VIEW intent the app was launched with, if any.
  /// Returns a short human-readable outcome, or null when there was no file.
  static Future<String?> handleLaunchIntent({SettingsService? settings}) async {
    String? uri;
    try {
      uri = await _channel.invokeMethod<String>('getInitialUri');
    } catch (_) {
      // Channel not available (tests, non-Android) — nothing to do.
    }
    if (uri == null || uri.isEmpty) return null;
    return applyUri(uri, settings: settings);
  }

  /// Reads and applies a `.myhanout` URI (`file://` or `content://`).
  static Future<String?> applyUri(String uri, {SettingsService? settings}) async {
    String? json;
    try {
      json = await _channel.invokeMethod<String>('readUri', {'uri': uri});
    } catch (_) {
      return 'unreadable file';
    }
    if (json == null || json.isEmpty) return 'unreadable file';
    return applyJson(json, settings: settings);
  }

  /// Verifies a `.myhanout` payload against the active shop and applies it.
  ///
  /// [settings] is injected; it defaults to the production store so the POC
  /// tests and the launch-intent path need no setup.
  static Future<String> applyJson(String json, {SettingsService? settings}) async {
    final store = settings ?? const ConfigSettingsService();
    final shopKey = await store.getCurrentShopKey();
    final verification = CatalogDelta.verify(json);
    if (!verification.ok) return 'rejected: ${verification.error}';
    final d = verification.delta!;

    // Base-version guard: a delta built against a different catalog
    // generation than the one installed here is stale — reject it whole
    // rather than half-applying.
    final installed = await store.getCatalogVersion();
    if (d.baseVersion != installed) {
      return 'rejected: catalog version mismatch '
          '(device $installed, bundle ${d.baseVersion})';
    }

    await d.apply(CatalogDb.instance);
    await store.setCatalogVersion(d.targetVersion);
    // Display-cache refresh: fill the photo of matching inventory rows that
    // have none. Never touches price/stock/name.
    var refreshed = 0;
    for (final e in verification.delta!.upserts) {
      if (e.photo == null) continue;
      refreshed += await Db.applyCatalogPhoto(
        shopKey,
        barcode: e.barcode,
        photo: e.photo!,
      );
    }
    return 'applied ${d.upserts.length} update(s), ${d.deletes.length} delete(s)'
        ' (catalog → ${d.targetVersion})'
        '${refreshed > 0 ? ' · $refreshed inventory photo(s) filled' : ''}';
  }
}
