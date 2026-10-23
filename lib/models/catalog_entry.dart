import 'dart:typed_data';

/// A product catalog entry: barcode -> name, category, photo.
///
/// This is the ONLY data the mapper app owns. No price, no stock — the shop's
/// economics stay in ShopKeeper. The remote server (when deployed) stores the
/// same shape, so this model is the contract between local and remote storage.
///
/// Naming: [name] is the French/Latin primary. [nameAr] is the Arabic-script
/// rendering (how Moroccan shops write the name in Arabic letters). [nameEn]
/// is only set when English DIFFERS from the French primary; null means
/// "same as name". This matches the real need: a French label + Arabic script.
class CatalogEntry {
  final String barcode; // PRIMARY KEY — re-scan updates in place
  final String name; // French/Latin primary
  final String? nameAr; // Arabic script (suggested, editable); null = none
  final String? nameEn; // English if it differs from name; null = same as name
  final String? category;

  /// Small JPEG bytes (downscaled to <=128px, quality 60, ~5-15KB).
  /// Stored as BLOB so the entry is self-contained (sync/export friendly).
  final Uint8List? photo;

  final int createdAt; // epoch ms
  final int updatedAt; // epoch ms — ties broken by newer row on merge

  CatalogEntry({
    required this.barcode,
    required this.name,
    this.nameAr,
    this.nameEn,
    this.category,
    this.photo,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'barcode': barcode,
        'name': name,
        'name_ar': nameAr,
        'name_en': nameEn,
        'category': category,
        'photo': photo,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory CatalogEntry.fromMap(Map<String, Object?> m) => CatalogEntry(
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        nameAr: m['name_ar'] as String?,
        nameEn: m['name_en'] as String?,
        category: m['category'] as String?,
        photo: m['photo'] as Uint8List?,
        createdAt: (m['created_at'] as int?) ?? 0,
        updatedAt: (m['updated_at'] as int?) ?? 0,
      );

  CatalogEntry copyWith({
    String? barcode,
    String? name,
    String? nameAr,
    String? nameEn,
    String? category,
    Uint8List? photo,
    int? createdAt,
    int? updatedAt,
  }) =>
      CatalogEntry(
        barcode: barcode ?? this.barcode,
        name: name ?? this.name,
        nameAr: nameAr ?? this.nameAr,
        nameEn: nameEn ?? this.nameEn,
        category: category ?? this.category,
        photo: photo ?? this.photo,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Display name for a given locale code ('ar', 'fr', 'en').
  /// ar -> nameAr ?? name; en -> nameEn ?? name; otherwise -> name.
  /// Never returns blank: falls back to the French primary.
  String displayName(String locale) {
    switch (locale) {
      case 'ar':
        final ar = nameAr?.trim();
        return (ar != null && ar.isNotEmpty) ? ar : name;
      case 'en':
        final en = nameEn?.trim();
        return (en != null && en.isNotEmpty) ? en : name;
      default:
        return name;
    }
  }
}

/// Local storage seam. The current implementation is SQLite; a remote API
/// implementation can satisfy the same contract when the server is deployed.
/// Swapping the implementation never touches UI or provider code.
abstract class CatalogRepository {
  Future<void> init();
  Future<CatalogEntry?> get(String barcode);
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset});
  Future<void> upsert(CatalogEntry entry);
  Future<void> delete(String barcode);
  Future<int> count({String? search});
}
