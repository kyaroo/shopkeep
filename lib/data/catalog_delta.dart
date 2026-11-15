import 'dart:convert';

import '../models/catalog_entry.dart';
import 'provisioning.dart';

/// `.myhanout` — a signed catalog delta file.
///
/// Carries only the catalog rows that changed since [baseVersion]. The
/// shopkeeper applies it offline (a file received over WhatsApp, from a file
/// manager, ...). The signature reuses the provisioning HMAC secret.
///
/// The catalog is **universal**: a delta's content (name / name_ar / name_en /
/// category / photo) is identical for every shop, so it is deliberately *not*
/// bound to a shop — any device may apply any validly signed delta. Shop data
/// (price, stock) never travels here, which is what keeps the listing safe.
///
/// Only catalog fields travel here: name / name_ar / name_en / category /
/// photo. The shop's listing (price, stock) is never touched, so a delta
/// cannot clobber local pricing.
class CatalogDelta {
  static const String format = 'myhanout-catalog-delta';
  static const String fileExtension = '.myhanout';
  static const int fileVersion = 1;

  /// The catalog version this delta applies to (the shopkeeper's installed one).
  final int baseVersion;

  /// The catalog version after applying it.
  final int targetVersion;
  final int generatedAt;
  final List<CatalogEntry> upserts;
  final List<String> deletes;

  CatalogDelta({
    required this.baseVersion,
    required this.targetVersion,
    required this.generatedAt,
    required this.upserts,
    this.deletes = const [],
  });

  /// Canonical payload (signature excluded) — exactly what gets signed.
  Map<String, dynamic> _payload() => <String, dynamic>{
        'format': format,
        'version': fileVersion,
        'base_version': baseVersion,
        'target_version': targetVersion,
        'generated_at': generatedAt,
        'upserts': upserts.map(_entryToMap).toList(),
        'deletes': deletes,
      };

  Map<String, dynamic> _entryToMap(CatalogEntry e) => <String, dynamic>{
        'barcode': e.barcode,
        'name': e.name,
        'name_ar': e.nameAr,
        'name_en': e.nameEn,
        'category': e.category,
        'photo_base64': e.photo == null ? null : base64Encode(e.photo!),
        'updated_at': e.updatedAt,
      };

  /// Serialized file contents (pretty JSON, signed).
  String toFileJson() {
    final payload = _payload();
    final signature = Provisioning.signatureFor(jsonEncode(payload));
    return const JsonEncoder.withIndent('  ')
        .convert(<String, dynamic>{...payload, 'signature': signature});
  }

  /// Verifies the signature, then decodes the delta.
  static DeltaVerification verify(String json) {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return DeltaVerification.failed('not valid JSON');
    }
    if (map['format'] != format) {
      return DeltaVerification.failed('unknown format');
    }
    final signature = map.remove('signature') as String?;
    if (signature == null) return DeltaVerification.failed('missing signature');
    if (!Provisioning.verifySignature(jsonEncode(map), signature)) {
      return DeltaVerification.failed('bad signature');
    }
    return DeltaVerification.ok(
      CatalogDelta(
        baseVersion: map['base_version'] as int,
        targetVersion: map['target_version'] as int,
        generatedAt: map['generated_at'] as int,
        upserts: (map['upserts'] as List)
            .map((raw) => _entryFromMap(raw as Map<String, dynamic>))
            .toList(),
        deletes: (map['deletes'] as List).cast<String>(),
      ),
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

  DeltaVerification.ok(this.delta) : error = null;
  DeltaVerification.failed(this.error) : delta = null;

  bool get ok => delta != null;
}
