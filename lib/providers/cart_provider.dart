import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/cart.dart';
import '../utils/app_log.dart';
import '../models/product_lookup_result.dart';
import '../data/db.dart';
import '../data/product_lookup.dart';
import '../build_config.dart';

class CartProvider with ChangeNotifier {
  final String shopKey;
  final Cart _cart = Cart();
  List<Product> _products = [];
  bool _productsLoading = false;
  bool _loadingMoreProducts = false;
  int _totalProducts = 0;
  String _lastSearch = '';
  final String _businessName;

  /// Rows per inventory page. The shop's own listing is normally small, but a
  /// large import must not load unbounded into memory.
  static const int productsPageSize = 50;

  List<CartLine> get lines => _cart.lines;
  int get totalCents => _cart.totalCents;
  int get itemCount => _cart.itemCount;
  bool get isEmpty => _cart.isEmpty;
  List<Product> get products => _products;
  bool get productsLoading => _productsLoading;
  bool get loadingMoreProducts => _loadingMoreProducts;

  /// Total rows for the current search, not just the loaded page.
  int get totalProducts => _totalProducts;
  bool get hasMoreProducts => _products.length < _totalProducts;
  String get businessName => _businessName;

  CartProvider(this.shopKey, {String? businessName})
      : _businessName = businessName ?? 'Maison du Marché' {
    loadProducts();
  }

  /// Loads the first page (or the whole list when [all] is set).
  Future<void> loadProducts({String? search, bool all = false}) async {
    _lastSearch = search ?? _lastSearch;
    _productsLoading = true;
    notifyListeners();
    final db = await Db.open(shopKey);
    _totalProducts = await db.countProducts(shopKey, search: _lastSearch);
    _products = await db.getProducts(
      shopKey,
      search: _lastSearch,
      limit: all ? null : productsPageSize,
    );
    _productsLoading = false;
    notifyListeners();
  }

  /// Appends the next page. No-op while a page is in flight or when the list
  /// is already complete.
  Future<void> loadMoreProducts() async {
    if (_loadingMoreProducts || !hasMoreProducts) return;
    _loadingMoreProducts = true;
    notifyListeners();
    final db = await Db.open(shopKey);
    final page = await db.getProducts(
      shopKey,
      search: _lastSearch,
      limit: productsPageSize,
      offset: _products.length,
    );
    _products = [..._products, ...page];
    _loadingMoreProducts = false;
    notifyListeners();
  }

  /// Barcode lookup for the checkout scan: the in-memory list first, then the
  /// shop database. Keeps the scan path offline and lets the screen stay clear
  /// of the data layer.
  Future<Product?> findByBarcode(String barcode) async {
    final cached = _products.where((p) => p.barcode == barcode).firstOrNull;
    if (cached != null) return cached;
    final db = await Db.open(shopKey);
    return db.getByBarcode(shopKey, barcode);
  }

  /// Inserts a new product or updates an existing one (matched by id).
  Future<void> saveProduct(Product p) async {
    if (p.id == null) {
      final db = await Db.open(shopKey);
      await db.insertProduct(shopKey, p);
    } else {
      final db = await Db.open(shopKey);
      await db.updateProduct(shopKey, p);
    }
    await loadProducts(search: _lastSearch);
  }

  Future<void> deleteProduct(int id) async {
    final db = await Db.open(shopKey);
    await db.deleteProduct(shopKey, id);
    await loadProducts(search: _lastSearch);
  }

  /// Looks up an unknown barcode via Open Food Facts (after a local miss).
  /// Returns null if not found or the network is unavailable.
  ///
  /// Admin-only: the shopkeeper flavor must stay 100% offline, so it never
  /// reaches an external barcode DB — not even on a local-catalog miss.
  /// `kIsAdmin` is a build-time const, so a shopkeeper release build
  /// tree-shakes [ProductLookup] and its sources out entirely.
  Future<ProductLookupResult?> lookupProduct(String barcode) =>
      kIsAdmin ? ProductLookup().fetch(barcode) : Future.value(null);

  void addToCart(Product product, {int qty = 1}) {
    _cart.add(product, qty: qty);
    notifyListeners();
  }

  void setQty(Product product, int qty) {
    _cart.setQty(product, qty);
    notifyListeners();
  }

  void removeAt(int index) {
    _cart.removeAt(index);
    notifyListeners();
  }

  /// Restores a removed line at [index] (used by cart-line delete undo).
  void insertAt(int index, CartLine line) {
    _cart.insertAt(index, line);
    notifyListeners();
  }

  void clear() {
    _cart.clear();
    notifyListeners();
  }

  /// Completes the sale: records the sale, deducts stock, clears cart, reloads products.
  /// Returns the total in cents. Throws on failure (caller shows error).
  Future<int> completeSale() async {
    if (_cart.isEmpty) return 0;
    final total = _cart.totalCents;
    final deductions = _cart.stockDeductions();

    // Capture line items before clearing the cart.
    final items = _cart.lines.map((line) => {
      'productName': line.product.name,
      'unitPriceCents': line.product.priceCents,
      'quantity': line.qty,
      'lineTotalCents': line.lineTotalCents,
    }).toList();

    final db = await Db.open(shopKey);
    await db.insertSale(shopKey, total, items);
    await db.deductStock(shopKey, deductions);
    // Visible in logcat even on a release build, so a completed sale can be
    // confirmed without a debugger.
    logInfo('sale completed: ${items.length} line(s), '
        '$total cents, shop $shopKey');
    _cart.clear();
    await loadProducts();
    return total;
  }
}
