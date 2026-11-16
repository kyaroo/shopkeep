/// Shared trust fixture for the Ed25519 signing tests.
///
/// Builds a root key that signs a directory of signers (founder / admin /
/// salesman) plus the matching private seeds, so a test can sign as any role
/// and verify against the same directory.
library;

import 'dart:convert';

import 'package:myhanout/data/signing.dart';

class SigningTrust {
  final List<int> rootPrivate;
  final List<int> rootPublic;
  final SignersDirectory directory;
  final Map<String, List<int>> seeds;

  SigningTrust._(this.rootPrivate, this.rootPublic, this.directory, this.seeds);

  static const founderAdminId = 'founder-admin';
  static const adminId = 'admin-2';
  static const salesmanId = 'salesman-1';

  static Future<SigningTrust> create() async {
    final rootPrivate = await Signing.generateSigner();
    final rootPublic = await Signing.publicKeyFromSeed(rootPrivate);

    final seeds = <String, List<int>>{
      founderAdminId: await Signing.generateSigner(),
      adminId: await Signing.generateSigner(),
      salesmanId: await Signing.generateSigner(),
    };

    final payload = <String, dynamic>{
      'format': ArtifactFormat.signers,
      'alg': Signing.algorithm,
      'version': 7,
      'updated_at': 1718000000000,
      'signers': [
        for (final entry in seeds.entries)
          {
            'id': entry.key,
            'name': entry.key,
            'role': switch (entry.key) {
              founderAdminId => 'founder',
              salesmanId => 'salesman',
              _ => 'admin',
            },
            'public_key':
                base64Url.encode(await Signing.publicKeyFromSeed(entry.value)),
          },
      ],
    };

    final envelope = await Signing.signPayload(payload, rootPrivate);
    final directory = await Signing.verifyDirectoryWith(envelope, rootPublic);
    return SigningTrust._(rootPrivate, rootPublic, directory, seeds);
  }

  List<int> seed(String signerId) => seeds[signerId]!;

  /// A directory with a chosen version and/or signer set, signed by this
  /// trust's root. Used to exercise replace/removal/replay cases.
  Future<SignersDirectory> buildDirectory({
    int version = 7,
    List<String> signerIds = const [founderAdminId, adminId, salesmanId],
  }) async {
    final envelope = await Signing.signPayload(<String, dynamic>{
      'format': ArtifactFormat.signers,
      'alg': Signing.algorithm,
      'version': version,
      'updated_at': 1718000000000,
      'signers': [
        for (final id in signerIds)
          {
            'id': id,
            'name': id,
            'role': switch (id) {
              founderAdminId => 'founder',
              salesmanId => 'salesman',
              _ => 'admin',
            },
            'public_key': base64Url.encode(await Signing.publicKeyFromSeed(seed(id))),
          },
      ],
    }, rootPrivate);
    return Signing.verifyDirectoryWith(envelope, rootPublic);
  }

  /// A signed catalog delta file for [signerId].
  Future<String> deltaFile(
    String signerId, {
    int base = 100,
    int? target,
    List<Map<String, dynamic>> upserts = const [],
  }) =>
      Signing.signArtifactFile(<String, dynamic>{
        'format': CatalogDeltaFormat.catalogDelta,
        'alg': Signing.algorithm,
        'fileVersion': 2,
        'signer_id': signerId,
        'base_version': base,
        'target_version': target ?? base + 1,
        'generated_at': base + 1,
        'upserts': upserts,
        'deletes': <String>[],
      }, seed(signerId));

  /// A signed provisioning QR envelope for [signerId].
  Future<String> provisionEnvelope(
    String signerId, {
    String shopKey = 'maison-du-marche',
    String businessName = 'Maison du Marché',
    int ttlSeconds = 1800,
    String nonce = 'A3F9K2Q7',
  }) =>
      Signing.signPayload(<String, dynamic>{
        'format': CatalogDeltaFormat.provision,
        'alg': Signing.algorithm,
        'shop_key': shopKey,
        'business_name': businessName,
        'issued_at': DateTime.now().millisecondsSinceEpoch,
        'nonce': nonce,
        'ttl_seconds': ttlSeconds,
        'signer_id': signerId,
      }, seed(signerId));
}

/// Re-exported format constants so tests can import only this helper.
class CatalogDeltaFormat {
  static const catalogDelta = ArtifactFormat.catalogDelta;
  static const provision = ArtifactFormat.provision;
  static const signers = ArtifactFormat.signers;
}
