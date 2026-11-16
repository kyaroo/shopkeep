/// Phase 1 — signing foundation: canonical JSON, the verify chain, roles and
/// the baked directory.
///
/// Covers spec §10 criteria 1–3, 13–16 (the parts that do not need UI or the
/// camera).
///
/// Run: flutter test test/poc/signing_poc_test.dart
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/signing.dart';

/// A self-contained trust setup: a root key that signs a directory of signers.
class _Trust {
  final List<int> rootPrivate;
  final List<int> rootPublic;
  final SignersDirectory directory;
  final Map<String, List<int>> seeds;

  _Trust(this.rootPrivate, this.rootPublic, this.directory, this.seeds);
}

Future<_Trust> _newTrust() async {
  final rootPrivate = await Signing.generateSigner();
  final rootPublic = await Signing.publicKeyFromSeed(rootPrivate);

  final founderPrivate = await Signing.generateSigner();
  final adminPrivate = await Signing.generateSigner();
  final salesmanPrivate = await Signing.generateSigner();

  final payload = <String, dynamic>{
    'format': ArtifactFormat.signers,
    'alg': Signing.algorithm,
    'version': 7,
    'updated_at': 1718000000000,
    'signers': [
      {
        'id': 'founder-admin',
        'name': 'Manu',
        'role': 'founder',
        'public_key': base64Url.encode(await Signing.publicKeyFromSeed(founderPrivate)),
      },
      {
        'id': 'admin-2',
        'name': 'Sara',
        'role': 'admin',
        'public_key': base64Url.encode(await Signing.publicKeyFromSeed(adminPrivate)),
      },
      {
        'id': 'salesman-1',
        'name': 'Omar',
        'role': 'salesman',
        'public_key': base64Url.encode(await Signing.publicKeyFromSeed(salesmanPrivate)),
      },
    ],
  };
  final envelope = await Signing.signPayload(payload, rootPrivate);
  return _Trust(
    rootPrivate,
    rootPublic,
    await Signing.verifyDirectoryWith(envelope, rootPublic),
    {
      'founder-admin': founderPrivate,
      'admin-2': adminPrivate,
      'salesman-1': salesmanPrivate,
    },
  );
}

const _deltaRoles = {SignerRole.founder, SignerRole.admin};
const _provisionRoles = {SignerRole.founder, SignerRole.admin, SignerRole.salesman};

Future<String> _provisionEnvelope(_Trust t, String signerId) =>
    Signing.signPayload(<String, dynamic>{
      'format': ArtifactFormat.provision,
      'alg': Signing.algorithm,
      'shop_key': 'maison-du-marche',
      'business_name': 'Maison du Marché',
      'issued_at': 1718000000000,
      'nonce': 'A3F9K2Q7',
      'ttl_seconds': 1800,
      'signer_id': signerId,
    }, t.seeds[signerId]!);

