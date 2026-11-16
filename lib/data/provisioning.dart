import 'dart:math';

import 'signing.dart';

/// Default QR validity when the caller does not choose one (30 minutes).
const int defaultProvisioningTtlSeconds = 1800;

/// Provisioning QR helpers — now Ed25519, per-admin.
///
/// The shared HMAC secret is gone: a QR is signed by the issuing signer's
/// private key and verified offline against the signers directory (see
/// `lib/data/signing.dart`).
class Provisioning {
  /// Nonce alphabet/length for QR uniqueness.
  static String generateShopKey({int length = 12}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Fallback lifetime for tokens issued before per-token TTL existed.
  static const Duration defaultTtl = Duration(minutes: 30);

  /// Clock skew tolerated when rejecting future-dated tokens.
  static const Duration maxClockSkew = Duration(seconds: 60);

  /// Builds a signed provisioning QR envelope.
  ///
  /// [signerId] must be in the directory with a role allowed to provision
  /// (founder / admin / salesman); [privateSeed] is that signer's key.
  static Future<String> buildProvisioningToken(
    String shopKey,
    String businessName, {
    required String signerId,
    required List<int> privateSeed,
    int ttlSeconds = defaultProvisioningTtlSeconds,
  }) {
    final payload = <String, dynamic>{
      'format': ArtifactFormat.provision,
      'alg': Signing.algorithm,
      'shop_key': shopKey,
      'business_name': businessName,
      'issued_at': DateTime.now().millisecondsSinceEpoch,
      'nonce': generateShopKey(length: 8),
      'ttl_seconds': ttlSeconds,
      'signer_id': signerId,
    };
    return Signing.signPayload(payload, privateSeed);
  }

  /// Verifies a scanned QR: format → signer → role → signature → expiry.
  static Future<ProvisioningResult> verify(
    String token, {
    required SignersDirectory directory,
    Duration? maxAge,
  }) async {
    final result = await Signing.verifyEnvelope(
      token,
      directory: directory,
      expectedFormat: ArtifactFormat.provision,
      allowedRoles: const {
        SignerRole.founder,
        SignerRole.admin,
        SignerRole.salesman,
      },
    );
    if (!result.ok) return ProvisioningResult.fail(result.error!);

    final payload = result.payload!;
    final issuedAt = payload['issued_at'];
    if (issuedAt is! int) return ProvisioningResult.fail('malformed-field');
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(issuedAt),
    );
    if (age > _ttlFor(payload, maxAge)) {
      return ProvisioningResult.fail('expired');
    }
    if (age.isNegative && -age > maxClockSkew) {
      return ProvisioningResult.fail('expired');
    }
    return ProvisioningResult.ok(payload, result.signer!);
  }

  static Duration _ttlFor(Map<String, dynamic> payload, Duration? override) {
    if (override != null) return override;
    final raw = payload['ttl_seconds'];
    if (raw is int && raw > 0) return Duration(seconds: raw);
    if (raw is num && raw > 0) {
      return Duration(milliseconds: (raw * 1000).round());
    }
    return defaultTtl;
  }
}

/// Outcome of [Provisioning.verify].
class ProvisioningResult {
  final bool ok;
  final Map<String, dynamic>? payload;
  final SignerEntry? signer;
  final String? error;

  const ProvisioningResult._(this.ok, this.payload, this.signer, this.error);

  factory ProvisioningResult.ok(
    Map<String, dynamic> payload,
    SignerEntry signer,
  ) =>
      ProvisioningResult._(true, payload, signer, null);
  factory ProvisioningResult.fail(String error) =>
      ProvisioningResult._(false, null, null, error);
}
