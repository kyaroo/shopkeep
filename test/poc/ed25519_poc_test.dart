/// POC — Ed25519 for the per-admin signing design.
///
/// Proves, on the real dependency and the real code path:
///   - a keypair can be generated,
///   - a payload signs and verifies,
///   - a tampered payload / wrong key fails,
///   - the key and signature sizes fit a QR / a delta payload.
///
/// Run: flutter test test/poc/ed25519_poc_test.dart
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ed25519 round-trip, tamper rejection and sizes', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    // The canonical payload pattern: sign the payload, signature excluded.
    final payload = utf8.encode(
      '{"format":"myhanout-catalog-delta","signer_id":"founder-admin",'
      '"base_version":1,"target_version":2}',
    );

    final signature = await algorithm.sign(payload, keyPair: keyPair);
    final sealed = Signature(signature.bytes, publicKey: publicKey);

    expect(await algorithm.verify(payload, signature: sealed), isTrue);

    // Tampered payload must not verify.
    final tampered = utf8.encode(
      '{"format":"myhanout-catalog-delta","signer_id":"founder-admin",'
      '"base_version":1,"target_version":3}',
    );
    expect(await algorithm.verify(tampered, signature: sealed), isFalse);

    // A different key must not verify.
    final otherKey = await Ed25519().newKeyPair();
    final otherPublic = await otherKey.extractPublicKey();
    final wrongKey = Signature(signature.bytes, publicKey: otherPublic);
    expect(await algorithm.verify(payload, signature: wrongKey), isFalse);

    // ignore: avoid_print
    print('Ed25519 POC: public=${publicKey.bytes.length}B '
        'private=${privateKey.length}B signature=${signature.bytes.length}B '
        'verify=true, tampered=false, wrong-key=false');
  });
}
