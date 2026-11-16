/// Shared slug helper for shop keys.
String slugify(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// A shop key becomes a **filename component** (`myhanout_<key>.db`), so it must
/// be a safe slug: lowercase alphanumerics plus `_`/`-`, no separators, no dots,
/// no traversal, bounded length.
///
/// Every entry point that accepts a shop key from the outside (typed join, QR
/// payload) must validate it; `Db.shopDbPath` enforces it again as the last
/// line of defence.
final RegExp _shopKeyPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$');

bool isValidShopKey(String key) => _shopKeyPattern.hasMatch(key);
