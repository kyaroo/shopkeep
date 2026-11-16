import '../services/catalog_delta_service.dart';
import '../models/catalog_entry.dart';

/// Builds the `.myhanout` payload for one catalogue delivery, without any UI.
///
/// Flutter-free on purpose (no `material.dart`): the delivery tools and tests
/// import it with plain `dart`, while the screen imports the same helper so
/// there is exactly one implementation of the version guard.
///
/// The base must be the generation the shop is on (server truth) and the
/// target the next counter value. A base that does not match the local catalog
/// is rejected before a single byte is written, so an out-of-order or
/// cross-generation bundle can never half-apply.
class CatalogPushBuilder {
  /// Returns the file name the payload is written to.
  static String fileName(String shopKey, int target) =>
      'catalog_${shopKey}_v$target.myhanout';

  /// Builds the signed delta. Throws [CatalogBaseMismatchException] when
  /// [localVersion] is not [shopVersion], or when the shop never reported a
  /// generation (0).
  ///
  /// Returns the [DeltaBuildResult] so the caller can report what the photo
  /// budget did; the file contents are `result.json`.
  static Future<DeltaBuildResult> buildPayload({
    required int localVersion,
    required int shopVersion,
    required String signerId,
    required List<int> privateSeed,
    required List<CatalogEntry> entries,
    List<String> deletes = const [],
  }) async {
    if (shopVersion <= 0) {
      throw const CatalogBaseMismatchException(0, 0);
    }
    if (localVersion != shopVersion) {
      throw CatalogBaseMismatchException(localVersion, shopVersion);
    }
    final target = shopVersion + 1;
    return CatalogDeltaBuilder.build(
      baseVersion: shopVersion,
      targetVersion: target,
      generatedAt: target,
      signerId: signerId,
      privateSeed: privateSeed,
      entries: entries,
      deletes: deletes,
    );
  }
}

/// Thrown when a delivery cannot proceed because the admin's catalog and the
/// shop's registered generation differ.
class CatalogBaseMismatchException implements Exception {
  final int local;
  final int remote;
  const CatalogBaseMismatchException(this.local, this.remote);

  @override
  String toString() =>
      'CatalogBaseMismatchException(local: $local, remote: $remote)';
}
