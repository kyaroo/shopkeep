library;

/// Mandatory mutation audit. Runs after every data change; JSON blobs are
/// TEXT columns. Defensively encodes — any encoding failure is printed and
/// swallowed so audit never blocks the business flow.
///
/// Every data mutation in Db logs a row: action, table, record_id,
/// old_values/new_values, changed_at, changed_by.
import 'dart:convert';

import 'db.dart';

class Audit {
  static Future<int> log({
    required String shopKey,
    required String action,
    required String table,
    required int recordId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    String changedBy = 'system',
  }) async {
    try {
      final oldJson = oldValues == null ? null : const JsonEncoder.withIndent('  ').convert(oldValues);
      final newJson = newValues == null ? null : const JsonEncoder.withIndent('  ').convert(newValues);
      final db = await Db.databaseHandle(shopKey);
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
      print('[audit] FAILED: $e');
      return 0;
    }
  }
}
