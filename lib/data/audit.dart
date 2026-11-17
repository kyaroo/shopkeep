library;

/// Mandatory mutation audit. Runs after every data change; JSON blobs are
/// TEXT columns. Defensively encodes — any failure is logged and swallowed so
/// audit never blocks the business flow.
///
/// Every data mutation in Db logs a row: action, table, record_id,
/// old_values/new_values, changed_at, changed_by.
import 'dart:convert';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../utils/app_log.dart';
import 'db.dart';

class Audit {
  /// Records a mutation row.
  ///
  /// [txn] must be passed when the caller is already inside a transaction.
  /// sqflite serialises operations per database: using the top-level handle
  /// from inside `db.transaction(...)` queues the write *behind* that same
  /// transaction, which never completes — a silent permanent deadlock (the
  /// only symptom is `Warning database has been locked for 0:00:10`).
  static Future<int> log({
    required String shopKey,
    required String action,
    required String table,
    required int recordId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    String changedBy = 'system',
    DatabaseExecutor? txn,
  }) async {
    try {
      final oldJson = oldValues == null ? null : const JsonEncoder.withIndent('  ').convert(oldValues);
      final newJson = newValues == null ? null : const JsonEncoder.withIndent('  ').convert(newValues);
      final db = txn ?? await Db.databaseHandle(shopKey);
      return await db.rawInsert(
        'INSERT INTO audit_log '
        '(shop_key, action, table_name, record_id, old_values, new_values, changed_at, changed_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          shopKey, action, table, recordId, oldJson, newJson,
          DateTime.now().millisecondsSinceEpoch, changedBy,
        ],
      );
    } catch (e) {
      logWarning('audit log write failed', error: e);
      return 0;
    }
  }
}
