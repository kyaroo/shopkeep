import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/models/product.dart';
import 'package:myhanout/models/cart.dart';

Product p(String name, int priceCents, int stock, {int? id}) =>
    Product(id: id, name: name, priceCents: priceCents, stockQty: stock);

void main() {
  group('Cart totals', () {
    test('total of mixed lines is sum of price*qty', () {
      final cart = Cart();
      cart.add(p('A', 199, 5, id: 1), qty: 2); // 398
      cart.add(p('B', 250, 3, id: 2), qty: 1); // 250
      expect(cart.totalCents, 648);
      expect(cart.itemCount, 3);
    });

    test('adding same product again increments qty, not lines', () {
      final cart = Cart();
      cart.add(p('A', 100, 9, id: 1), qty: 1);
      cart.add(p('A', 100, 9, id: 1), qty: 2);
      expect(cart.lines.length, 1);
      expect(cart.lines.first.qty, 3);
      expect(cart.totalCents, 300);
    });

    test('empty cart total is zero', () {
      expect(Cart().totalCents, 0);
      expect(Cart().isEmpty, isTrue);
    });
  });

  group('Cart stock guards', () {
    test('cannot add beyond available stock', () {
      final cart = Cart();
      expect(() => cart.add(p('A', 100, 2, id: 1), qty: 3),
          throwsStateError);
      expect(cart.isEmpty, isTrue);
    });

    test('cannot over-increment existing line beyond stock', () {
      final cart = Cart();
      cart.add(p('A', 100, 3, id: 1), qty: 2);
      expect(() => cart.setQty(cart.lines.first.product, 5), throwsStateError);
      expect(cart.lines.first.qty, 2); // unchanged
    });

    test('setQty 0 removes the line', () {
      final cart = Cart();
      final prod = p('A', 100, 5, id: 1);
      cart.add(prod, qty: 2);
      cart.setQty(prod, 0);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('Cart stockDeductions', () {
    test('maps productId to qty for DB deduction', () {
      final cart = Cart();
      cart.add(p('A', 100, 5, id: 1), qty: 2);
      cart.add(p('B', 200, 5, id: 2), qty: 1);
      final map = cart.stockDeductions();
      expect(map, {1: 2, 2: 1});
    });
  });

  group('Cart insertAt (undo restore)', () {
    test('restores a removed line at its original index', () {
      final cart = Cart();
      cart.add(p('A', 100, 5, id: 1), qty: 2);
      cart.add(p('B', 200, 5, id: 2), qty: 1);
      cart.add(p('C', 300, 5, id: 3), qty: 4);
      final removed = cart.lines[1]; // B
      cart.removeAt(1);
      expect(cart.lines.length, 2);
      cart.insertAt(1, removed);
      expect(cart.lines.length, 3);
      expect(cart.lines[1].product.name, 'B');
      expect(cart.lines[1].qty, 1);
      expect(cart.totalCents, 200 + 200 + 1200);
    });

    test('clamps index out of range', () {
      final cart = Cart();
      cart.add(p('A', 100, 5, id: 1), qty: 1);
      cart.insertAt(99, CartLine(p('B', 200, 5, id: 2), 1));
      expect(cart.lines.length, 2);
      expect(cart.lines.last.product.name, 'B');
    });
  });
}
