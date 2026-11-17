import '../data/catalog_db.dart';
import '../data/db.dart';

/// One recorded change, from either attribution source.
///
/// Two different logs feed this, and they answer different questions:
/// - `catalog` — **who pushed which catalog generation** (`signer_log`, written
///   when a `.myhanout` delta is applied). Device-wide.
/// - `listing` — **who changed a price or a stock level** (`audit_log`, written
///   by the listing merge). Per shop.
class AttributionEntry {
  /// `catalog` or `listing`.
  final String kind;

  /// The signer's display name, or the recorded `changed_by`.
  final String actor;

  /// Short human detail, e.g. `v12 · 38 rows` or `update #7`.
  final String detail;

  /// Epoch ms, used to sort newest-first.
  final int at;

  const AttributionEntry({
    required this.kind,
    required this.actor,
    required this.detail,
    required this.at,
  });
}

/// Reads the attribution trail for the Settings screen.
///
/// Read-only and offline: both sources are local tables. Nothing here contacts
/// a server, and the shopkeeper flavor never does.
class AttributionService {
  /// Newest-first, capped at [limit].
  ///
  /// The two sources are merged by timestamp so a single timeline shows both
  /// catalog pushes and listing edits in the order they happened.
  static Future<List<AttributionEntry>> recent({
    required String shopKey,
    int limit = 50,
  }) async {
    final entries = <AttributionEntry>[];

    final catalog = CatalogDb.instance;
    await catalog.init();
    for (final row in await catalog.signerLog()) {
      entries.add(AttributionEntry(
        kind: 'catalog',
        actor: (row['signed_by'] as String?) ?? '',
        detail: 'v${row['version']} · ${row['entry_count']}',
        at: (row['applied_at'] as int?) ?? 0,
      ));
    }

    await Db.open(shopKey);
    final handle = await Db.databaseHandle(shopKey);
    final rows = await handle.query(
      'audit_log',
      where: "table_name = 'products'",
      orderBy: 'changed_at DESC',
      limit: limit,
    );
    for (final row in rows) {
      entries.add(AttributionEntry(
        kind: 'listing',
        actor: (row['changed_by'] as String?) ?? '',
        detail: '${row['action']} #${row['record_id']}',
        at: (row['changed_at'] as int?) ?? 0,
      ));
    }

    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries.take(limit).toList();
  }
}
