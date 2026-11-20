import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../data/catalog_db.dart';
import '../data/db.dart';
import '../models/catalog_entry.dart';

/// JSON exports, one artifact per verb.
///
/// The shop's **listing** (price/stock) must never be labelled "catalog": the
/// catalog is the universal product database, and the shopkeeper has no business
/// exporting it. The UI gates [catalogJson] behind `kIsAdmin`; the listing and
/// history exports are available in both flavors.
///
/// **No export carries photos.** The listing and history are per-shop rows and
/// the catalog export is metadata only (barcode, names, category), so every
/// artifact stays small enough to share and none of them leaks the 13k-image
/// catalog.
class ShopExportService {
  static const _pageSize = 2000;

  static const String listingFormat = 'myhanout-listing-v1';
  static const String historyFormat = 'myhanout-history-v1';
  static const String catalogFormat = 'myhanout-catalog-v1';

  /// The shop's inventory listing: barcode, name, price, stock.
  static Future<String> listingJson(String shopKey) async {
    final db = await Db.open(shopKey);
    final products = await db.getProducts(shopKey);
    return const JsonEncoder.withIndent('  ').convert({
      'format': listingFormat,
      'shop_key': shopKey,
      'exported_at': _now(),
      'count': products.length,
      'rows': [
        for (final p in products)
          {
            'barcode': p.barcode,
            'name': p.name,
            'price_cents': p.priceCents,
            'stock_qty': p.stockQty,
          }
      ],
    });
  }

  /// The shop's sales history: every sale with its line items.
  static Future<String> historyJson(String shopKey) async {
    final db = await Db.open(shopKey);
    final sales = await db.getSales(
      shopKey,
      startMs: 0,
      endMs: _now(),
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': historyFormat,
      'shop_key': shopKey,
      'exported_at': _now(),
      'count': sales.length,
      // `Sale.toMap()` deliberately carries no line items (they are a separate
      // table); a history export without them is not a history.
      'sales': [
        for (final s in sales)
          {...s.toMap(), 'items': [for (final i in s.items) i.toMap()]},
      ],
    });
  }

  /// The universal catalog, metadata only. **Admin only** — the caller must
  /// gate this; nothing in the shopkeeper flavor should reach it.
  ///
  /// Deliberately excludes `photo`: the catalog's value is its metadata, and a
  /// photo dump would be a 49 MB file no shopkeeper can use.
  static Future<String> catalogJson({CatalogRepository? repo}) async {
    final source = repo ?? CatalogDb.instance;
    await source.init();

    final rows = <Map<String, Object?>>[];
    var offset = 0;
    while (true) {
      final page = await source.all(limit: _pageSize, offset: offset);
      if (page.isEmpty) break;
      for (final e in page) {
        rows.add({
          'barcode': e.barcode,
          'name': e.name,
          'name_ar': e.nameAr,
          'name_en': e.nameEn,
          'category': e.category,
        });
      }
      if (page.length < _pageSize) break;
      offset += page.length;
    }

    return const JsonEncoder.withIndent('  ').convert({
      'format': catalogFormat,
      'exported_at': _now(),
      'count': rows.length,
      'products': rows,
    });
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// File name for an exported artifact. Shared so the caller and the tests
  /// agree on it.
  static String fileName(String format, String shopKey) {
    const slugs = {
      listingFormat: 'listing',
      historyFormat: 'history',
      catalogFormat: 'catalog',
    };
    final slug = slugs[format] ?? 'export';
    final key = shopKey.trim();
    // The catalog is universal: with no shop key the artifact is `catalog.json`.
    return key.isEmpty ? '$slug.json' : '${slug}_$key.json';
  }

  /// Writes [json] to a temp file named after [format]/[shopKey] and hands it
  /// to the system share sheet (WhatsApp / file manager).
  ///
  /// Shared by every export entry point so the artifact name and the share
  /// call live in exactly one place. Throws on IO / share failure — the caller
  /// owns the user-facing error message.
  static Future<void> shareJson(String format, String shopKey, String json) async {
    final temp = Directory.systemTemp.createTempSync('myhanout_');
    final name = fileName(format, shopKey);
    final file = File('${temp.path}/$name');
    await file.writeAsString(json);
    await Share.shareXFiles([XFile(file.path)], subject: name);
  }
}
