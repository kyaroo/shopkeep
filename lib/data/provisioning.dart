import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Shared secret used to sign/verify shop provisioning QR codes.
/// Embedded in both flavors; rotate by changing this constant and rebuilding.
const String _provisioningSecret = 'myhanout-provisioning-secret-change-me';

class Provisioning {
  static String generateShopKey({int length = 12}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Signs a payload and returns `base64(payload).base64(signature)`.
  static String sign(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    final payloadB64 = base64UrlEncode(utf8.encode(json));
    final hmac = Hmac(sha256, utf8.encode(_provisioningSecret));
    final sig = hmac.convert(utf8.encode(payloadB64));
    final sigB64 = base64UrlEncode(sig.bytes);
    return '$payloadB64.$sigB64';
  }

  /// Verifies signature and expiry. Returns payload map if valid, else null.
  static Map<String, dynamic>? verify(String token, {Duration maxAge = const Duration(minutes: 30)}) {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    final payloadB64 = parts[0];
    final sigB64 = parts[1];
    final hmac = Hmac(sha256, utf8.encode(_provisioningSecret));
    final expected = base64UrlEncode(hmac.convert(utf8.encode(payloadB64)).bytes);
    if (!_constantTimeEquals(expected, sigB64)) return null;
    try {
      final json = utf8.decode(base64Url.decode(base64Url.normalize(payloadB64)));
      final payload = jsonDecode(json) as Map<String, dynamic>;
      final issuedAt = payload['issued_at'] as int?;
      if (issuedAt == null) return null;
      final issued = DateTime.fromMillisecondsSinceEpoch(issuedAt);
      if (DateTime.now().difference(issued).abs() > maxAge) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Signs an arbitrary canonical JSON string. Used by `.myhanout` catalog
  /// delta files so a file can be verified offline and bound to one shop.
  /// Returns a base64url HMAC-SHA256 signature.
  static String signatureFor(String canonicalJson) {
    final hmac = Hmac(sha256, utf8.encode(_provisioningSecret));
    return base64UrlEncode(hmac.convert(utf8.encode(canonicalJson)).bytes);
  }

  /// Verifies a [signatureFor] signature in constant time.
  static bool verifySignature(String canonicalJson, String signature) =>
      _constantTimeEquals(signatureFor(canonicalJson), signature);

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}