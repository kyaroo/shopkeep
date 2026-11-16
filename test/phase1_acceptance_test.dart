/// Phase-1 acceptance criteria — the cases the spec lists but the feature tests
/// did not cover: directory distribution (replace/version/tamper/root), the
/// nonce replay guard, provisioning attribution, signer_log, malformed input.
///
/// Run: flutter test test/phase1_acceptance_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_db.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/data/signers_directory.dart';
import 'package:myhanout/data/signing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/signing_trust.dart';

void main() {
  late SigningTrust trust;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Config.init();
    trust = await SigningTrust.create();
  });

  const store = ConfigSettingsService();

  Future<SignersDirectory> load() => SignersDirectoryLoader.load(
        settings: store,
        rootPublicKey: trust.rootPublic,
      );

  group('directory distribution (QR-only trust material)', () {
    test('4. a higher version is adopted; a lower/equal one is a no-op',
        () async {
      final low = await trust.buildDirectory(version: 5);
      final high = await trust.buildDirectory(version: 9);

      expect((await SignersDirectoryLoader.replace(low.envelope,
              settings: store, rootPublicKey: trust.rootPublic))!
          .version, 5);
      expect((await SignersDirectoryLoader.replace(high.envelope,
              settings: store, rootPublicKey: trust.rootPublic))!
          .version, 9);

      // Replaying the same or an older directory changes nothing.
      expect(await SignersDirectoryLoader.replace(high.envelope,
          settings: store, rootPublicKey: trust.rootPublic), isNull);
      expect(await SignersDirectoryLoader.replace(low.envelope,
          settings: store, rootPublicKey: trust.rootPublic), isNull);

      expect((await load()).version, 9);
    });

    test('5. a removed signer is rejected once the new directory lands',
        () async {
      final full = await trust.buildDirectory();
      await SignersDirectoryLoader.replace(full.envelope,
          settings: store, rootPublicKey: trust.rootPublic);

      final adminDelta = await trust.deltaFile(SigningTrust.adminId);
      expect((await CatalogDelta.verify(adminDelta, directory: await load()))
          .ok, isTrue);

      final reduced = await trust.buildDirectory(
          version: 8,
          signerIds: [SigningTrust.founderAdminId, SigningTrust.salesmanId]);
      await SignersDirectoryLoader.replace(reduced.envelope,
          settings: store, rootPublicKey: trust.rootPublic);

      final v = await CatalogDelta.verify(adminDelta, directory: await load());
      expect(v.ok, isFalse);
      expect(v.error, 'unknown-signer');
    });

    test('9. a tampered persisted override never wins over the baked asset',
        () async {
      // Criterion 9 / CR-01: the override is re-verified on EVERY load.
      await store.saveSignersEnvelope('tampered.not-a-valid-envelope');
      final dir = await SignersDirectoryLoader.load();
      expect(dir.signers, isNotEmpty);
      expect(dir.version, greaterThanOrEqualTo(1));
    });

    test('13. duplicate signer ids and bad key lengths are rejected', () async {
      Future<String> dirEnvelope(List<Map<String, dynamic>> signers) =>
          Signing.signPayload(<String, dynamic>{
        'format': ArtifactFormat.signers,
        'alg': Signing.algorithm,
        'version': 1,
        'updated_at': 1718000000000,
        'signers': signers,
      }, trust.rootPrivate);

      final dup = await dirEnvelope([
        {
          'id': 'admin-2',
          'name': 'a',
          'role': 'admin',
          'public_key': base64Url.encode(await Signing.publicKeyFromSeed(
              trust.seed(SigningTrust.adminId))),
        },
        {
          'id': 'admin-2',
          'name': 'b',
          'role': 'admin',
          'public_key': base64Url.encode(await Signing.publicKeyFromSeed(
              trust.seed(SigningTrust.adminId))),
        },
      ]);
      await expectLater(
        () => Signing.verifyDirectoryWith(dup, trust.rootPublic),
        throwsA(isA<FormatException>()),
      );

      final shortKey = await dirEnvelope([
        {
          'id': 'admin-2',
          'name': 'a',
          'role': 'admin',
          'public_key': base64Url.encode(Uint8List(31)),
        },
      ]);
      await expectLater(
        () => Signing.verifyDirectoryWith(shortKey, trust.rootPublic),
        throwsA(isA<FormatException>()),
      );
    });

    test('14. a directory signed by the wrong root is refused; the previous one '
        'is retained', () async {
      final first = await trust.buildDirectory(version: 3);
      await SignersDirectoryLoader.replace(first.envelope,
          settings: store, rootPublicKey: trust.rootPublic);

      final other = await SigningTrust.create();
      final forged = await other.buildDirectory(version: 4);
      expect(await SignersDirectoryLoader.replace(forged.envelope,
          settings: store, rootPublicKey: trust.rootPublic), isNull);

      expect((await load()).version, 3);
    });

    test('16b. a directory must be root-signed, never admin-signed', () async {
      final adminSigned = await Signing.signPayload(<String, dynamic>{
        'format': ArtifactFormat.signers,
        'alg': Signing.algorithm,
        'version': 2,
        'updated_at': 1718000000000,
        'signers': [
          {
            'id': SigningTrust.adminId,
            'name': 'a',
            'role': 'admin',
            'public_key': base64Url.encode(await Signing.publicKeyFromSeed(
                trust.seed(SigningTrust.adminId))),
          },
        ],
      }, trust.seed(SigningTrust.adminId)); // wrong key: an admin, not the root

      await expectLater(
        () => Signing.verifyDirectoryWith(adminSigned, trust.rootPublic),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('provisioning attribution and replay', () {
    test('8. provisioned_by / provisioned_by_id round-trip', () async {
      expect(await store.getProvisionedBy('hanouti'), isNull);
      await store.saveProvisionedBy('hanouti', 'Omar', SigningTrust.salesmanId);
      expect(await store.getProvisionedBy('hanouti'), 'Omar');
      expect(await store.getProvisionedById('hanouti'), SigningTrust.salesmanId);
    });

    test('12. a provisioning nonce is single-use within its TTL', () async {
      expect(await store.isNonceUsed('N1'), isFalse);
      await store.markNonceUsed('N1', const Duration(seconds: 1800));
      expect(await store.isNonceUsed('N1'), isTrue);
      // An already-expired nonce is pruned, not remembered forever.
      await store.markNonceUsed('N2', const Duration(seconds: -1));
      expect(await store.isNonceUsed('N2'), isFalse);
    });
  });

  group('attribution log', () {
    test('17. signer_log rows are written and queryable', () async {
      await CatalogDb.instance.logSigner(
        version: 101,
        signedBy: 'Sara',
        signedById: SigningTrust.adminId,
        entryCount: 3,
        appliedOnShop: 'hanouti',
      );
      final rows = await CatalogDb.instance.signerLog();
      final row = rows.first;
      expect(row['version'], 101);
      expect(row['signed_by'], 'Sara');
      expect(row['signed_by_id'], SigningTrust.adminId);
      expect(row['entry_count'], 3);
      expect(row['applied_on_shop'], 'hanouti');
      expect(row['applied_at'], isNotNull);
    });
  });

  group('malformed input never throws', () {
    test('11. malformed deltas are rejected, not thrown', () async {
      final malformed = <String>[
        '',
        '{',
        '[]',
        'null',
        '{"format": 123}',
        '{"format": "myhanout-catalog-delta"}',
        '{"format":"myhanout-catalog-delta","format":"x"}', // duplicate key
        '{"format":"myhanout-catalog-delta","signer_id":123}',
        '{"format":"myhanout-catalog-delta","signer_id":"admin-2",'
            '"base_version":"x","target_version":2,"signature":"AAAA"}',
        '{"format":"myhanout-catalog-delta","signer_id":"admin-2",'
            '"base_version":1,"target_version":2,"signature":"!!!"}',
      ];
      for (final json in malformed) {
        final v = await CatalogDelta.verify(json, directory: trust.directory);
        expect(v.ok, isFalse, reason: json);
      }
    });
  });
}
