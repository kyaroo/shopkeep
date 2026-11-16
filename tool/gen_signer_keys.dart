// Generates the founder ROOT keypair and the first signer keypairs, then writes
// the baked signers directory `assets/signers.json`.
//
// The ROOT key signs the directory only. Its PRIVATE half is printed once and
// must be imported into the founder's device — never committed, never logged.
//
// Usage:
//   dart run tool/gen_signer_keys.dart
//
// Re-running rotates every key: re-issue QRs and re-bake the directory.
import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/signing.dart';

Future<void> main(List<String> args) async {
  final rootPrivate = await Signing.generateSigner();
  final rootPublic = await Signing.publicKeyFromSeed(rootPrivate);

  final founderPrivate = await Signing.generateSigner();
  final founderPublic = await Signing.publicKeyFromSeed(founderPrivate);

  final salesmanPrivate = await Signing.generateSigner();
  final salesmanPublic = await Signing.publicKeyFromSeed(salesmanPrivate);

  final payload = <String, dynamic>{
    'format': ArtifactFormat.signers,
    'alg': Signing.algorithm,
    'version': 1,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
    'signers': [
      {
        'id': 'founder-admin',
        'name': 'Fondateur',
        'role': 'founder',
        'public_key': base64Url.encode(founderPublic),
      },
      {
        'id': 'salesman-1',
        'name': 'Omar',
        'role': 'salesman',
        'public_key': base64Url.encode(salesmanPublic),
      },
    ],
  };

  final envelope = await Signing.signPayload(payload, rootPrivate);
  final out = File('assets/signers.json');
  await out.writeAsString(envelope); // exact bytes; no trailing newline

  final baked = await Signing.verifyDirectoryWith(envelope, rootPublic);
  stdout.writeln('wrote ${out.path} '
      '(${baked.signers.length} signers, version ${baked.version})');
  stdout.writeln();
  stdout.writeln('kRootPublicKeyB64 = '
      "'${base64Url.encode(rootPublic)}'");
  stdout.writeln();
  stdout.writeln('PRIVATE KEYS — keep offline, never commit, never log:');
  stdout.writeln('  root           ${base64Url.encode(rootPrivate)}');
  stdout.writeln('  founder-admin  ${base64Url.encode(founderPrivate)}');
  stdout.writeln('  salesman-1     ${base64Url.encode(salesmanPrivate)}');
}
