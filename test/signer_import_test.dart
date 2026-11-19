/// In-app signer import verification (decisions 2a / 3a / 4a).
///
/// Uses a THROWAWAY trust anchor (`SigningTrust`) — never `assets/signers.json`
/// and never the founder's real seeds. The directory is injected through the
/// fake settings service; `SignersDirectoryLoader` is given the throwaway root.
/// No SQLite file is opened here.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/signer_import.dart';
import 'package:myhanout/data/signing.dart';

import 'helpers/fake_settings.dart';
import 'helpers/signing_trust.dart';

String _envelope(String signerId, List<int> seed, {String? format}) =>
    jsonEncode(<String, dynamic>{
      'format': format ?? SignerSeedImport.format,
      'signer_id': signerId,
      'seed': base64Url.encode(seed),
    });

void main() {
  late SigningTrust trust;
  late FakeSettingsService settings;

  setUp(() async {
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope;
  });

  Future<SignerImportResult> import(String signerId, List<int> seed,
          {String? format}) =>
      SignerSeedImport.import(
        _envelope(signerId, seed, format: format),
        settings: settings,
        rootPublicKey: trust.rootPublic,
      );

  test('happy path: founder seed stored and activated', () async {
    final seed = trust.seed(SigningTrust.founderAdminId);
    final result = await import(SigningTrust.founderAdminId, seed);

    expect(result.ok, isTrue, reason: result.error);
    expect(result.role, SignerRole.founder);
    expect(result.activated, isTrue);
    expect(await settings.getSignerKey(SigningTrust.founderAdminId), seed);
    expect(await settings.getActiveSignerId(), SigningTrust.founderAdminId);
  });

  test('happy path: admin seed activated', () async {
    final result =
        await import(SigningTrust.adminId, trust.seed(SigningTrust.adminId));
    expect(result.ok, isTrue, reason: result.error);
    expect(result.role, SignerRole.admin);
    expect(result.activated, isTrue);
    expect(await settings.getActiveSignerId(), SigningTrust.adminId);
  });

  test('wrong seed length is refused', () async {
    final result = await import(
      SigningTrust.founderAdminId,
      List<int>.filled(31, 7),
    );
    expect(result.ok, isFalse);
    expect(result.error, SignerSeedImport.errBadSeedLength);
    expect(await settings.getSignerKey(SigningTrust.founderAdminId), isNull);
    expect(await settings.getActiveSignerId(), isNull);
  });

  test('unknown signer id is refused', () async {
    final result = await import('ghost-id', trust.seed(SigningTrust.adminId));
    expect(result.ok, isFalse);
    expect(result.error, SignerSeedImport.errUnknownSigner);
    expect(settings.signerKeys, isEmpty);
  });

  test('public key mismatch is refused', () async {
    // A valid 32-byte seed for a DIFFERENT signer must not be accepted for
    // founder-admin: derived public key would not match the directory entry.
    final result = await import(
      SigningTrust.founderAdminId,
      trust.seed(SigningTrust.adminId),
    );
    expect(result.ok, isFalse);
    expect(result.error, SignerSeedImport.errKeyMismatch);
    expect(settings.signerKeys, isEmpty);
    expect(await settings.getActiveSignerId(), isNull);
  });

  test('salesman seed stored but not activated, and cannot push', () async {
    final seed = trust.seed(SigningTrust.salesmanId);
    final result = await import(SigningTrust.salesmanId, seed);

    expect(result.ok, isTrue, reason: result.error);
    expect(result.role, SignerRole.salesman);
    expect(result.activated, isFalse);
    expect(await settings.getSignerKey(SigningTrust.salesmanId), seed);
    expect(await settings.getActiveSignerId(), isNull,
        reason: 'salesman must never become the active push signer');

    // Even if prefs are edited to point at the salesman, the push-time
    // re-check reads the role from the ROOT-verified directory and refuses.
    settings.activeSignerId = SigningTrust.salesmanId;
    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: trust.rootPublic,
    );
    expect(role, SignerRole.salesman);
    expect(SignerSeedImport.canPush(role), isFalse);
  });

  test('bad format and malformed envelopes are refused', () async {
    final badFormat = await import(
      SigningTrust.adminId,
      trust.seed(SigningTrust.adminId),
      format: 'myhanout-signers-v1',
    );
    expect(badFormat.error, SignerSeedImport.errBadFormat);

    final malformed = await SignerSeedImport.import(
      '{not json',
      settings: settings,
      rootPublicKey: trust.rootPublic,
    );
    expect(malformed.error, SignerSeedImport.errMalformed);
  });

  test('importing a salesman after admin activation keeps the active signer',
      () async {
    final adminResult =
        await import(SigningTrust.adminId, trust.seed(SigningTrust.adminId));
    expect(adminResult.ok, isTrue, reason: adminResult.error);
    expect(await settings.getActiveSignerId(), SigningTrust.adminId);

    // A salesman seed is stored but must never displace the active admin.
    final salesmanResult = await import(
      SigningTrust.salesmanId,
      trust.seed(SigningTrust.salesmanId),
    );
    expect(salesmanResult.ok, isTrue, reason: salesmanResult.error);
    expect(salesmanResult.role, SignerRole.salesman);
    expect(salesmanResult.activated, isFalse);
    expect(await settings.getSignerKey(SigningTrust.salesmanId),
        trust.seed(SigningTrust.salesmanId));
    expect(await settings.getActiveSignerId(), SigningTrust.adminId,
        reason: 'a salesman seed must never replace the active admin signer');

    // Push-time re-check still sees the admin and allows a push.
    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: trust.rootPublic,
    );
    expect(role, SignerRole.admin);
    expect(SignerSeedImport.canPush(role), isTrue);
  });

  test('directory rotation removing the active signer fails closed', () async {
    final founderResult = await import(
      SigningTrust.founderAdminId,
      trust.seed(SigningTrust.founderAdminId),
    );
    expect(founderResult.ok, isTrue, reason: founderResult.error);
    expect(await settings.getActiveSignerId(), SigningTrust.founderAdminId);

    // A newer, validly-signed directory that no longer lists the founder.
    final newer = await trust.buildDirectory(
      version: 8,
      signerIds: const [SigningTrust.adminId, SigningTrust.salesmanId],
    );

    await settings.saveSignersEnvelope(newer.envelope);

    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: trust.rootPublic,
    );
    expect(role, isNull,
        reason: 'the rotated directory no longer contains the active signer');
    expect(SignerSeedImport.canPush(role), isFalse);
  });

  test('fail-closed: tampered override falls back to baked root and refuses',
      () async {
    settings.activeSignerId = SigningTrust.founderAdminId;
    settings.signersEnvelope = 'not-a-valid-envelope';

    // The bad override makes the loader fall back to the baked directory,
    // which cannot verify against the throwaway root — so load throws and
    // activeRole must return null rather than a permissive role.
    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: trust.rootPublic,
    );
    expect(role, isNull);
    expect(SignerSeedImport.canPush(role), isFalse);
  });

  test('fail-closed: wrong root key cannot verify the directory', () async {
    settings.activeSignerId = SigningTrust.founderAdminId;
    settings.signersEnvelope = trust.directory.envelope;

    final wrongRoot =
        await Signing.publicKeyFromSeed(trust.seed(SigningTrust.salesmanId));
    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: wrongRoot,
    );
    expect(role, isNull);
    expect(SignerSeedImport.canPush(role), isFalse);
  });
}
