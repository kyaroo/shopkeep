import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/catalog_entry.dart';
import '../models/catalog_row.dart';
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

/// A shop registered on the catalog server.
///
/// [catalogVersion] is the **server-side** truth: the generation the shop is
/// on, reported by the admin after a delivery. 0 means "never reported".
class ShopRow {
  final String shopKey;
  final String businessName;
  final int catalogVersion;
  final int createdAt;
  final String? deviceId;

  const ShopRow({
    required this.shopKey,
    required this.businessName,
    required this.catalogVersion,
    required this.createdAt,
    this.deviceId,
  });

  factory ShopRow.fromMap(Map<String, dynamic> m) => ShopRow(
        shopKey: (m['shop_key'] ?? '') as String,
        businessName: (m['business_name'] ?? '') as String,
        catalogVersion: (m['catalog_version'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        deviceId: m['device_id'] as String?,
      );
}

/// One page of `GET /v1/shops/search`, ordered by `shop_key` on the server.
class ShopSearchResult {
  final List<ShopRow> items;
  final int total;
  final int limit;
  final int offset;

  const ShopSearchResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  bool get hasMore => offset + items.length < total;

  factory ShopSearchResult.fromMap(Map<String, dynamic> m) => ShopSearchResult(
        items: ((m['items'] as List?) ?? const [])
            .map((raw) => ShopRow.fromMap(raw as Map<String, dynamic>))
            .toList(),
        total: (m['total'] as num?)?.toInt() ?? 0,
        limit: (m['limit'] as num?)?.toInt() ?? 0,
        offset: (m['offset'] as num?)?.toInt() ?? 0,
      );
}

/// Builds a catalog sync client. Injectable so services and tests can supply
/// their own instead of the static [SyncConfig.defaultClient] locator.
typedef CatalogSyncClientFactory = Future<CatalogSyncClient> Function();

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

  /// A shop registered on the server, with the catalog generation it is on.
  /// [catalogVersion] is the server-side truth (0 = never reported).
  Future<List<ShopRow>> listShops() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/v1/shops'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('list shops ${resp.statusCode}: ${resp.body}');
    }
    final rows = jsonDecode(resp.body) as List;
    return rows
        .map((raw) => ShopRow.fromMap(raw as Map<String, dynamic>))
        .toList();
  }

  /// Paged shop search (`GET /v1/shops/search`). Replaces the old one-shot
  /// `listShops` for large catalogs. `limit` is capped at 100 by the server.
  Future<ShopSearchResult> searchShops({
    String q = '',
    int? minVersion,
    int? maxVersion,
    int limit = 20,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (q.trim().isNotEmpty) params['q'] = q.trim();
    if (minVersion != null) params['min_version'] = '$minVersion';
    if (maxVersion != null) params['max_version'] = '$maxVersion';
    final uri = Uri.parse('$baseUrl/v1/shops/search')
        .replace(queryParameters: params);
    final resp = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('search shops ${resp.statusCode}: ${resp.body}');
    }
    return ShopSearchResult.fromMap(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Looks up a shop on the server. Returns the row if found, else null.
  Future<ShopRow?> getShop(String shopKey) async {
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
    return ShopRow.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// `GET /v1/catalog/version` — the server's latest global generation.
  /// Owner-token only; the caller sends its stored token.
  Future<int> catalogVersion() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/v1/catalog/version'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('catalog version ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['version'] as num?)?.toInt() ?? 0;
  }

  /// One page of `GET /v1/catalog/diff` (owner token only). The server clamps
  /// `limit` to 1..100 and returns only `version > fromVersion`.
  Future<CatalogDiffPage> catalogDiff({
    required int fromVersion,
    int limit = 100,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/catalog/diff').replace(queryParameters: {
      'from_version': '$fromVersion',
      'limit': '$limit',
      'offset': '$offset',
    });
    final resp = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw SyncAuthException('auth failed (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw SyncException('catalog diff ${resp.statusCode}: ${resp.body}');
    }
    return CatalogDiffPage.fromMap(
        jsonDecode(resp.body) as Map<String, dynamic>);
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
  /// canonical row on hit, or null on 404. Throws SyncException/SyncAuth
  /// on server/auth error so the caller can fall back to manual entry.
  /// Read-only — works even when the server's write gate is closed.
  Future<CatalogRow?> resolve(String barcode) async {
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
    return CatalogRow.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Browses/searches the server catalog. `q` matches name/brand (empty =
  /// browse all, paginated); `category` filters by slug. Returns
  /// {total, limit, offset, products:[...]}. Read-only, ungated.
  Future<CatalogSearchResult> search({
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
    return CatalogSearchResult.fromMap(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }
}

/// One change row of `GET /v1/catalog/diff`.
///
/// The server returns `op` = `upsert` (with a stored [row]) or `delete`
/// (row null), only for `version > from_version`, ordered by
/// `(version, barcode)`. [row] is the stored payload; the shop listing
/// (price/stock) never travels here.
class CatalogDiffChange {
  final int version;
  final String barcode;
  final String op;
  final CatalogEntry? row;

  const CatalogDiffChange({
    required this.version,
    required this.barcode,
    required this.op,
    this.row,
  });

  /// A change is a tombstone when the server says `delete` or omits the row.
  bool get isDelete => op == 'delete' || row == null;

  factory CatalogDiffChange.fromMap(Map<String, dynamic> m) {
    final barcode = (m['barcode'] ?? '') as String;
    final op = (m['op'] ?? 'upsert') as String;
    final rawRow = m['row'];
    CatalogEntry? row;
    if (rawRow is Map) {
      final r = Map<String, dynamic>.from(rawRow);
      final photoB64 = r['photo_base64'] as String?;
      row = CatalogEntry(
        barcode: barcode,
        name: (r['name'] ?? '') as String,
        nameAr: r['name_ar'] as String?,
        nameEn: r['name_en'] as String?,
        category: r['category'] as String?,
        photo: (photoB64 == null || photoB64.isEmpty)
            ? null
            : base64Decode(photoB64),
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
      );
    }
    return CatalogDiffChange(
      version: (m['version'] as num?)?.toInt() ?? 0,
      barcode: barcode,
      op: op,
      row: row,
    );
  }
}

/// One page of `GET /v1/catalog/diff`.
class CatalogDiffPage {
  final int fromVersion;
  final int toVersion;
  final int total;
  final int limit;
  final int offset;
  final int? nextOffset;
  final List<CatalogDiffChange> changes;

  const CatalogDiffPage({
    required this.fromVersion,
    required this.toVersion,
    required this.total,
    required this.limit,
    required this.offset,
    required this.changes,
    this.nextOffset,
  });

  bool get hasMore => nextOffset != null;

  factory CatalogDiffPage.fromMap(Map<String, dynamic> m) => CatalogDiffPage(
        fromVersion: (m['from_version'] as num?)?.toInt() ?? 0,
        toVersion: (m['to_version'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        limit: (m['limit'] as num?)?.toInt() ?? 0,
        offset: (m['offset'] as num?)?.toInt() ?? 0,
        nextOffset: (m['next_offset'] as num?)?.toInt(),
        changes: ((m['changes'] as List?) ?? const [])
            .map((raw) =>
                CatalogDiffChange.fromMap(Map<String, dynamic>.from(raw as Map)))
            .toList(),
      );
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
