/// In-app signer seed import (decisions 2a / 3a / 4a).
///
/// A founder hands a single signer seed to an admin as an envelope:
///   `{"format":"myhanout-signer-seed-v1","signer_id":"…","seed":"<base64url 32B>"}`
/// (as a QR, or as a `.myhanoutseed` text file). Before the seed is persisted it
/// is verified against the ROOT-signed signers directory: the id must exist, the
/// seed must derive the public key recorded for that id, and its length must be
/// exactly 32 bytes. Nothing here logs, displays or returns the seed.
///
/// Roles: every verified seed is stored. Only founder/admin may be made the
/// active push signer; a salesman seed is stored but never activated, and
/// [activeRole] is re-checked at push time so edited prefs cannot bypass it.
library;

import 'dart:convert';

import 'settings_service.dart';
import 'signers_directory.dart';
import 'signing.dart';

class SignerSeedImport {
  SignerSeedImport._();

  static const format = ArtifactFormat.signerSeed;

  // Stable rejection codes (never contain a seed).
  static const errMalformed = 'malformed-envelope';
  static const errBadFormat = 'bad-format';
  static const errBadSeedLength = 'seed-length';
  static const errUnknownSigner = VerifyResult.errUnknownSigner;
  static const errKeyMismatch = 'public-key-mismatch';
  static const errDirectory = 'directory-unavailable';

  /// Parses [envelope], verifies it against the directory, stores the seed and
  /// activates it only for founder/admin. The raw [envelope] is never retained
  /// or logged; the caller is responsible for clearing its own UI buffer.
  static Future<SignerImportResult> import(
    String envelope, {
    required SettingsService settings,
    List<int>? rootPublicKey,
  }) async {
    final Map<String, dynamic> payload;
    try {
      final decoded = Signing.decodeStrict(envelope.trim());
      if (decoded is! Map) {
        return SignerImportResult.fail(errMalformed);
      }
      payload = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return SignerImportResult.fail(errMalformed);
    }

    if (payload['format'] != format) {
      return SignerImportResult.fail(errBadFormat);
    }
    final signerId = payload['signer_id'];
    final seedB64 = payload['seed'];
    if (signerId is! String || signerId.isEmpty ||
        seedB64 is! String || seedB64.isEmpty) {
      return SignerImportResult.fail(errMalformed);
    }

    final List<int> seed;
    try {
      seed = base64Url.decode(base64Url.normalize(seedB64));
    } catch (_) {
      return SignerImportResult.fail(errMalformed);
    }
    if (seed.length != Signing.publicKeyLength) {
      return SignerImportResult.fail(errBadSeedLength);
    }

    final SignersDirectory directory;
    try {
      directory = await SignersDirectoryLoader.load(
        settings: settings,
        rootPublicKey: rootPublicKey,
      );
    } catch (_) {
      return SignerImportResult.fail(errDirectory);
    }

    final signer = directory.byId(signerId);
    if (signer == null) {
      return SignerImportResult.fail(errUnknownSigner);
    }

    final List<int> derived;
    try {
      derived = await Signing.publicKeyFromSeed(seed);
    } catch (_) {
      return SignerImportResult.fail(errMalformed);
    }
    if (!_sameBytes(derived, signer.publicKey)) {
      return SignerImportResult.fail(errKeyMismatch);
    }

    // Verified: store for ANY role. Only founder/admin may push.
    await settings.saveSignerKey(signerId, seed);
    final canActivate = canPush(signer.role);
    if (canActivate) {
      await settings.setActiveSignerId(signerId);
    }
    return SignerImportResult(
      signer: signer,
      activated: canActivate,
    );
  }

  /// Re-reads the role of the active signer from the ROOT-verified directory.
  /// Used at push time so a manually edited `active_signer_id` cannot turn a
  /// salesman into a distributor. Returns null when there is no active signer
  /// or its id is not in the trusted directory.
  static Future<SignerRole?> activeRole(
    SettingsService settings, {
    List<int>? rootPublicKey,
  }) async {
    final id = await settings.getActiveSignerId();
    if (id == null || id.isEmpty) return null;
    try {
      final directory = await SignersDirectoryLoader.load(
        settings: settings,
        rootPublicKey: rootPublicKey,
      );
      return directory.byId(id)?.role;
    } catch (_) {
      return null; // fail closed
    }
  }

  static bool canPush(SignerRole? role) =>
      role == SignerRole.founder || role == SignerRole.admin;

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Outcome of an import. Carries only public signer metadata — never a seed.
class SignerImportResult {
  final SignerEntry? signer;
  final bool activated;
  final String? error;

  const SignerImportResult({this.signer, this.activated = false, this.error});

  factory SignerImportResult.fail(String code) =>
      SignerImportResult(error: code);

  bool get ok => error == null && signer != null;
  SignerRole? get role => signer?.role;
}
