import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/catalog_entry.dart';
import '../data/sync_config.dart';

/// Result of a push sync against the catalog server.
class SyncResult {
  final int accepted;
  final int rejectedCount;
  final List<String> rejected; // barcodes the server refused
  final int serverNow; // epoch ms; store as new last_synced_at
  final List<String> newerOnServer; // barcodes where server row was newer

  SyncResult({
    required this.accepted,
    required this.rejected,
    required this.serverNow,
    required this.newerOnServer,
  }) : rejectedCount = rejected.length;

  bool get ok => rejected.isEmpty;
}

/// Client for the catalog push server (server/app.py).
/// On-demand only — the caller decides when to sync; this class never
/// schedules or auto-triggers anything.
class CatalogSyncClient {
  final String baseUrl;
  final String token;
  final String deviceId;
  final http.Client _client;

  CatalogSyncClient({
    required this.baseUrl,
    required this.token,
    required this.deviceId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory CatalogSyncClient.fromConfig(SyncConfig cfg) {
    return CatalogSyncClient(
      baseUrl: cfg.url ?? '',
      token: cfg.token ?? '',
      deviceId: cfg.deviceId,
    );
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Pushes catalog entries newer than [lastSyncedAt], plus [deleted] barcodes
  /// to tombstone. Returns the parsed result. Throws on network/server error.
  Future<SyncResult> push({
    required List<CatalogEntry> entries,
    required List<String> deleted,
    required int lastSyncedAt,
  }) async {
    final body = jsonEncode({
      'device_id': deviceId,
      'last_synced_at': lastSyncedAt,
      'entries': entries
          .map((e) => {
                'barcode': e.barcode,
                'name': e.name,
                'name_ar': e.nameAr,
                'name_en': e.nameEn,
                'category': e.category,
                'photo_base64':
                    e.photo != null ? base64Encode(e.photo!) : null,
                'updated_at': e.updatedAt,
              })
          .toList(),
      'deleted': deleted,
    });

    final resp = await _client
        .post(
          Uri.parse('$baseUrl/v1/sync'),
          headers: _headers,
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('server error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return SyncResult(
      accepted: (data['accepted'] as num).toInt(),
      rejected: ((data['rejected'] as List?) ?? [])
          .map((r) => (r['barcode'] ?? '').toString())
          .toList(),
      serverNow: (data['server_now'] as num).toInt(),
      newerOnServer: ((data['newer_on_server'] as List?) ?? [])
          .map((r) => (r['barcode'] ?? '').toString())
          .toList(),
    );
  }

  /// Registers a shop on the server (admin provisioning).
  Future<void> registerShop(String shopKey, String businessName) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/v1/shops'),
          headers: _headers,
          body: jsonEncode({
            'shop_key': shopKey,
            'business_name': businessName,
            'device_id': deviceId,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw SyncException('register shop ${resp.statusCode}: ${resp.body}');
    }
  }

  /// Looks up a shop on the server. Returns business name if found, else null.
  Future<String?> getShop(String shopKey) async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/v1/shops/$shopKey'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('get shop ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['business_name'] as String?;
  }

  void close() => _client.close();

  /// Deletes a shop on the server (admin provisioning).
  Future<void> deleteShop(String shopKey) async {
    final resp = await _client
        .delete(Uri.parse('$baseUrl/v1/shops/$shopKey'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw SyncException('delete shop ${resp.statusCode}: ${resp.body}');
    }
  }
  Future<bool> getCatalogOpen() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/v1/admin/catalog-open'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('catalog-open ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['open'] == true;
  }

  /// Toggles whether the server accepts pushes.
  Future<bool> setCatalogOpen(bool open) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/v1/admin/catalog-open'),
          headers: _headers,
          body: jsonEncode({'open': open}),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('catalog-open ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['open'] == true;
  }

  /// Records the catalog version the shopkeeper is running, so the server
  /// (single source of truth) knows which generation each shop is on.
  /// Called by the admin after a push is applied.
  Future<void> setCatalogVersion(String shopKey, int version) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/v1/shops/$shopKey/catalog-version'),
          headers: _headers,
          body: jsonEncode({'catalog_version': version}),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('set catalog version ${resp.statusCode}: ${resp.body}');
    }
  }

  /// Resolves a barcode against the server catalog (read API). Returns the
  /// canonical fields on hit, or null on 404. Throws SyncException/SyncAuth
  /// on server/auth error so the caller can fall back to manual entry.
  /// Read-only — works even when the server's write gate is closed.
  Future<Map<String, dynamic>?> resolve(String barcode) async {
    final resp = await _client
        .get(
          Uri.parse('$baseUrl/v1/products/${Uri.encodeComponent(barcode)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('resolve ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Browses/searches the server catalog. `q` matches name/brand (empty =
  /// browse all, paginated); `category` filters by slug. Returns
  /// {total, limit, offset, products:[...]}. Read-only, ungated.
  Future<Map<String, dynamic>> search({
    String q = '',
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (q.trim().isNotEmpty) params['q'] = q.trim();
    if (category != null && category.isNotEmpty) params['category'] = category;
    final uri = Uri.parse('$baseUrl/v1/products/search')
        .replace(queryParameters: params);
    final resp =
        await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('search ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => 'SyncException: $message';
}

class SyncAuthException extends SyncException {
  SyncAuthException(super.message);
}
