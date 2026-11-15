import 'product.dart';

/// Which rows the inventory list shows.
///
/// The list is narrowed in two stages, and the order is deliberate:
///
/// 1. **Search** runs in the provider's SQL query
///    (`CartProvider.loadProducts(search: ...)`), so it is the first filter —
///    it is paged and it drives `totalProducts`.
/// 2. **The chip** is an in-memory predicate over the already-search-narrowed
///    page ([apply]).
///
/// The chips are mutually exclusive views (all / low stock / local additions),
/// so `lowStock` and `local` are alternative views rather than stacked
/// conditions: a local row that is also low stock appears in both views, but
/// the user picks one view at a time.
enum InventoryFilter {
  /// Every row (the default view).
  all,

  /// Rows at or below their own low-stock threshold.
  lowStock,

  /// Rows the shopkeeper typed by hand (`Product.isLocal`), i.e. additions
  /// that did not come from the catalog.
  local;

  /// Whether [product] belongs in this view.
  bool matches(Product product) => switch (this) {
        InventoryFilter.all => true,
        InventoryFilter.lowStock => product.isLowStock,
        InventoryFilter.local => product.isLocal,
      };

  /// Applies the view to [products] (already search-narrowed by the provider).
  List<Product> apply(List<Product> products) =>
      products.where(matches).toList();
}
