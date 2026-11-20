import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/sync_config.dart';

/// Read-only view of a shop as reported by `GET /v1/shops/{key}/info`.
///
/// Provisioner fields are the server's truth about who created the shop; the
/// app never edits them. [businessName] is editable ONLY for an `owner` token
/// (the server answers 403 for a salesman); the four contact fields are
/// editable for both roles. See [ShopInfoPatch].
class ShopInfo {
  final String shopKey;
  final String businessName;
  final String address;
  final String city;
  final String ownerName;
  final String phone;
  final String provisionerSignerId;
  final String provisionerName;
  final String provisionerRole;
  final int catalogVersion;

  const ShopInfo({
    required this.shopKey,
    required this.businessName,
    required this.address,
    required this.city,
    required this.ownerName,
    required this.phone,
    required this.provisionerSignerId,
    required this.provisionerName,
    required this.provisionerRole,
    required this.catalogVersion,
  });

  factory ShopInfo.fromMap(Map<String, dynamic> m) => ShopInfo(
        shopKey: (m['shop_key'] ?? '').toString(),
        businessName: (m['business_name'] ?? '').toString(),
        address: (m['address'] ?? '').toString(),
        city: (m['city'] ?? '').toString(),
        ownerName: (m['owner_name'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        provisionerSignerId: (m['provisioner_signer_id'] ?? '').toString(),
        provisionerName: (m['provisioner_name'] ?? '').toString(),
        provisionerRole: (m['provisioner_role'] ?? '').toString(),
        catalogVersion: (m['catalog_version'] as num?)?.toInt() ?? 0,
      );
}

/// The ONLY fields the server accepts on `PATCH /v1/shops/{key}/info`.
///
/// Building the request body from this class is what enforces the allowlist:
/// no provisioning or catalog field can be smuggled into a patch.
class ShopInfoPatch {
  final String? businessName;
  final String? address;
  final String? city;
  final String? ownerName;
  final String? phone;

  const ShopInfoPatch({
    this.businessName,
    this.address,
    this.city,
    this.ownerName,
    this.phone,
  });

  bool get isEmpty =>
      businessName == null &&
      address == null &&
      city == null &&
      ownerName == null &&
      phone == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (businessName != null) 'business_name': businessName,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (ownerName != null) 'owner_name': ownerName,
        if (phone != null) 'phone': phone,
      };
}

/// Injectable factory so screens/tests can supply a client without touching
/// SharedPreferences (the app uses [ShopInfoClient.fromConfig] by default).
typedef ShopInfoClientFactory = Future<ShopInfoClient> Function();

/// Admin-only HTTP client for per-shop info. Founders and salesmen both use it:
/// the role decision lives entirely in the server token the app already has.
class ShopInfoClient {
  final String baseUrl;
  final String token;
  final http.Client _client;

  ShopInfoClient({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory ShopInfoClient.fromConfig(SyncConfig cfg) => ShopInfoClient(
        baseUrl: (cfg.url ?? SyncConfig.defaultUrl).trim(),
        token: (cfg.token ?? '').trim(),
      );

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static String _detail(http.Response resp) {
    try {
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) {
        final detail = data['detail'] ?? data['message'] ?? data['error'];
        if (detail != null) return detail.toString();
      }
    } catch (_) {
      // Non-JSON body: fall through to the raw text.
    }
    final body = resp.body.trim();
    return body.isEmpty ? 'HTTP ${resp.statusCode}' : body;
  }

  static ShopInfoException _errorFor(http.Response resp) {
    final status = resp.statusCode;
    final detail = _detail(resp);
    if (status == 404) {
      return ShopInfoNotFoundException(detail, statusCode: status);
    }
    if (status == 401 || status == 403) {
      return ShopInfoForbiddenException(detail, statusCode: status);
    }
    if (status == 400) {
      return ShopInfoBadRequestException(detail, statusCode: status);
    }
    if (status == 409) {
      return ShopInfoConflictException(detail, statusCode: status);
    }
    return ShopInfoException(detail, statusCode: status);
  }

  /// GET `/v1/shops/{key}/info`.
  Future<ShopInfo> fetch(String shopKey) async {
    final uri = Uri.parse(
        '$baseUrl/v1/shops/${Uri.encodeComponent(shopKey)}/info');
    final resp = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 12),
        );
    if (resp.statusCode != 200) throw _errorFor(resp);
    return ShopInfo.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// PATCH `/v1/shops/{key}/info` with the allowlisted [patch] only.
  Future<ShopInfo> patch(String shopKey, ShopInfoPatch patch) async {
    if (patch.isEmpty) {
      throw const ShopInfoBadRequestException('No editable fields provided',
          statusCode: 400);
    }
    final uri = Uri.parse(
        '$baseUrl/v1/shops/${Uri.encodeComponent(shopKey)}/info');
    final resp = await _client
        .patch(
          uri,
          headers: _headers,
          body: jsonEncode(patch.toJson()),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) throw _errorFor(resp);
    return ShopInfo.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  void close() => _client.close();
}

class ShopInfoException implements Exception {
  final String message;
  final int? statusCode;
  const ShopInfoException(this.message, {this.statusCode});

  @override
  String toString() => 'ShopInfoException${statusCode == null ? '' : ' ($statusCode)'}: $message';
}

class ShopInfoNotFoundException extends ShopInfoException {
  const ShopInfoNotFoundException(super.message, {super.statusCode});
}

class ShopInfoForbiddenException extends ShopInfoException {
  const ShopInfoForbiddenException(super.message, {super.statusCode});
}

class ShopInfoBadRequestException extends ShopInfoException {
  const ShopInfoBadRequestException(super.message, {super.statusCode});
}

class ShopInfoConflictException extends ShopInfoException {
  const ShopInfoConflictException(super.message, {super.statusCode});
}
