/// One row of a shop's listing: the price and stock the shop owns.
///
/// Deliberately carries **no** name, category or photo. Those come from the
/// universal catalog on the device, which is what makes it impossible for a
/// listing bundle to overwrite catalog data (decision D3).
class ListingRow {
  final String barcode;
  final int priceCents;
  final int stockQty;

  const ListingRow({
    required this.barcode,
    required this.priceCents,
    required this.stockQty,
  });

  @override
  bool operator ==(Object other) =>
      other is ListingRow &&
      other.barcode == barcode &&
      other.priceCents == priceCents &&
      other.stockQty == stockQty;

  @override
  int get hashCode => Object.hash(barcode, priceCents, stockQty);

  @override
  String toString() =>
      'ListingRow($barcode, $priceCents, $stockQty)';
}
