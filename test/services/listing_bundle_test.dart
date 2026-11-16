/// B1/B3 — the listing bundle: signed round-trip, rejection paths, and the
/// merge policy that decides what an import may change.
///
/// Run: flutter test test/services/listing_bundle_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/listing_row.dart';

import '../helpers/signing_trust.dart';

void main() {
  late SigningTrust trust;

  setUp(() async {
    trust = await SigningTrust.create();
  });

  Future<String> sign(
    List<ListingRow> rows, {
    String signerId = SigningTrust.adminId,
    String shopKey = 'hanouti',
  }) =>
      Signing.signArtifactFile(ListingBundle(
        signerId: signerId,
        shopKey: shopKey,
        catalogVersion: 4,
        generatedAt: 1718000000000,
        rows: rows,
      ).toPayload(), trust.seed(signerId));

  const rows = [
    ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12),
    ListingRow(barcode: '6111053001673', priceCents: 150, stockQty: 0),
  ];

  group('signed round-trip', () {
    test('an admin-signed bundle verifies and survives the wire', () async {
      final v = await ListingBundle.verify(await sign(rows),
          directory: trust.directory);
      expect(v.ok, isTrue, reason: v.error);
      expect(v.signerName, SigningTrust.adminId);
      expect(v.bundle!.shopKey, 'hanouti');
      expect(v.bundle!.catalogVersion, 4);
      expect(v.bundle!.rows, equals(rows));
    });

    test('a founder-signed bundle verifies', () async {
      final v = await ListingBundle.verify(
          await sign(rows, signerId: SigningTrust.founderAdminId),
          directory: trust.directory);
      expect(v.ok, isTrue, reason: v.error);
      expect(v.signerName, SigningTrust.founderAdminId);
    });

    test('the bundle carries no catalog field', () async {
      // Structural guarantee: name/category/photo are not in the format, so a
      // bundle cannot overwrite catalog data even if one is crafted.
      final payload = ListingBundle(
        signerId: SigningTrust.adminId,
        shopKey: 'hanouti',
        catalogVersion: 4,
        generatedAt: 1,
        rows: rows,
      ).toPayload();
      final encoded = Signing.canonicalize(payload);
      for (final forbidden in ['"name"', 'name_ar', 'name_en', 'category', 'photo']) {
        expect(encoded.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('rejection paths', () {
    test('tampered payload is rejected', () async {
      // Mutate AFTER signing: the signature no longer matches the bytes.
      final map = jsonDecode(await sign(rows)) as Map<String, dynamic>;
      (map['rows'] as List).first['price_cents'] = 1;
      final v = await ListingBundle.verify(jsonEncode(map),
          directory: trust.directory);
      expect(v.ok, isFalse);
      expect(v.error, 'bad-signature');
    });

    test('a salesman cannot sign a listing (provision-only role)', () async {
      final v = await ListingBundle.verify(
          await sign(rows, signerId: SigningTrust.salesmanId),
          directory: trust.directory);
      expect(v.ok, isFalse);
      expect(v.error, 'forbidden-role');
    });

    test('an unknown signer is rejected', () async {
      final stranger = await Signing.generateSigner();
      final v = await ListingBundle.verify(
          await Signing.signArtifactFile(ListingBundle(
            signerId: 'ghost',
            shopKey: 'hanouti',
            catalogVersion: 4,
            generatedAt: 1,
            rows: rows,
          ).toPayload(), stranger),
          directory: trust.directory);
      expect(v.ok, isFalse);
      expect(v.error, 'unknown-signer');
    });

    test('an unsigned bundle is rejected, never warned about', () async {
      final v = await ListingBundle.verify(
          Signing.splitArtifact(await sign(rows)).$1.toString(),
          directory: trust.directory);
      expect(v.ok, isFalse);
    });

    test('a malformed / traversal shop_key is rejected', () async {
      for (final bad in ['../evil', 'A', 'a/b', '']) {
        final payload = ListingBundle(
          signerId: SigningTrust.adminId,
          shopKey: bad,
          catalogVersion: 4,
          generatedAt: 1,
          rows: rows,
        ).toPayload();
        final v = await ListingBundle.verify(
            await Signing.signArtifactFile(
                payload, trust.seed(SigningTrust.adminId)),
            directory: trust.directory);
        expect(v.ok, isFalse, reason: bad);
      }
    });

    test('duplicate barcodes are rejected', () async {
      final dup = [
        ...rows,
        const ListingRow(barcode: '0011210006508', priceCents: 1, stockQty: 1),
      ];
      final v = await ListingBundle.verify(await sign(dup),
          directory: trust.directory);
      expect(v.ok, isFalse);
      expect(v.error, 'duplicate barcode');
    });

    test('negative price/stock are rejected', () async {
      for (final bad in [
        const ListingRow(barcode: 'x', priceCents: -1, stockQty: 0),
        const ListingRow(barcode: 'x', priceCents: 0, stockQty: -1),
      ]) {
        final v = await ListingBundle.verify(await sign([bad]),
            directory: trust.directory);
        expect(v.ok, isFalse, reason: bad.toString());
        expect(v.error, 'malformed row');
      }
    });

    test('malformed bundles never throw', () async {
      for (final json in ['', '{', '[]', 'null', '{"format": 123}']) {
        final v = await ListingBundle.verify(json, directory: trust.directory);
        expect(v.ok, isFalse, reason: json);
      }
    });
  });
}
