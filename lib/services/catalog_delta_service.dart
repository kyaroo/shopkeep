import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/models/catalog_entry.dart';

/// Builds a `.myhanout` catalog delta from a list of changes.
///
/// Used by the admin (CAT6) to generate signed delta files for delivery to
/// shopkeepers. The delta carries catalog fields only (universal), never the
/// shop listing (price/stock).
///
/// Example:
///   final delta = await CatalogDeltaBuilder.build(
///     baseVersion: 1000,
///     targetVersion: 1001,
///     entries: [updatedProduct],
///     deletes: ['0011210006508'],
///   );
///   File('update.myhanout').writeAsStringSync(delta);
class CatalogDeltaBuilder {
  /// Builds the serialized `.myhanout` payload.
  ///
  /// [baseVersion] must match the installed catalog version on the target
  /// shop (enforced by the version guard in the receiver). [targetVersion] is
  /// the version after applying. [entries] are upserts; [deletes] are
  /// tombstones. Both are catalog rows only — the shop listing is never
  /// touched.
  static String build({
    required int baseVersion,
    required int targetVersion,
    required int generatedAt,
    required List<CatalogEntry> entries,
    required List<String> deletes,
  }) {
    final upserts = entries
        .map((e) => e.copyWith(updatedAt: targetVersion))
        .whereType<CatalogEntry>()
        .toList();
    final delta = CatalogDelta(
      baseVersion: baseVersion,
      targetVersion: targetVersion,
      generatedAt: generatedAt,
      upserts: upserts,
      deletes: deletes,
    );
    return delta.toFileJson();
  }
}
