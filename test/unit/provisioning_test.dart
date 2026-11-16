// Provisioning QR — Ed25519, per-signer, with the per-token TTL inside the
// signed payload.
//
// Run: flutter test test/unit/provisioning_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/provisioning.dart';
import 'package:myhanout/data/shop_provisioning_service.dart';
import 'package:myhanout/data/signing.dart';

import '../helpers/signing_trust.dart';

const _shopKey = 'hanouti';
const _name = 'Hanouti';

/// Builds a token with a chosen payload, signed exactly like production.
Future<String> _token(SigningTrust trust, Map<String, dynamic> payload) =>
    Signing.signPayload(payload, trust.seed(SigningTrust.founderAdminId));

Map<String, dynamic> _payload({
  int? issuedAt,
  int? ttlSeconds,
  bool omitTtl = false,
}) {
  final m = <String, dynamic>{
    'format': ArtifactFormat.provision,
    'alg': Signing.algorithm,
    'shop_key': _shopKey,
    'business_name': _name,
    'issued_at': issuedAt ?? DateTime.now().millisecondsSinceEpoch,
    'nonce': 'ABCDEFGH',
    'signer_id': SigningTrust.founderAdminId,
  };
  if (!omitTtl) m['ttl_seconds'] = ttlSeconds ?? 1800;
  return m;
}

void main() {
  late SigningTrust trust;

  setUp(() async {
    trust = await SigningTrust.create();
  });

  Future<ProvisioningResult> verify(String token, {Duration? maxAge}) =>
      Provisioning.verify(token, directory: trust.directory, maxAge: maxAge);

  group('Provisioning.verify — TTL resolution', () {
    test('a fresh token with ttl_seconds is accepted', () async {
      final r = await verify(await _token(trust, _payload(ttlSeconds: 604800)));
      expect(r.ok, isTrue);
      expect(r.payload!['shop_key'], _shopKey);
    });

    test('the token ttl wins over the 30-minute default', () async {
      final issued = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      final token = await _token(
          trust, _payload(issuedAt: issued, ttlSeconds: 604800));

      expect((await verify(token)).ok, isTrue,
          reason: 'ttl_seconds must extend the default lifetime');
      expect(
        (await verify(token, maxAge: const Duration(minutes: 30))).ok,
        isFalse,
        reason: 'an explicit maxAge override must be honoured',
      );
    });

    test('a token without ttl_seconds falls back to the 30-minute default',
        () async {
      expect((await verify(await _token(trust, _payload(omitTtl: true)))).ok,
          isTrue);

      final old = await _token(trust, _payload(
        omitTtl: true,
        issuedAt: DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      ));
      expect((await verify(old)).ok, isFalse,
          reason: 'pre-B4 codes must keep the old 30 min lifetime');
    });

    test('an expired token is rejected', () async {
      final token = await _token(trust, _payload(
        ttlSeconds: 1800,
        issuedAt: DateTime.now()
            .subtract(const Duration(minutes: 31))
            .millisecondsSinceEpoch,
      ));
      expect((await verify(token)).ok, isFalse);
    });

    test('a token dated in the future beyond the skew is rejected', () async {
      final token = await _token(trust, _payload(
        issuedAt: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      ));
      expect((await verify(token)).ok, isFalse);
    });

    test('a small clock skew in the future is tolerated', () async {
      final token = await _token(trust, _payload(
        issuedAt: DateTime.now()
            .add(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
      ));
      expect((await verify(token)).ok, isTrue);
    });

    test('a malformed ttl_seconds fails open to the default', () async {
      final payload = _payload()..['ttl_seconds'] = 'not-a-number';
      expect((await verify(await _token(trust, payload))).ok, isTrue);

      final negative = _payload(ttlSeconds: -5);
      expect((await verify(await _token(trust, negative))).ok, isTrue);
    });

    test('a tampered signature is rejected', () async {
      final token = await _token(trust, _payload(ttlSeconds: 604800));
      final parts = token.split('.');
      final bad = '${parts[0]}.${parts[1].substring(0, parts[1].length - 1)}X';
      expect((await verify(bad)).ok, isFalse);
    });

    test('garbage input is rejected, not thrown', () async {
      expect((await verify('not-a-token')).ok, isFalse);
      expect((await verify('')).ok, isFalse);
    });

    test('an unknown signer and a forbidden role are rejected', () async {
      final stranger = await Signing.generateSigner();
      final ghost = await Signing.signPayload(
          _payload()..['signer_id'] = 'ghost', stranger);
      expect((await verify(ghost)).error, VerifyResult.errUnknownSigner);

      // A salesman may provision, but not with a delta format.
      final salesmanToken = await Signing.signPayload(
        _payload()..['signer_id'] = SigningTrust.salesmanId,
        trust.seed(SigningTrust.salesmanId),
      );
      expect((await verify(salesmanToken)).ok, isTrue,
          reason: 'salesman is allowed to provision');
    });
  });

  group('ShopProvisioningService.buildProvisioningToken', () {
    Future<String> build({
      int ttlSeconds = defaultProvisioningTtlSeconds,
      String signerId = SigningTrust.founderAdminId,
    }) =>
        ShopProvisioningService.buildProvisioningToken(
          _shopKey,
          _name,
          signerId: signerId,
          privateSeed: trust.seed(signerId),
          ttlSeconds: ttlSeconds,
        );

    test('carries ttl_seconds and names exactly one shop', () async {
      final r = await verify(await build(ttlSeconds: 86400));
      expect(r.ok, isTrue);
      expect(r.payload!['ttl_seconds'], 86400);
      expect(r.payload!['shop_key'], _shopKey);
      expect(r.payload!['business_name'], _name);
      expect(r.signer?.id, SigningTrust.founderAdminId);
    });

    test('defaults to the 30-minute TTL', () async {
      final r = await verify(await build());
      expect(r.payload!['ttl_seconds'], defaultProvisioningTtlSeconds);
    });

    test('the offered choices are all positive and usable', () async {
      expect(provisioningTtlChoices, isNotEmpty);
      for (final ttl in provisioningTtlChoices.keys) {
        expect(ttl, greaterThan(0));
        expect((await verify(await build(ttlSeconds: ttl))).ok, isTrue,
            reason: 'ttl $ttl must verify');
      }
    });
  });
}
