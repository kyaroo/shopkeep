import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/cart.dart';
import '../data/db.dart';

class CartProvider with ChangeNotifier {
  final Cart _cart = Cart();
  List<Product> _products = [];
  bool _productsLoading = false;
  String _lastSearch = '';

  List<CartLine> get lines => _cart.lines;
  int get totalCents => _cart.totalCents;
  int get itemCount => _cart.itemCount;
  bool get isEmpty => _cart.isEmpty;
  List<Product> get products => _products;
  bool get productsLoading => _productsLoading;

  CartProvider() {
    loadProducts();
  }

  Future<void> loadProducts({String? search}) async {
    _lastSearch = search ?? _lastSearch;
    _productsLoading = true;
    notifyListeners();
    _products = await Db().getProducts(search: search);
    _productsLoading = false;
    notifyListeners();
  }

  /// Inserts a new product or updates an existing one (matched by id).
  Future<void> saveProduct(Product p) async {
    if (p.id == null) {
      await Db().insertProduct(p);
    } else {
      await Db().updateProduct(p);
    }
    await loadProducts(search: _lastSearch);
  }

  Future<void> deleteProduct(int id) async {
    await Db().deleteProduct(id);
    await loadProducts(search: _lastSearch);
  }

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

  void clear() {
    _cart.clear();
    notifyListeners();
  }

  /// Completes the sale: deducts stock, clears cart, reloads products.
  /// Returns the total in cents. Throws on failure (caller shows error).
  Future<int> completeSale() async {
    if (_cart.isEmpty) return 0;
    final total = _cart.totalCents;
    final deductions = _cart.stockDeductions();
    await Db().deductStock(deductions);
    _cart.clear();
    await loadProducts();
    return total;
  }
}
