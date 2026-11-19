import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Signer roles and the capabilities attached to them.
enum SignerRole { founder, admin, salesman }

/// Artifact types, carried in every signed payload's `format` field so a
/// verifier can route **before** doing any signature work.
class ArtifactFormat {
  static const signers = 'myhanout-signers-v1';
  static const provision = 'myhanout-provision-v1';
  static const catalogDelta = 'myhanout-catalog-delta';

  /// In-app signer seed envelope (QR / `.myhanoutseed` file).
  static const signerSeed = 'myhanout-signer-seed-v1';
}

/// Baked trust anchor: the founder ROOT public key (Ed25519, 32 bytes,
/// base64url). Public by design — it only verifies the signers directory, so a
/// leaked APK cannot forge anything.
///
/// Generated once by `tool/gen_signer_keys.dart`; the private half never
/// leaves the founder's device.
const String kRootPublicKeyB64 = 'bzQmWdafMHVj2RnGofETUR1d7EPcdQLxQwHfRxplxAE=';

/// One entry of the signers directory.
class SignerEntry {
  final String id;
  final String name;
  final SignerRole role;
  final List<int> publicKey;

  const SignerEntry({
    required this.id,
    required this.name,
    required this.role,
    required this.publicKey,
  });

  factory SignerEntry.fromMap(Map<String, dynamic> m) {
    final role = switch (m['role']) {
      'founder' => SignerRole.founder,
      'admin' => SignerRole.admin,
      'salesman' => SignerRole.salesman,
      _ => throw const FormatException('unknown role'),
    };
    final key = base64Url.decode(base64Url.normalize(m['public_key'] as String));
    if (key.length != 32) {
      throw const FormatException('public_key must be 32 bytes');
    }
    return SignerEntry(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      role: role,
      publicKey: key,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
        'public_key': base64Url.encode(publicKey),
      };
}

/// The parsed signers directory. [envelope] is kept verbatim so the override
/// can be re-verified on every load (CR-01).
class SignersDirectory {
  final int version;
  final int updatedAt;
  final List<SignerEntry> signers;
  final String envelope;

  const SignersDirectory({
    required this.version,
    required this.updatedAt,
    required this.signers,
    required this.envelope,
  });

  SignerEntry? byId(String id) {
    for (final s in signers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'format': ArtifactFormat.signers,
        'alg': Signing.algorithm,
        'version': version,
        'updated_at': updatedAt,
        'signers': signers.map((s) => s.toMap()).toList(),
      };
}

/// Outcome of a verify. [error] is one of the stable rejection codes the UI and
/// tests match on.
class VerifyResult {
  final bool ok;
  final SignerEntry? signer;
  final String? error;
  final Map<String, dynamic>? payload;

  const VerifyResult._(this.ok, this.signer, this.error, this.payload);

  factory VerifyResult.ok(SignerEntry signer, Map<String, dynamic> payload) =>
      VerifyResult._(true, signer, null, payload);
  factory VerifyResult.fail(String error) =>
      VerifyResult._(false, null, error, null);

  static const errNotJson = 'not-json';
  static const errUnknownFormat = 'unknown-format';
  static const errMissingSignature = 'missing-signature';
  static const errBadSignature = 'bad-signature';
  static const errUnknownSigner = 'unknown-signer';
  static const errForbiddenRole = 'forbidden-role';
  static const errMalformedField = 'malformed-field';
  static const errDuplicateKey = 'duplicate-key';
}

class Signing {
  static const String algorithm = 'ed25519';
  static const int publicKeyLength = 32;

  static final Ed25519 _ed = Ed25519();

  /// The baked root public key bytes. Tests may substitute their own root via
  /// [SignersDirectoryLoader.load]'s `rootPublicKey`.
  static List<int> get bakedRootPublicKey =>
      base64Url.decode(base64Url.normalize(kRootPublicKeyB64));
  static final List<int> _rootPublic =
      base64Url.decode(base64Url.normalize(kRootPublicKeyB64));

