import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/photo_processor.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/catalog_entry.dart';

/// Hard per-photo budget inside a `.myhanout` delta.
///
/// Matches [processPhoto]'s cap so a delta never carries a photo bigger than
/// the one the rest of the app would have produced. The server refuses
/// anything over 64 KB, so an unbounded delta could be rejected at the push
/// boundary; enforcing it here keeps the file predictable at full catalog
/// scale (~4 KB/photo × 13k photos).
const int kMaxDeltaPhotoBytes = 50 * 1024;

/// Outcome of [CatalogDeltaBuilder.build].
///
/// [photosTrimmed] / [photosDropped] let the admin see what the budget did:
/// a trimmed photo was downscaled, a dropped one left its entry without a
/// photo (the name/category always survive).
class DeltaBuildResult {
  final String json;
  final int upserts;
  final int deletes;
  final int photosTrimmed;
  final int photosDropped;

  const DeltaBuildResult({
    required this.json,
    required this.upserts,
    required this.deletes,
    required this.photosTrimmed,
    required this.photosDropped,
  });

  /// True when every photo fit the budget untouched.
  bool get photosUntouched => photosTrimmed == 0 && photosDropped == 0;
}

/// Builds a `.myhanout` catalog delta from a list of changes.
///
/// Used by the admin (CAT6) to generate signed delta files for delivery to
/// shopkeepers. The delta carries catalog fields only (universal), never the
/// shop listing (price/stock).
///
/// Example:
///   final result = CatalogDeltaBuilder.build(
///     baseVersion: 1000,
///     targetVersion: 1001,
///     entries: [updatedProduct],
///     deletes: ['0011210006508'],
///   );
///   File('update.myhanout').writeAsStringSync(result.json);
class CatalogDeltaBuilder {
  /// Builds the serialized `.myhanout` payload.
  ///
  /// [baseVersion] must match the installed catalog version on the target
  /// shop (enforced by the version guard in the receiver). [targetVersion] is
  /// the version after applying. [entries] are upserts; [deletes] are
  /// tombstones. Both are catalog rows only — the shop listing is never
  /// touched.
  ///
  /// Every photo larger than [kMaxDeltaPhotoBytes] is re-encoded through
  /// [processPhoto]; if that still does not fit, the photo is dropped from
  /// that entry rather than bloating (or breaking) the file.
  static Future<DeltaBuildResult> build({
    required int baseVersion,
    required int targetVersion,
    required int generatedAt,
    required String signerId,
    required List<int> privateSeed,
    required List<CatalogEntry> entries,
    List<String> deletes = const [],
  }) async {
    var trimmed = 0;
    var dropped = 0;

    final upserts = <CatalogEntry>[];
    for (final e in entries) {
      final normalized = e.copyWith(updatedAt: targetVersion);
      final photo = normalized.photo;
      if (photo == null || photo.length <= kMaxDeltaPhotoBytes) {
        upserts.add(normalized);
        continue;
      }
      final resized = processPhoto(photo);
      if (resized != null && resized.length <= kMaxDeltaPhotoBytes) {
        trimmed++;
        upserts.add(normalized.copyWith(photo: resized));
      } else {
        dropped++;
        // NOTE: `copyWith(photo: null)` does NOT clear the photo — its
        // implementation is `photo ?? this.photo`. Rebuild the entry so the
        // dropped photo is really gone from the payload.
        upserts.add(CatalogEntry(
          barcode: normalized.barcode,
          name: normalized.name,
          nameAr: normalized.nameAr,
          nameEn: normalized.nameEn,
          category: normalized.category,
          photo: null,
          createdAt: normalized.createdAt,
          updatedAt: normalized.updatedAt,
        ));
      }
    }

    final delta = CatalogDelta(
      signerId: signerId,
      baseVersion: baseVersion,
      targetVersion: targetVersion,
      generatedAt: generatedAt,
      upserts: upserts,
      deletes: deletes,
    );
    return DeltaBuildResult(
      json: await Signing.signArtifactFile(delta.toPayload(), privateSeed),
      upserts: upserts.length,
      deletes: deletes.length,
      photosTrimmed: trimmed,
      photosDropped: dropped,
    );
  }
}
