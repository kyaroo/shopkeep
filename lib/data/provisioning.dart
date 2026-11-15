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

  /// Fallback lifetime for tokens issued before per-token TTL existed.
  static const Duration defaultTtl = Duration(minutes: 30);

  /// Clock skew tolerated when rejecting future-dated tokens (a phone clock
  /// slightly ahead of the admin's must not invalidate a fresh code).
  static const Duration maxClockSkew = Duration(seconds: 60);

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
  ///
  /// Lifetime resolution order: an explicit [maxAge] (caller override) wins;
  /// otherwise the token's own `ttl_seconds` (B4) is used; tokens without it
  /// fall back to [defaultTtl], so codes issued before B4 stay valid.
  ///
  /// Tokens dated in the future beyond [maxClockSkew] are rejected — an
  /// `issued_at` from next week is not a code anyone scanned.
  static Map<String, dynamic>? verify(String token, {Duration? maxAge}) {
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
      final age = DateTime.now().difference(issued);
      final ttl = _ttlFor(payload, maxAge);
      if (age > ttl) return null;
      if (age.isNegative && -age > maxClockSkew) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Lifetime for a token: caller override, else the token's `ttl_seconds`,
  /// else [defaultTtl]. A malformed/absent `ttl_seconds` fails open to the
  /// default rather than bricking an older code.
  static Duration _ttlFor(Map<String, dynamic> payload, Duration? override) {
    if (override != null) return override;
    final raw = payload['ttl_seconds'];
    if (raw is int && raw > 0) return Duration(seconds: raw);
    if (raw is num && raw > 0) {
      return Duration(milliseconds: (raw * 1000).round());
    }
    return defaultTtl;
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