  // ---- canonical JSON -----------------------------------------------------

  /// UTF-8, keys sorted, no whitespace. Both producer and verifier must sign
  /// and verify these exact bytes.
  static String canonicalize(Map<String, dynamic> payload) =>
      jsonEncode(_sorted(payload));

  static dynamic _sorted(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return <String, dynamic>{for (final k in keys) k: _sorted(value[k])};
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }

  /// Decodes JSON and **rejects duplicate keys** (last-wins would silently
  /// normalise a hostile payload).
  static dynamic decodeStrict(String source) {
    final parser = _StrictJsonParser(source);
    final value = parser.parseValue();
    parser.skipWhitespace();
    if (!parser.atEnd) throw const FormatException('trailing characters');
    return value;
  }

  /// Parses a signed artifact file: `signature` is stripped, the remaining
  /// payload re-encoded canonically. Returns (payload, signature).
  static (Map<String, dynamic>, List<int>) splitArtifact(String json) {
    final map = decodeStrict(json);
    if (map is! Map) throw const FormatException('artifact must be an object');
    final sig = map.remove('signature');
    if (sig is! String || sig.isEmpty) {
      throw const FormatException(VerifyResult.errMissingSignature);
    }
    return (Map<String, dynamic>.from(map), base64Url.decode(base64Url.normalize(sig)));
  }

  // ---- envelopes (QR / directory) ----------------------------------------

  /// Wraps already-canonical payload bytes: `base64url(payload).base64url(sig)`.
  static String wrap(String payloadJson, List<int> signature) =>
      '${base64Url.encode(utf8.encode(payloadJson))}.${base64Url.encode(signature)}';

  /// Signs a payload map and returns the dotted envelope.
  static Future<String> signPayload(
    Map<String, dynamic> payload,
    List<int> privateSeed,
  ) async {
    final keyPair = await _ed.newKeyPairFromSeed(privateSeed);
    final canonical = canonicalize(payload);
    final sig = await _ed.sign(utf8.encode(canonical), keyPair: keyPair);
    return wrap(canonical, sig.bytes);
  }

  /// Verifies the **directory** envelope against the baked root key and parses it.
  static Future<SignersDirectory> verifyDirectory(String envelope) =>
      verifyDirectoryWith(envelope, _rootPublic);

  /// Same, against an explicit root public key (used by the key tool before the
  /// const is baked, and by tests).
  static Future<SignersDirectory> verifyDirectoryWith(
    String envelope,
    List<int> rootPublic,
  ) async {
    final parts = envelope.split('.');
    if (parts.length != 2) {
      throw const FormatException(VerifyResult.errBadSignature);
    }
    final payloadBytes = base64Url.decode(base64Url.normalize(parts[0]));
    final sigBytes = base64Url.decode(base64Url.normalize(parts[1]));
    final ok = await _ed.verify(
      payloadBytes,
      signature: Signature(sigBytes,
          publicKey: SimplePublicKey(rootPublic, type: KeyPairType.ed25519)),
    );
    if (!ok) throw const FormatException(VerifyResult.errBadSignature);

    final payload = decodeStrict(utf8.decode(payloadBytes));
    return directoryFromPayload(Map<String, dynamic>.from(payload as Map), envelope);
  }

  /// Parses a directory payload (already verified) into a [SignersDirectory].
  static SignersDirectory directoryFromPayload(
    Map<String, dynamic> payload,
    String envelope,
  ) {
    final rawSigners = payload['signers'];
    if (rawSigners is! List) {
      throw const FormatException(VerifyResult.errMalformedField);
    }
    final seen = <String>{};
    final signers = <SignerEntry>[];
    for (final raw in rawSigners) {
      if (raw is! Map) {
        throw const FormatException(VerifyResult.errMalformedField);
      }
      final entry = SignerEntry.fromMap(Map<String, dynamic>.from(raw));
      if (!seen.add(entry.id)) {
        throw const FormatException('duplicate signer id');
      }
      signers.add(entry);
    }
    return SignersDirectory(
      version: payload['version'] as int? ?? 0,
      updatedAt: payload['updated_at'] as int? ?? 0,
      signers: signers,
      envelope: envelope,
    );
  }

