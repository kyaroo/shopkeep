import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/cart.dart';
import '../models/product_lookup_result.dart';
import '../data/db.dart';
import '../data/product_lookup.dart';

class CartProvider with ChangeNotifier {
  final String shopKey;
  final Cart _cart = Cart();
  List<Product> _products = [];
  bool _productsLoading = false;
  String _lastSearch = '';
  String _businessName = 'Maison du Marché';

  List<CartLine> get lines => _cart.lines;
  int get totalCents => _cart.totalCents;
  int get itemCount => _cart.itemCount;
  bool get isEmpty => _cart.isEmpty;
  List<Product> get products => _products;
  bool get productsLoading => _productsLoading;
  String get businessName => _businessName;

  CartProvider(this.shopKey, {String? businessName})
      : _businessName = businessName ??= 'Maison du Marché' {
    loadProducts();
  }

  Future<void> loadProducts({String? search}) async {
    _lastSearch = search ?? _lastSearch;
    _productsLoading = true;
    notifyListeners();
    final db = await Db.open(shopKey);
    _products = await db.getProducts(shopKey, search: search);
    _productsLoading = false;
    notifyListeners();
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
  Future<ProductLookupResult?> lookupProduct(String barcode) =>
      ProductLookup().fetch(barcode);

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
    _cart.clear();
    await loadProducts();
    return total;
  }
}
