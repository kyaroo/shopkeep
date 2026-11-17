// Regression guard for the deadlocked sale.
//
// `deductStock` writes an audit row per product inside its transaction. It used
// to call `Audit.log` without the transaction handle, so the write went through
// the top-level database handle — which sqflite serialises *behind* the very
// transaction that issued it. The sale then never completed: the only symptom
// on device was `Warning database has been locked for 0:00:10` and a
// "Valider la vente" button that did nothing.
//
// ffi reproduces the same queueing, so the lock warning is observable here.
// Run: flutter test test/services/sale_audit_transaction_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/models/product.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _shop = 'sale-txn-shop';

Future<void> _cleanUp() async {
  await Db.closeShop(_shop);
  final f = await Db.shopDbFile(_shop);
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('${f.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _cleanUp();
  });

  tearDown(() async {
    await _cleanUp();
  });

  // The API has no reset (it null-asserts both arguments), so restore a
  // no-op callback at the default 10s threshold.
  tearDownAll(() => sqflite.Sqflite.setLockWarningInfo(
        duration: const Duration(seconds: 10),
        callback: () {},
      ));

  test('a sale never queues a write behind its own transaction', () async {
    var lockWarnings = 0;
    sqflite.Sqflite.setLockWarningInfo(
      duration: const Duration(milliseconds: 50),
      callback: () => lockWarnings++,
    );

    final db = await Db.open(_shop);
    final id = await db.insertProduct(
      _shop,
      Product(
        name: 'Tabasco Habanero',
        barcode: '0011210006508',
        priceCents: 1250,
        stockQty: 10,
      ),
    );

    await db.insertSale(_shop, 2500, [
      {'productName': 'Tabasco Habanero', 'unitPriceCents': 1250,
       'quantity': 2, 'lineTotalCents': 2500},
    ]);
    await db.deductStock(_shop, {id: 2});

    // No operation may wait on the transaction that is waiting on it.
    expect(lockWarnings, 0,
        reason: 'a database write deadlocked behind its own transaction');

    // The deduction is real, and its audit row was written (not swallowed by
    // a lock timeout).
    final product = await Db.getProductById(_shop, id);
    expect(product!.stockQty, 8);
    final handle = await Db.databaseHandle(_shop);
    final audit = await handle.query(
      'audit_log',
      where: 'shop_key = ? AND table_name = ?',
      whereArgs: [_shop, 'products'],
    );
    expect(audit, isNotEmpty,
        reason: 'the stock deduction must leave an audit trail');
  });
}