  /// Verifies a dotted envelope: decode → route on `format` → resolve the signer
  /// in the directory → role check → signature. Nothing after the format check
  /// runs unless the format matches, so envelopes can never be cross-accepted.
  static Future<VerifyResult> verifyEnvelope(
    String envelope, {
    required SignersDirectory directory,
    required String expectedFormat,
    required Set<SignerRole> allowedRoles,
  }) async {
    final parts = envelope.split('.');
    if (parts.length != 2) return VerifyResult.fail(VerifyResult.errBadSignature);
    final List<int> payloadBytes;
    final List<int> sigBytes;
    try {
      payloadBytes = base64Url.decode(base64Url.normalize(parts[0]));
      sigBytes = base64Url.decode(base64Url.normalize(parts[1]));
    } catch (_) {
      return VerifyResult.fail(VerifyResult.errBadSignature);
    }

    final Map<String, dynamic> payload;
    try {
      final decoded = decodeStrict(utf8.decode(payloadBytes));
      if (decoded is! Map) return VerifyResult.fail(VerifyResult.errNotJson);
      payload = Map<String, dynamic>.from(decoded);
    } on FormatException catch (e) {
      return VerifyResult.fail(e.message == VerifyResult.errDuplicateKey
          ? VerifyResult.errDuplicateKey
          : VerifyResult.errNotJson);
    }

    if (payload['format'] != expectedFormat) {
      return VerifyResult.fail(VerifyResult.errUnknownFormat);
    }
    final signerId = payload['signer_id'];
    if (signerId is! String || signerId.isEmpty) {
      return VerifyResult.fail(VerifyResult.errUnknownSigner);
    }
    final signer = directory.byId(signerId);
    if (signer == null) return VerifyResult.fail(VerifyResult.errUnknownSigner);
    if (!allowedRoles.contains(signer.role)) {
      return VerifyResult.fail(VerifyResult.errForbiddenRole);
    }

    final bool ok;
    try {
      ok = await _ed.verify(
        payloadBytes,
        signature: Signature(sigBytes,
            publicKey: SimplePublicKey(signer.publicKey, type: KeyPairType.ed25519)),
      );
    } catch (_) {
      return VerifyResult.fail(VerifyResult.errBadSignature);
    }
    if (!ok) return VerifyResult.fail(VerifyResult.errBadSignature);
    return VerifyResult.ok(signer, payload);
  }

  /// Signs an artifact **file**: canonical payload + `signature` appended, then
  /// pretty-printed. Verification re-encodes canonically ([splitArtifact]).
  static Future<String> signArtifactFile(
    Map<String, dynamic> payload,
    List<int> privateSeed,
  ) async {
    final keyPair = await _ed.newKeyPairFromSeed(privateSeed);
    final sig = await _ed.sign(utf8.encode(canonicalize(payload)), keyPair: keyPair);
    return const JsonEncoder.withIndent('  ')
        .convert(<String, dynamic>{...payload, 'signature': base64Url.encode(sig.bytes)});
  }

  /// Generates a signer keypair **on this device**; the private half is returned
  /// so the caller can persist it in the app's private store.
  static Future<List<int>> generateSigner() async {
    final keyPair = await _ed.newKeyPair();
    return keyPair.extractPrivateKeyBytes();
  }

  static Future<List<int>> publicKeyFromSeed(List<int> seed) async {
    final keyPair = await _ed.newKeyPairFromSeed(seed);
    return (await keyPair.extractPublicKey()).bytes;
  }
}

/// Minimal JSON parser that rejects duplicate object keys.
class _StrictJsonParser {
  final String src;
  int i = 0;

