// CAT9 — distribution du catalogue (admin).
//
// Two seams are covered here, both pure (no UI, no SQLite, no network):
//   1. [ShopRow.fromMap] — the server's `catalog_version` must survive the
//      wire, because the whole version guard depends on it.
//   2. [CatalogPushBuilder.buildPayload] — the base/target guard: a shop whose
//      registered generation differs from the local catalog is refused before
//      any byte is written, and a valid delivery targets base + 1.
//
// Run: flutter test test/services/catalog_push_builder_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_push_service.dart';
import 'package:myhanout/services/catalog_delta_service.dart';
import 'package:myhanout/data/signing.dart';

import '../helpers/signing_trust.dart';

late SigningTrust trust;

Future<DeltaBuildResult> _push({
  required int localVersion,
  required int shopVersion,
  required List<CatalogEntry> entries,
}) =>
    CatalogPushBuilder.buildPayload(
      localVersion: localVersion,
      shopVersion: shopVersion,
      signerId: SigningTrust.founderAdminId,
      privateSeed: trust.seed(SigningTrust.founderAdminId),
      entries: entries,
    );

CatalogEntry _entry(String barcode, {String name = 'Produit'}) => CatalogEntry(
      barcode: barcode,
      name: name,
      category: 'grocery',
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  group('ShopRow.fromMap', () {
    test('carries catalog_version from the server', () {
      final row = ShopRow.fromMap({
        'shop_key': 'hanouti',
        'business_name': 'Hanouti',
        'created_at': 1794490202276,
        'device_id': 'mapper-owner-01',
        'created_by': null,
        'catalog_version': 7,
      });

      expect(row.shopKey, 'hanouti');
      expect(row.businessName, 'Hanouti');
      expect(row.catalogVersion, 7);
    });

    test('catalog_version defaults to 0 when absent (older server)', () {
      final row = ShopRow.fromMap({
        'shop_key': 'legacy',
        'business_name': 'Legacy',
        'created_at': 0,
      });

      // 0 = "never reported", which the screen treats as "no base yet".
      expect(row.catalogVersion, 0);
    });
  });

  group('CatalogPushBuilder', () {
    setUp(() async {
      trust = await SigningTrust.create();
    });

    test('fileName is stable and versioned', () {
      expect(CatalogPushBuilder.fileName('hanouti', 3),
          'catalog_hanouti_v3.myhanout');
    });

    test('builds a signed delta with base=shop version and target=base+1',
        () async {
      final result = await _push(
        localVersion: 4,
        shopVersion: 4,
        entries: [_entry('6111000000123')],
      );

      final map = jsonDecode(result.json) as Map<String, dynamic>;
      expect(map['base_version'], 4);
      expect(map['target_version'], 5);
      expect(map['signature'], isA<String>());
      expect(result.upserts, 1);
      expect(result.photosUntouched, isTrue);

      // The payload must verify against the same directory the receiver uses.
      final verification = await CatalogDelta.verify(
        result.json,
        directory: trust.directory,
      );
      expect(verification.ok, isTrue, reason: verification.error);
      expect(verification.delta!.baseVersion, 4);
      expect(verification.delta!.targetVersion, 5);
      expect(verification.delta!.upserts.single.barcode, '6111000000123');
      expect(verification.delta!.signerId, SigningTrust.founderAdminId);
    });

    test('a shop that never reported a version (0) is refused', () async {
      await expectLater(
        () => _push(
          localVersion: 1,
          shopVersion: 0,
          entries: [_entry('6111000000123')],
        ),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('local ahead of the shop is refused (would skip a generation)',
        () async {
      await expectLater(
        () => _push(
          localVersion: 5,
          shopVersion: 4,
          entries: [_entry('6111000000123')],
        ),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('shop ahead of local is refused (stale admin catalog)', () async {
      await expectLater(
        () => _push(
          localVersion: 3,
          shopVersion: 4,
          entries: [_entry('6111000000123')],
        ),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('the guard exception carries both versions for the UI', () async {
      try {
        await _push(
          localVersion: 2,
          shopVersion: 9,
          entries: const [],
        );
        fail('expected CatalogBaseMismatchException');
      } on CatalogBaseMismatchException catch (e) {
        expect(e.local, 2);
        expect(e.remote, 9);
      }
    });

    test('a delta that jumps the version is rejected on verify', () async {
      // Build a legitimate base+1 payload, then tamper the target upward and
      // re-sign it: the receiver must refuse rather than desync the catalog.
      final result = await _push(
        localVersion: 4,
        shopVersion: 4,
        entries: [_entry('6111000000123')],
      );
      final map = Map<String, dynamic>.from(
          jsonDecode(result.json) as Map<String, dynamic>);
      map.remove('signature');
      map['target_version'] = 999;
      final forged = await Signing.signArtifactFile(map, trust.seed(SigningTrust.founderAdminId));
      final verification = await CatalogDelta.verify(
        forged,
        directory: trust.directory,
      );
      expect(verification.ok, isFalse);
      expect(verification.error, 'version jump');
    });
  });
}
