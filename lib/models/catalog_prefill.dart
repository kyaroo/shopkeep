import 'dart:typed_data';

/// The fields a form needs from a catalog hit — a scan resolve or a browse row.
///
/// Replaces the `Map<String, dynamic>` (whose keys were `name_ar`,
/// `photo_base64`, …) that used to cross from the data layer into the widgets.
class CatalogPrefill {
  final String barcode;
  final String name;
  final String? nameAr;
  final String? nameEn;
  final String? category;
  final String? brand;
  final String? quantityText;
  final String? imageUrl;

  /// 'owner' or 'source:off'.
  final String? origin;

  /// Local catalog photo (already downscaled). Null when there is none.
  final Uint8List? photo;

  const CatalogPrefill({
    required this.barcode,
    required this.name,
    this.nameAr,
    this.nameEn,
    this.category,
    this.brand,
    this.quantityText,
    this.imageUrl,
    this.origin,
    this.photo,
  });
}

/// One page of the browse list, whatever the source (local or server).
class CatalogBrowseResult {
  final int total;
  final int limit;
  final int offset;
  final List<CatalogPrefill> products;

  const CatalogBrowseResult({
    required this.total,
    required this.limit,
    required this.offset,
    required this.products,
  });
}
