// CAT9 — distribution du catalogue (admin).
//
// Two seams are covered here, both pure (no UI, no SQLite, no network):
//   1. [ShopRow.fromMap] — the server's `catalog_version` must survive the
//      wire, because the whole version guard depends on it.
//   2. [CatalogPushBuilder.buildPayload] — the base/target guard: a shop whose
//      registered generation differs from the target is refused before any
//      byte is written, and the target may span several generations.
//
// Run: flutter test test/services/catalog_push_builder_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_delta_service.dart';
import 'package:myhanout/services/catalog_push_service.dart';

import '../helpers/signing_trust.dart';

late SigningTrust trust;

Future<DeltaBuildResult> _push({
  required int localVersion,
  required int shopVersion,
  required int targetVersion,
  List<CatalogEntry> entries = const [],
}) =>
    CatalogPushBuilder.buildPayload(
      localVersion: localVersion,
      shopVersion: shopVersion,
      targetVersion: targetVersion,
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

    test('builds a signed single-generation delta (base+1)', () async {
      final result = await _push(
        localVersion: 5,
        shopVersion: 4,
        targetVersion: 5,
        entries: [_entry('6111000000123')],
      );

      final map = jsonDecode(result.json) as Map<String, dynamic>;
      expect(map['base_version'], 4);
      expect(map['target_version'], 5);
      expect(map['signature'], isA<String>());
      expect(result.upserts, 1);
      expect(result.photosUntouched, isTrue);

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

    test('builds a signed MULTI-generation delta (target > base+1)', () async {
      final result = await _push(
        localVersion: 7,
        shopVersion: 4,
        targetVersion: 7,
        entries: [_entry('6111000000123')],
      );

      final map = jsonDecode(result.json) as Map<String, dynamic>;
      expect(map['base_version'], 4);
      expect(map['target_version'], 7);

      final verification = await CatalogDelta.verify(
        result.json,
        directory: trust.directory,
      );
      expect(verification.ok, isTrue, reason: verification.error);
      expect(verification.delta!.baseVersion, 4);
      expect(verification.delta!.targetVersion, 7);
    });

    test('a shop that never reported a version (0) is refused', () async {
      await expectLater(
        () => _push(localVersion: 1, shopVersion: 0, targetVersion: 1),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('target == shop is refused (nothing to deliver)', () async {
      await expectLater(
        () => _push(localVersion: 4, shopVersion: 4, targetVersion: 4),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('shop ahead of the admin target is refused (M > N)', () async {
      await expectLater(
        () => _push(localVersion: 7, shopVersion: 9, targetVersion: 7),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('admin local not at the target is refused (stale admin catalog)',
        () async {
      await expectLater(
        () => _push(localVersion: 3, shopVersion: 2, targetVersion: 7),
        throwsA(isA<CatalogBaseMismatchException>()),
      );
    });

    test('the guard exception carries both versions for the UI', () async {
      try {
        await _push(localVersion: 2, shopVersion: 9, targetVersion: 9);
        fail('expected CatalogBaseMismatchException');
      } on CatalogBaseMismatchException catch (e) {
        expect(e.local, 2);
        expect(e.remote, 9);
      }
    });

    test('a delta that does not move forward is rejected on verify', () async {
      // Re-sign a payload whose target was tampered DOWNWARD: the receiver
      // must refuse rather than desync the catalog.
      final result = await _push(
        localVersion: 5,
        shopVersion: 4,
        targetVersion: 5,
        entries: [_entry('6111000000123')],
      );
      final map = Map<String, dynamic>.from(
          jsonDecode(result.json) as Map<String, dynamic>);
      map.remove('signature');
      map['target_version'] = 3;
      final forged = await Signing.signArtifactFile(
          map, trust.seed(SigningTrust.founderAdminId));
      final verification = await CatalogDelta.verify(
        forged,
        directory: trust.directory,
      );
      expect(verification.ok, isFalse);
      expect(verification.error, 'version jump');
    });
  });
}
