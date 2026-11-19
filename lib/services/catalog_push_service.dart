import '../services/catalog_delta_service.dart';
import '../models/catalog_entry.dart';

/// Builds the signed `.myhanout` payload for one delivery. Injectable so tests
/// can supply a prebuilt payload (Ed25519 signing is real async and cannot be
/// awaited inside a `testWidgets` FakeAsync zone).
typedef CatalogPayloadBuilder = Future<DeltaBuildResult> Function({
  required int localVersion,
  required int shopVersion,
  required int targetVersion,
  required String signerId,
  required List<int> privateSeed,
  required List<CatalogEntry> entries,
  required List<String> deletes,
});

/// Builds the `.myhanout` payload for one catalogue delivery, without any UI.
///
/// Flutter-free on purpose (no `material.dart`): the delivery tools and tests
/// import it with plain `dart`, while the screen imports the same helper so
/// there is exactly one implementation of the version guard.
///
/// The base must be the generation the shop is on (server truth) and the
/// target the admin's generation. Distribution delivers **one
/// multi-generation delta** `base = M` (shop) → `target = N` (admin), so the
/// target may be more than `base + 1`. A base that does not match the shop's
/// registered generation is rejected before a single byte is written, so an
/// out-of-order or cross-generation bundle can never half-apply.
class CatalogPushBuilder {
  /// Returns the file name the payload is written to.
  static String fileName(String shopKey, int target) =>
      'catalog_${shopKey}_v$target.myhanout';

  /// Builds the signed delta. Throws [CatalogBaseMismatchException] when the
  /// shop never reported a generation (0), when [targetVersion] is not ahead
  /// of [shopVersion], or when the admin's local catalog
  /// ([localVersion]) is not at [targetVersion].
  ///
  /// Returns the [DeltaBuildResult] so the caller can report what the photo
  /// budget did; the file contents are `result.json`.
  static Future<DeltaBuildResult> buildPayload({
    required int localVersion,
    required int shopVersion,
    required int targetVersion,
    required String signerId,
    required List<int> privateSeed,
    required List<CatalogEntry> entries,
    List<String> deletes = const [],
  }) async {
    if (shopVersion <= 0) {
      throw CatalogBaseMismatchException(localVersion, shopVersion);
    }
    if (targetVersion <= shopVersion) {
      throw CatalogBaseMismatchException(localVersion, targetVersion);
    }
    if (localVersion != targetVersion) {
      throw CatalogBaseMismatchException(localVersion, targetVersion);
    }
    return CatalogDeltaBuilder.build(
      baseVersion: shopVersion,
      targetVersion: targetVersion,
      generatedAt: targetVersion,
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
