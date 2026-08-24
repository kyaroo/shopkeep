import '../models/product.dart';

/// A line in the checkout cart: one product + quantity.
class CartLine {
  final Product product;
  final int qty;

  CartLine(this.product, this.qty);

  int get lineTotalCents => product.priceCents * qty;
}

/// Pure checkout logic. No Flutter, no device — fully unit-testable.
class Cart {
  final List<CartLine> _lines = [];

  List<CartLine> get lines => List.unmodifiable(_lines);

  int get itemCount => _lines.fold(0, (sum, l) => sum + l.qty);

  int get totalCents => _lines.fold(0, (sum, l) => sum + l.lineTotalCents);

  bool get isEmpty => _lines.isEmpty;

  void add(Product product, {int qty = 1}) {
    if (qty <= 0) return;
    if (product.stockQty < qty) {
      throw StateError('Not enough stock for ${product.name}');
    }
    final idx = _lines.indexWhere((l) => l.product.id == product.id);
    if (idx >= 0) {
      final newQty = _lines[idx].qty + qty;
      if (newQty > product.stockQty) {
        throw StateError('Not enough stock for ${product.name}');
      }
      _lines[idx] = CartLine(product, newQty);
    } else {
      _lines.add(CartLine(product, qty));
    }
  }

  void setQty(Product product, int qty) {
    final idx = _lines.indexWhere((l) => l.product.id == product.id);
    if (idx < 0) return;
    if (qty <= 0) {
      _lines.removeAt(idx);
      return;
    }
    if (qty > product.stockQty) {
      throw StateError('Not enough stock for ${product.name}');
    }
    _lines[idx] = CartLine(product, qty);
  }

  void removeAt(int index) {
    if (index >= 0 && index < _lines.length) _lines.removeAt(index);
  }

  void clear() => _lines.clear();

  /// Returns a map of productId -> quantity deducted, and the new stock per product.
  /// Caller persists these to the database.
  Map<int, int> stockDeductions() {
    final map = <int, int>{};
    for (final l in _lines) {
      map[l.product.id!] = l.qty;
    }
    return map;
  }
}
