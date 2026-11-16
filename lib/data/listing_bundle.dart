import '../models/listing_row.dart';
import '../utils/slug.dart';
import 'signing.dart';

/// `.myhanoutlisting` — a signed shop listing bundle (price + stock).
///
/// The mirror image of `.myhanout`: a catalog delta carries **universal** catalog
/// fields, this carries the **shop's own** listing. It never carries a name,
/// category or photo — the shopkeeper reads those from its local catalog — so a
/// bundle structurally cannot overwrite catalog data.
///
/// Signed by a `founder`/`admin` key and verified against the signers directory
/// (decision D10, 2026-11-16, which reopens D2). A salesman key is not enough:
/// provisioning is the salesman's job, pricing is not. Unsigned or unknown-signer
/// bundles are **rejected**, not warned about.
class ListingBundle {
  static const String format = 'myhanout-listing-v1';
  static const String fileExtension = '.myhanoutlisting';

  /// 1 = Ed25519 + `signer_id` + `shop_key`, the only version.
  static const int fileVersion = 1;

  /// Decision D6: a compact, phone-safe snapshot.
  static const int maxRows = 10000;

  final String signerId;

  /// The shop this listing belongs to. Signed, so the importer can trust it.
  final String shopKey;

  /// The catalog generation the listing was exported against, for display and
  /// for the shopkeeper to see how stale its catalog is.
  final int catalogVersion;
  final int generatedAt;
  final List<ListingRow> rows;

  ListingBundle({
    required this.signerId,
    required this.shopKey,
    required this.catalogVersion,
    required this.generatedAt,
    required this.rows,
  });

  /// Signed payload, `signature` excluded — exactly what gets signed.
  Map<String, dynamic> toPayload() => <String, dynamic>{
        'format': format,
        'alg': Signing.algorithm,
        'fileVersion': fileVersion,
        'signer_id': signerId,
        'shop_key': shopKey,
        'catalog_version': catalogVersion,
        'generated_at': generatedAt,
        'rows': rows
            .map((r) => <String, dynamic>{
                  'barcode': r.barcode,
                  'price_cents': r.priceCents,
                  'stock_qty': r.stockQty,
                })
            .toList(),
      };

  /// Verifies a bundle offline: format → signer → role → signature → shape.
  static Future<ListingVerification> verify(
    String json, {
    required SignersDirectory directory,
  }) async {
    final Map<String, dynamic> payload;
    final List<int> signature;
    try {
      (payload, signature) = Signing.splitArtifact(json);
    } catch (e) {
      // Malformed input must never escape as an exception: this is a security
      // boundary that consumes untrusted file content.
      return ListingVerification.failed(
          e is FormatException ? e.message : 'malformed artifact');
    }
    if (payload['format'] != format) {
      return ListingVerification.failed('unknown format');
    }

    final envelope = Signing.wrap(Signing.canonicalize(payload), signature);
    final result = await Signing.verifyEnvelope(
      envelope,
      directory: directory,
      expectedFormat: format,
      allowedRoles: const {SignerRole.founder, SignerRole.admin},
    );
    if (!result.ok) return ListingVerification.failed(result.error!);

    final shopKey = payload['shop_key'];
    if (shopKey is! String || !isValidShopKey(shopKey)) {
      return ListingVerification.failed('bad shop_key');
    }
    final catalogVersion = payload['catalog_version'];
    if (catalogVersion is! int) {
      return ListingVerification.failed('malformed-field');
    }
    final rawRows = payload['rows'];
    if (rawRows is! List || rawRows.length > maxRows) {
      return ListingVerification.failed('too many rows');
    }

    final rows = <ListingRow>[];
    final seen = <String>{};
    for (final raw in rawRows) {
      if (raw is! Map) return ListingVerification.failed('malformed row');
      final barcode = raw['barcode'];
      final price = raw['price_cents'];
      final stock = raw['stock_qty'];
      if (barcode is! String || barcode.isEmpty) {
        return ListingVerification.failed('malformed row');
      }
      if (price is! int || price < 0 || stock is! int || stock < 0) {
        return ListingVerification.failed('malformed row');
      }
      // A duplicate barcode would make the upsert order-dependent; reject it
      // rather than pick a winner silently.
      if (!seen.add(barcode)) {
        return ListingVerification.failed('duplicate barcode');
      }
      rows.add(ListingRow(
          barcode: barcode, priceCents: price, stockQty: stock));
    }

    return ListingVerification.ok(
      ListingBundle(
        signerId: payload['signer_id'] as String,
        shopKey: shopKey,
        catalogVersion: catalogVersion,
        generatedAt: payload['generated_at'] as int? ?? 0,
        rows: rows,
      ),
      signerName: result.signer?.name,
    );
  }
}

/// Outcome of [ListingBundle.verify].
class ListingVerification {
  final ListingBundle? bundle;
  final String? error;
  final String? signerName;

  ListingVerification.ok(this.bundle, {this.signerName}) : error = null;
  ListingVerification.failed(this.error)
      : bundle = null,
        signerName = null;

  bool get ok => bundle != null;
}
