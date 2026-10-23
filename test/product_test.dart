import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/models/product.dart';

Product p({
  int? id,
  String name = 'A',
  int priceCents = 100,
  int stockQty = 5,
  int lowStockThreshold = 5,
}) =>
    Product(
      id: id,
      name: name,
      priceCents: priceCents,
      stockQty: stockQty,
      lowStockThreshold: lowStockThreshold,
    );

void main() {
  test('isLowStock is true when stock at or below threshold', () {
    expect(p(stockQty: 3, lowStockThreshold: 5).isLowStock, isTrue);
    expect(p(stockQty: 5, lowStockThreshold: 5).isLowStock, isTrue);
  });

  test('isLowStock is false when stock above threshold', () {
    expect(p(stockQty: 6, lowStockThreshold: 5).isLowStock, isFalse);
  });

  test('isOutOfStock is true only at zero', () {
    expect(p(stockQty: 0).isOutOfStock, isTrue);
    expect(p(stockQty: 1).isOutOfStock, isFalse);
  });

  test('fromMap/toMap round-trips low_stock_threshold', () {
    final m = p(id: 1, lowStockThreshold: 9).toMap();
    expect(m['low_stock_threshold'], 9);
    final back = Product.fromMap(m);
    expect(back.lowStockThreshold, 9);
  });

  test('fromMap defaults missing threshold to 5 (pre-migration rows)', () {
    final prod = Product.fromMap({
      'id': 1, 'name': 'A', 'barcode': null,
      'price_cents': 100, 'stock_qty': 2,
    });
    expect(prod.lowStockThreshold, 5);
  });

  test('copyWith carries threshold', () {
    final a = p(lowStockThreshold: 3);
    expect(a.copyWith(name: 'B').lowStockThreshold, 3);
    expect(a.copyWith(lowStockThreshold: 8).lowStockThreshold, 8);
  });
}
