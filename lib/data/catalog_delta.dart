import 'dart:convert';

import '../models/catalog_entry.dart';
import 'signing.dart';

/// `.myhanout` — a signed catalog delta file.
///
/// Carries only the catalog rows that changed since [baseVersion]. The
/// shopkeeper applies it offline (a file received over WhatsApp, from a file
/// manager, ...).
///
/// The catalog is **universal**: a delta's content (name / name_ar / name_en /
/// category / photo) is identical for every shop, so it is deliberately *not*
/// bound to a shop — any device may apply any validly signed delta. Shop data
/// (price, stock) never travels here, which is what keeps the listing safe.
///
/// Integrity comes from the signer's **Ed25519** key, resolved through the
/// signers directory; the HMAC era (`fileVersion` 1) is gone.
class CatalogDelta {
  static const String format = 'myhanout-catalog-delta';
  static const String fileExtension = '.myhanout';

  /// 2 = Ed25519 + `signer_id`. v1 was the HMAC era.
  static const int fileVersion = 2;

  /// The signer that authored this delta (resolved in the directory).
  final String signerId;

  /// The catalog version this delta applies to (the shopkeeper's installed one).
  final int baseVersion;

  /// The catalog version after applying it. Must be `baseVersion + 1`.
  final int targetVersion;
  final int generatedAt;
  final List<CatalogEntry> upserts;
  final List<String> deletes;

  CatalogDelta({
    required this.signerId,
    required this.baseVersion,
    required this.targetVersion,
    required this.generatedAt,
    required this.upserts,
    this.deletes = const [],
  });

  /// Signed payload, `signature` excluded — exactly what gets signed.
  Map<String, dynamic> toPayload() => <String, dynamic>{
        'format': format,
        'alg': Signing.algorithm,
        'fileVersion': fileVersion,
        'signer_id': signerId,
        'base_version': baseVersion,
        'target_version': targetVersion,
        'generated_at': generatedAt,
        'upserts': upserts.map(_entryToMap).toList(),
        'deletes': deletes,
      };

  /// Unsigned pretty-printed file (preview / tests). Signing is
  /// `Signing.signArtifactFile(delta.toPayload(), seed)`.
  String toFileJson() =>
      const JsonEncoder.withIndent('  ').convert(toPayload());

  Map<String, dynamic> _entryToMap(CatalogEntry e) => <String, dynamic>{
        'barcode': e.barcode,
        'name': e.name,
        'name_ar': e.nameAr,
        'name_en': e.nameEn,
        'category': e.category,
        'photo_base64': e.photo == null ? null : base64Encode(e.photo!),
        'updated_at': e.updatedAt,
      };

  /// Verifies a delta file offline: format → signer → role → signature →
  /// version step. Returns a [DeltaVerification].
  static Future<DeltaVerification> verify(
    String json, {
    required SignersDirectory directory,
  }) async {
    final Map<String, dynamic> payload;
    final List<int> signature;
    try {
      (payload, signature) = Signing.splitArtifact(json);
    } catch (e) {
      // Malformed input must never escape as an exception: this is a security
      // boundary that consumes untrusted QR/file content.
      return DeltaVerification.failed(
          e is FormatException ? e.message : 'malformed artifact');
    }
    if (payload['format'] != format) {
      return DeltaVerification.failed('unknown format');
    }

    final envelope = Signing.wrap(Signing.canonicalize(payload), signature);
    final result = await Signing.verifyEnvelope(
      envelope,
      directory: directory,
      expectedFormat: format,
      allowedRoles: const {SignerRole.founder, SignerRole.admin},
    );
    if (!result.ok) return DeltaVerification.failed(result.error!);

    final base = payload['base_version'];
    final target = payload['target_version'];
    if (base is! int || target is! int) {
      return DeltaVerification.failed('malformed-field');
    }
    // Defence in depth: the build side already emits base+1; a delta that
    // jumps the version is rejected so a leaked key cannot desync every shop.
    if (target != base + 1) {
      return DeltaVerification.failed('version jump');
    }

    return DeltaVerification.ok(
      CatalogDelta(
        signerId: payload['signer_id'] as String,
        baseVersion: base,
        targetVersion: target,
        generatedAt: payload['generated_at'] as int? ?? 0,
        upserts: (payload['upserts'] as List? ?? [])
            .map((raw) => _entryFromMap(raw as Map<String, dynamic>))
            .toList(),
        deletes: (payload['deletes'] as List? ?? []).cast<String>(),
      ),
      signerName: result.signer?.name,
    );
  }

  static CatalogEntry _entryFromMap(Map<String, dynamic> m) {
    final photoB64 = m['photo_base64'] as String?;
    return CatalogEntry(
      barcode: m['barcode'] as String,
      name: m['name'] as String,
      nameAr: m['name_ar'] as String?,
      nameEn: m['name_en'] as String?,
      category: m['category'] as String?,
      photo: photoB64 == null ? null : base64Decode(photoB64),
      createdAt: (m['created_at'] as int?) ?? 0,
      updatedAt: (m['updated_at'] as int?) ?? 0,
    );
  }

  /// Applies the delta: upsert catalog fields, then tombstone deletes.
  /// Never touches the shop listing (price/stock).
  Future<void> apply(CatalogRepository repo) async {
    await repo.init();
    for (final e in upserts) {
      final existing = await repo.get(e.barcode);
      await repo.upsert(CatalogEntry(
        barcode: e.barcode,
        name: e.name,
        nameAr: e.nameAr,
        nameEn: e.nameEn,
        category: e.category,
        photo: e.photo ?? existing?.photo,
        createdAt: existing?.createdAt ?? e.createdAt,
        updatedAt: e.updatedAt,
      ));
    }
    for (final barcode in deletes) {
      await repo.delete(barcode);
    }
  }
}

/// Outcome of [CatalogDelta.verify].
class DeltaVerification {
  final CatalogDelta? delta;
  final String? error;
  final String? signerName;

  DeltaVerification.ok(this.delta, {this.signerName}) : error = null;
  DeltaVerification.failed(this.error)
      : delta = null,
        signerName = null;

  bool get ok => delta != null;
}
