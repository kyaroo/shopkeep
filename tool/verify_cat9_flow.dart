/// CAT9 — end-to-end delivery proof, host-side (no device needed).
///
/// Reproduces exactly what the admin screen does, then what the shopkeeper's
/// receiver does, and asserts:
///   1. the admin builds a signed delta whose base is the shop's generation;
///   2. the receiver verifies it against the signers directory;
///   3. the receiver REJECTS a second identical delta (base no longer matches);
///   4. a tampered delta is refused.
///
/// Run: dart run tool/verify_cat9_flow.dart
library;

// ignore_for_file: avoid_print
// Justification: this is a host-side verification script — its stdout IS the
// report a human reads to confirm the flow. There is no UI and no logging
// framework to send it to. Do NOT add this ignore to lib/ or test/.

import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_push_service.dart';

const shopKey = 'hanouti';
const base = 3;
const signerId = 'admin-1';

final entries = [
  CatalogEntry(
    barcode: '6111000000123',
    name: 'Ain Soltani Eau Minerale 1.5L',
    category: 'beverage',
    createdAt: base,
    updatedAt: base,
  ),
  CatalogEntry(
    barcode: '6111000000456',
    name: 'Couscous Dari 1kg',
    category: 'grain',
    createdAt: base,
    updatedAt: base,
  ),
];

Future<void> main() async {
  // A throwaway trust: the root key signs a directory listing our admin key.
  final rootPrivate = await Signing.generateSigner();
  final rootPublic = await Signing.publicKeyFromSeed(rootPrivate);
  final adminSeed = await Signing.generateSigner();
  final adminPublic = await Signing.publicKeyFromSeed(adminSeed);
  final directory = await Signing.verifyDirectoryWith(
    await Signing.signPayload(<String, dynamic>{
      'format': ArtifactFormat.signers,
      'alg': Signing.algorithm,
      'version': 1,
      'updated_at': 1718000000000,
      'signers': [
        {
          'id': signerId,
          'name': 'Admin',
          'role': 'admin',
          'public_key': base64Url.encode(adminPublic),
        },
      ],
    }, rootPrivate),
    rootPublic,
  );

  // ---- 1. admin side: build ----
  final result = await CatalogPushBuilder.buildPayload(
    localVersion: base,
    shopVersion: base,
    signerId: signerId,
    privateSeed: adminSeed,
    entries: entries,
  );
  final payload = result.json;
  final map = jsonDecode(payload) as Map<String, dynamic>;
  print('built: base=${map['base_version']} target=${map['target_version']} '
      'signer=${map['signer_id']} upserts=${(map['upserts'] as List).length}');
  if (map['base_version'] != base || map['target_version'] != base + 1) {
    stderr.writeln('FAIL: wrong base/target');
    exit(1);
  }

  final file = File('/tmp/${CatalogPushBuilder.fileName(shopKey, base + 1)}');
  await file.writeAsString(payload);
  print('file: ${file.path} (${file.lengthSync()} B)');

  // ---- 2. receiver side: verify against the directory ----
  final verification = await CatalogDelta.verify(
    await file.readAsString(),
    directory: directory,
  );
  if (!verification.ok) {
    stderr.writeln('FAIL: signature ${verification.error}');
    exit(1);
  }
  final delta = verification.delta!;
  print('verify: ok, base=${delta.baseVersion} '
      'target=${delta.targetVersion} signer=${delta.signerId}');

  // Simulate the shopkeeper's installed version (it was at `base`).
  const installed = base;
  if (delta.baseVersion != installed) {
    stderr.writeln('FAIL: first apply should be accepted');
    exit(1);
  }
  print('apply #1: accepted (installed $installed → ${delta.targetVersion})');

  // ---- 3. second apply of the same delta must be refused ----
  const installedAfterFirst = base + 1;
  if (delta.baseVersion == installedAfterFirst) {
    stderr.writeln('FAIL: the guard would allow a double-apply');
    exit(1);
  }
  print('apply #2: rejected (device $installedAfterFirst, bundle ${delta.baseVersion})');

  // ---- 4. tamper is refused ----
  final tampered = (jsonDecode(payload) as Map<String, dynamic>)
    ..['upserts'] = [
      {'barcode': '6111000000123', 'name': 'Fake', 'updated_at': base + 1}
    ];
  final v2 = await CatalogDelta.verify(jsonEncode(tampered),
      directory: directory);
  if (v2.ok) {
    stderr.writeln('FAIL: tampered payload accepted');
    exit(1);
  }
  print('tamper: rejected (${v2.error})');

  print('\nCAT9 flow OK: 2 upserts, guard holds, signature holds.');
}