Future<String> _deltaFile(_Trust t, String signerId, {int? target}) =>
    Signing.signArtifactFile(<String, dynamic>{
      'format': ArtifactFormat.catalogDelta,
      'alg': Signing.algorithm,
      'fileVersion': 2,
      'signer_id': signerId,
      'base_version': 100,
      'target_version': target ?? 101,
      'generated_at': 101,
      'upserts': [],
      'deletes': <String>[],
    }, t.seeds[signerId]!);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  test('baked assets/signers.json verifies against the baked root key', () async {
    final envelope = await rootBundle.loadString('assets/signers.json');
    final dir = await Signing.verifyDirectory(envelope);
    expect(dir.signers, isNotEmpty);
    expect(dir.version, greaterThanOrEqualTo(1));
    for (final s in dir.signers) {
      expect(s.publicKey.length, 32);
    }
    // ignore: avoid_print
    print('baked directory: version=${dir.version}, '
        'signers=${dir.signers.map((s) => '${s.id}:${s.role.name}').join(', ')}');
  });

  test('a one-byte tamper of the directory is rejected', () async {
    final t = await _newTrust();
    final parts = t.directory.envelope.split('.');
    final payload = String.fromCharCodes(
        base64Url.decode(base64Url.normalize(parts[0])));
    final flipped = payload.replaceFirst('"version":7', '"version":8');
    final tampered = '${base64Url.encode(utf8.encode(flipped))}.${parts[1]}';
    await expectLater(
      () => Signing.verifyDirectoryWith(tampered, t.rootPublic),
      throwsA(isA<FormatException>()),
    );
  });

  test('envelope verify: listed signer OK, unknown signer and bad format rejected',
      () async {
    final t = await _newTrust();

    final ok = await Signing.verifyEnvelope(await _provisionEnvelope(t, 'admin-2'),
        directory: t.directory,
        expectedFormat: ArtifactFormat.provision,
        allowedRoles: _provisionRoles);
    expect(ok.ok, isTrue);
    expect(ok.signer!.name, 'Sara');

    final stranger = await Signing.generateSigner();
    final strangerEnvelope = await Signing.signPayload(<String, dynamic>{
      'format': ArtifactFormat.provision,
      'alg': Signing.algorithm,
      'signer_id': 'ghost',
    }, stranger);
    final unknown = await Signing.verifyEnvelope(strangerEnvelope,
        directory: t.directory,
        expectedFormat: ArtifactFormat.provision,
        allowedRoles: _provisionRoles);
    expect(unknown.ok, isFalse);
    expect(unknown.error, VerifyResult.errUnknownSigner);

    // A provisioning envelope must never satisfy the delta verifier.
    final wrongType = await Signing.verifyEnvelope(await _provisionEnvelope(t, 'admin-2'),
        directory: t.directory,
        expectedFormat: ArtifactFormat.catalogDelta,
        allowedRoles: _deltaRoles);
    expect(wrongType.error, VerifyResult.errUnknownFormat);
  });

  test('roles: a salesman provisions but cannot push a catalog delta', () async {
    final t = await _newTrust();

    final provision = await Signing.verifyEnvelope(
        await _provisionEnvelope(t, 'salesman-1'),
        directory: t.directory,
        expectedFormat: ArtifactFormat.provision,
        allowedRoles: _provisionRoles);
    expect(provision.ok, isTrue);

    final delta = await Signing.verifyEnvelope(
        await _provisionEnvelope(t, 'salesman-1'),
        directory: t.directory,
        expectedFormat: ArtifactFormat.catalogDelta,
        allowedRoles: _deltaRoles);
    expect(delta.error, VerifyResult.errUnknownFormat);

    // A delta signed by the salesman is well-formed but forbidden.
    final salesmanDelta = await Signing.signArtifactFile(<String, dynamic>{
      'format': ArtifactFormat.catalogDelta,
      'alg': Signing.algorithm,
      'fileVersion': 2,
      'signer_id': 'salesman-1',
      'base_version': 100,
      'target_version': 101,
    }, t.seeds['salesman-1']!);
    final decoded = Signing.decodeStrict(salesmanDelta);
    final sig = (decoded as Map).remove('signature');
    final envelope = Signing.wrap(
        Signing.canonicalize(Map<String, dynamic>.from(decoded)),
        base64Url.decode(base64Url.normalize(sig as String)));
    final forbidden = await Signing.verifyEnvelope(envelope,
        directory: t.directory,
        expectedFormat: ArtifactFormat.catalogDelta,
        allowedRoles: _deltaRoles);
    expect(forbidden.error, VerifyResult.errForbiddenRole);
  });

  test('delta file round-trips: canonical bytes verify, tamper fails', () async {
    final t = await _newTrust();
    final file = await _deltaFile(t, 'admin-2');
    final (payload, signature) = Signing.splitArtifact(file);
    expect(payload['signer_id'], 'admin-2');
    expect(payload['target_version'], 101);

    final ok = await Signing.verifyEnvelope(
        Signing.wrap(Signing.canonicalize(payload), signature),
        directory: t.directory,
        expectedFormat: ArtifactFormat.catalogDelta,
        allowedRoles: _deltaRoles);
    expect(ok.ok, isTrue);

    final bad = await Signing.verifyEnvelope(
        Signing.wrap(Signing.canonicalize({...payload, 'target_version': 999}),
            signature),
        directory: t.directory,
        expectedFormat: ArtifactFormat.catalogDelta,
        allowedRoles: _deltaRoles);
    expect(bad.error, VerifyResult.errBadSignature);
  });

  test('canonical JSON: keys sorted, duplicate keys rejected', () {
    expect(Signing.canonicalize({'b': 1, 'a': 2}), '{"a":2,"b":1}');
    expect(Signing.canonicalize({
      'z': {'d': 1, 'c': 2},
      'a': [3, 2]
    }), '{"a":[3,2],"z":{"c":2,"d":1}}');

    expect(() => Signing.decodeStrict('{"a":1,"a":2}'),
        throwsA(isA<FormatException>()));
    expect(Signing.decodeStrict('{"a":1}'), {'a': 1});
  });
}