  _StrictJsonParser(this.src);

  bool get atEnd => i >= src.length;

  void skipWhitespace() {
    while (i < src.length && (src[i] == ' ' || src[i] == '\n' || src[i] == '\r' || src[i] == '\t')) {
      i++;
    }
  }

  dynamic parseValue() {
    skipWhitespace();
    if (atEnd) throw const FormatException('unexpected end');
    final c = src[i];
    if (c == '{') return _object();
    if (c == '[') return _array();
    if (c == '"') return _string();
    if (c == 't' || c == 'f') return _boolean();
    if (c == 'n') {
      _expect('null');
      return null;
    }
    return _number();
  }

  Map<String, dynamic> _object() {
    i++; // {
    final out = <String, dynamic>{};
    skipWhitespace();
    if (i < src.length && src[i] == '}') {
      i++;
      return out;
    }
    while (true) {
      skipWhitespace();
      final key = _string();
      skipWhitespace();
      if (i >= src.length || src[i] != ':') throw const FormatException('expected :');
      i++;
      final value = parseValue();
      if (out.containsKey(key)) throw const FormatException(VerifyResult.errDuplicateKey);
      out[key] = value;
      skipWhitespace();
      if (i >= src.length) throw const FormatException('unterminated object');
      if (src[i] == ',') {
        i++;
        continue;
      }
      if (src[i] == '}') {
        i++;
        return out;
      }
      throw const FormatException('expected , or }');
    }
  }

  List<dynamic> _array() {
    i++; // [
    final out = <dynamic>[];
    skipWhitespace();
    if (i < src.length && src[i] == ']') {
      i++;
      return out;
    }
    while (true) {
      out.add(parseValue());
      skipWhitespace();
      if (i >= src.length) throw const FormatException('unterminated array');
      if (src[i] == ',') {
        i++;
        continue;
      }
      if (src[i] == ']') {
        i++;
        return out;
      }
      throw const FormatException('expected , or ]');
    }
  }

  String _string() {
    if (i >= src.length || src[i] != '"') {
      throw const FormatException('expected string');
    }
    i++;
    final sb = StringBuffer();
    while (i < src.length) {
      final c = src[i];
      if (c == '"') {
        i++;
        return sb.toString();
      }
      if (c == r'\') {
        i++;
        if (i >= src.length) throw const FormatException('bad escape');
        final e = src[i];
        switch (e) {
          case '"':
          case '\\':
          case '/':
            sb.write(e);
          case 'b':
            sb.write('\b');
          case 'f':
            sb.write('\f');
          case 'n':
            sb.write('\n');
          case 'r':
            sb.write('\r');
          case 't':
            sb.write('\t');
          case 'u':
            if (i + 4 >= src.length) throw const FormatException('bad unicode escape');
            sb.write(String.fromCharCode(int.parse(src.substring(i + 1, i + 5), radix: 16)));
            i += 4;
          default:
            throw const FormatException('bad escape');
        }
        i++;
        continue;
      }
      sb.write(c);
      i++;
    }
    throw const FormatException('unterminated string');
  }

  bool _boolean() {
    if (src.startsWith('true', i)) {
      i += 4;
      return true;
    }
    if (src.startsWith('false', i)) {
      i += 5;
      return false;
    }
    throw const FormatException('bad boolean');
  }

  void _expect(String literal) {
    if (!src.startsWith(literal, i)) throw const FormatException('bad literal');
    i += literal.length;
  }

  num _number() {
    final start = i;
    while (i < src.length &&
        (src[i] == '-' ||
            src[i] == '+' ||
            src[i] == '.' ||
            src[i] == 'e' ||
            src[i] == 'E' ||
            (src[i].codeUnitAt(0) >= 0x30 && src[i].codeUnitAt(0) <= 0x39))) {
      i++;
    }
    if (i == start) throw const FormatException('bad number');
    final text = src.substring(start, i);
    return int.tryParse(text) ?? double.parse(text);
  }
}
