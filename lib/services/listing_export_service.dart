import '../data/config.dart';
import '../data/db.dart';
import '../data/listing_bundle.dart';
import '../data/signing.dart';
import '../models/listing_row.dart';

/// Outcome of [ListingExportBuilder.export].
class ListingExportResult {
  final String json;
  final String fileName;
  final int rows;
  final int catalogVersion;

  const ListingExportResult({
    required this.json,
    required this.fileName,
    required this.rows,
    required this.catalogVersion,
  });
}

/// Reads a shop's listing from its database and signs it into a
/// `.myhanoutlisting` bundle.
///
/// Flutter-free on purpose (no `material.dart`), like the catalog delta builder:
/// the screen and the tests share this one implementation.
///
/// Only `barcode`, `price_cents` and `stock_qty` are exported. Names, categories
/// and photos stay in the catalog on the device, so a bundle can never overwrite
/// them.
class ListingExportBuilder {
  static String fileName(String shopKey, int catalogVersion) =>
      'listing_${shopKey}_v$catalogVersion.myhanoutlisting';

  /// Exports and signs the whole listing of [shopKey].
  ///
  /// The bundle's `catalog_version` is the catalog generation installed on this
  /// device, so the shopkeeper can see how stale its catalog is.
  static Future<ListingExportResult> export({
    required String shopKey,
    required String signerId,
    required List<int> privateSeed,
  }) async {
    await Db.open(shopKey);
    final handle = await Db.databaseHandle(shopKey);
    final catalogVersion = await Config.getCatalogVersion();

    final rows = (await handle.rawQuery(
      'SELECT barcode, price_cents, stock_qty FROM products '
      'WHERE barcode IS NOT NULL ORDER BY barcode',
    ))
        .map((r) => ListingRow(
              barcode: r['barcode'] as String,
              priceCents: r['price_cents'] as int,
              stockQty: r['stock_qty'] as int,
            ))
        .toList();

    final bundle = ListingBundle(
      signerId: signerId,
      shopKey: shopKey,
      catalogVersion: catalogVersion,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      rows: rows,
    );

    return ListingExportResult(
      json: await Signing.signArtifactFile(bundle.toPayload(), privateSeed),
      fileName: fileName(shopKey, catalogVersion),
      rows: rows.length,
      catalogVersion: catalogVersion,
    );
  }
}
