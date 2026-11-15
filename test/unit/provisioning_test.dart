// B4 — per-shop QR lifetime (`ttl_seconds` travels in the signed token).
//
// Run: flutter test test/unit/provisioning_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/provisioning.dart';
import 'package:myhanout/data/shop_provisioning_service.dart';

const _shopKey = 'hanouti';
const _name = 'Hanouti';

/// Builds a token with a chosen payload, signed exactly like production.
String _token(Map<String, dynamic> payload) => Provisioning.sign(payload);

Map<String, dynamic> _payload({
  int? issuedAt,
  int? ttlSeconds,
  bool omitTtl = false,
}) {
  final m = <String, dynamic>{
    'shop_key': _shopKey,
    'business_name': _name,
    'issued_at': issuedAt ?? DateTime.now().millisecondsSinceEpoch,
    'nonce': 'ABCDEFGH',
  };
  if (!omitTtl) m['ttl_seconds'] = ttlSeconds ?? 1800;
  return m;
}

void main() {
  group('Provisioning.verify — TTL resolution', () {
    test('a fresh token with ttl_seconds is accepted', () {
      final token = _token(_payload(ttlSeconds: 604800));
      final payload = Provisioning.verify(token);
      expect(payload, isNotNull);
      expect(payload!['shop_key'], _shopKey);
    });

    test('the token ttl wins over the 30-minute default', () {
      // Issued 1 hour ago: over the 30 min default, under a 7-day token TTL.
      final issued =
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final token = _token(_payload(issuedAt: issued, ttlSeconds: 604800));

      expect(Provisioning.verify(token), isNotNull,
          reason: 'ttl_seconds must extend the default lifetime');
      // An explicit caller override still wins.
      expect(
        Provisioning.verify(token, maxAge: const Duration(minutes: 30)),
        isNull,
        reason: 'an explicit maxAge override must be honoured',
      );
    });

    test('a token without ttl_seconds falls back to the 30-minute default',
        () {
      final fresh = _token(_payload(omitTtl: true));
      expect(Provisioning.verify(fresh), isNotNull);

      final old = _token(_payload(
        omitTtl: true,
        issuedAt: DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      ));
      expect(Provisioning.verify(old), isNull,
          reason: 'pre-B4 codes must keep the old 30 min lifetime');
    });

    test('an expired token is rejected', () {
      final token = _token(_payload(
        ttlSeconds: 1800,
        issuedAt: DateTime.now()
            .subtract(const Duration(minutes: 31))
            .millisecondsSinceEpoch,
      ));
      expect(Provisioning.verify(token), isNull);
    });

    test('a token dated in the future beyond the skew is rejected', () {
      final token = _token(_payload(
        issuedAt: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      ));
      expect(Provisioning.verify(token), isNull);
    });

    test('a small clock skew in the future is tolerated', () {
      final token = _token(_payload(
        issuedAt: DateTime.now()
            .add(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
      ));
      expect(Provisioning.verify(token), isNotNull);
    });

    test('a malformed ttl_seconds fails open to the default', () {
      final payload = _payload()..['ttl_seconds'] = 'not-a-number';
      expect(Provisioning.verify(_token(payload)), isNotNull);

      final negative = _payload(ttlSeconds: -5);
      expect(Provisioning.verify(_token(negative)), isNotNull);
    });

    test('a tampered payload is rejected', () {
      final token = _token(_payload(ttlSeconds: 604800));
      final parts = token.split('.');
      // Flip the signature.
      final bad = '${parts[0]}.${parts[1].substring(0, parts[1].length - 1)}X';
      expect(Provisioning.verify(bad), isNull);
    });

    test('garbage input is rejected, not thrown', () {
      expect(Provisioning.verify('not-a-token'), isNull);
      expect(Provisioning.verify(''), isNull);
    });
  });

  group('ShopProvisioningService.buildProvisioningToken', () {
    test('carries ttl_seconds and names exactly one shop', () {
      final payload =
          Provisioning.verify(ShopProvisioningService.buildProvisioningToken(
        _shopKey,
        _name,
        ttlSeconds: 86400,
      ));
      expect(payload, isNotNull);
      expect(payload!['ttl_seconds'], 86400);
      expect(payload['shop_key'], _shopKey);
      expect(payload['business_name'], _name);
    });

    test('defaults to the 30-minute TTL', () {
      final payload = Provisioning.verify(
          ShopProvisioningService.buildProvisioningToken(_shopKey, _name));
      expect(payload!['ttl_seconds'], defaultProvisioningTtlSeconds);
    });

    test('the offered choices are all positive and usable', () {
      expect(provisioningTtlChoices, isNotEmpty);
      for (final ttl in provisioningTtlChoices.keys) {
        expect(ttl, greaterThan(0));
        final payload = Provisioning.verify(
            ShopProvisioningService.buildProvisioningToken(_shopKey, _name,
                ttlSeconds: ttl));
        expect(payload, isNotNull, reason: 'ttl $ttl must verify');
      }
    });
  });
}
