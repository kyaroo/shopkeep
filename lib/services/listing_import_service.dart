import '../data/listing_bundle.dart';
import '../data/settings_service.dart';
import '../data/signers_directory.dart';
import '../data/signing.dart';
import 'listing_merge_service.dart';

/// Outcome of [ListingImportService.apply].
///
/// Either [rejected] (nothing was written) or [applied] (the shop's listing now
/// reflects the bundle). The two are distinguished by which field is non-null so
/// a caller cannot accidentally read counts off a rejected import.
class ListingImportOutcome {
  final String? error;
  final String? shopKey;
  final String? signerName;
  final ListingMergeResult? merge;

  const ListingImportOutcome._({
    this.error,
    this.shopKey,
    this.signerName,
    this.merge,
  });

  factory ListingImportOutcome.rejected(String error) =>
      ListingImportOutcome._(error: error);

  factory ListingImportOutcome.applied(
          String shopKey, String signerName, ListingMergeResult merge) =>
      ListingImportOutcome._(
          shopKey: shopKey, signerName: signerName, merge: merge);

  bool get ok => error == null;
}

/// Imports a `.myhanoutlisting` file into the shop it names.
///
/// Order matters: **verify first, then write**. A rejected bundle must leave the
/// shop's listing untouched, so the merge only ever runs on a bundle whose
/// signature and role have already been accepted.
///
/// The bundle's `shop_key` is signed, so it is trusted to select the target
/// database — an unsigned field here would let a file pick its own victim.
class ListingImportService {
  static Future<ListingImportOutcome> apply(
    String json, {
    SettingsService? settings,
    SignersDirectory? directory,
  }) async {
    final store = settings ?? const ConfigSettingsService();
    final SignersDirectory dir;
    if (directory != null) {
      dir = directory;
    } else {
      try {
        dir = await SignersDirectoryLoader.load(settings: store);
      } catch (e) {
        return ListingImportOutcome.rejected(
            'no usable signers directory ($e)');
      }
    }

    final verification = await ListingBundle.verify(json, directory: dir);
    if (!verification.ok) {
      return ListingImportOutcome.rejected(verification.error!);
    }
    final bundle = verification.bundle!;
    final signerName = verification.signerName ?? bundle.signerId;

    // Bind before writing: the merge opens the shop named by the bundle.
    await store.setCurrentShopKey(bundle.shopKey);
    final merge = await ListingMergeService.merge(bundle, changedBy: signerName);
    return ListingImportOutcome.applied(bundle.shopKey, signerName, merge);
  }
}
