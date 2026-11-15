/// A catalog row as served by the catalog server.
///
/// Typed replacement for the `Map<String, dynamic>` the HTTP client used to
/// hand back: the wire shape is now declared once, so a renamed server field
/// is a compile error instead of a silent null in the UI.
class CatalogRow {
  final String barcode;
  final String? name;
  final String? nameAr;
  final String? nameEn;
  final String? category;
  final String? brand;
  final String? quantityText;

  /// Remote image reference (never a stored blob on the server).
  final String? imageUrl;

  /// 'owner' or 'source:off' — who authored the winning row.
  final String? origin;
  final String? license;
  final int updatedAt;

  const CatalogRow({
    required this.barcode,
    this.name,
    this.nameAr,
    this.nameEn,
    this.category,
    this.brand,
    this.quantityText,
    this.imageUrl,
    this.origin,
    this.license,
    this.updatedAt = 0,
  });

  factory CatalogRow.fromMap(Map<String, dynamic> m) => CatalogRow(
        barcode: (m['barcode'] ?? '') as String,
        name: m['name'] as String?,
        nameAr: m['name_ar'] as String?,
        nameEn: m['name_en'] as String?,
        category: m['category'] as String?,
        brand: m['brand'] as String?,
        quantityText: m['quantity_text'] as String?,
        imageUrl: m['image_url'] as String?,
        origin: m['origin'] as String?,
        license: m['license'] as String?,
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
      );

  bool get isOwner => origin == 'owner';
}

/// One page of `GET /v1/products/search`.
class CatalogSearchResult {
  final int total;
  final int limit;
  final int offset;
  final List<CatalogRow> products;

  const CatalogSearchResult({
    required this.total,
    required this.limit,
    required this.offset,
    required this.products,
  });

  factory CatalogSearchResult.fromMap(Map<String, dynamic> m) =>
      CatalogSearchResult(
        total: (m['total'] as num?)?.toInt() ?? 0,
        limit: (m['limit'] as num?)?.toInt() ?? 0,
        offset: (m['offset'] as num?)?.toInt() ?? 0,
        products: ((m['products'] as List?) ?? [])
            .map((p) => CatalogRow.fromMap(p as Map<String, dynamic>))
            .toList(),
      );
}
