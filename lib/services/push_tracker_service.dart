/// Tracks catalog push actions performed by the admin.
///
/// Each push records which shop received which target version, so the admin
/// can review the history and the server can reconcile versions (single
/// source of truth).
///
/// Note: for v0.1 this is an in-memory tracker. A durable store (SQLite table
/// or server-side table) can be added for production.
class PushTracker {
  final _pushes = <String, PushRecord>{};

  /// Records a push. [producedAt] is the server epoch ms at generation time.
  void record(String shopKey, int targetVersion, int producedAt,
      {String status = 'ok'}) {
    _pushes[shopKey] = PushRecord(
      shopKey: shopKey,
      targetVersion: targetVersion,
      producedAt: producedAt,
      status: status,
      recordedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Returns all recorded pushes, ordered by recorded time (newest first).
  List<PushRecord> get all {
    return _pushes.values.toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  }

  /// Returns the latest push for a shop.
  PushRecord? forShop(String shopKey) => _pushes[shopKey];
}

class PushRecord {
  final String shopKey;
  final int targetVersion;
  final int producedAt;
  final String status;
  final int recordedAt;

  PushRecord({
    required this.shopKey,
    required this.targetVersion,
    required this.producedAt,
    required this.status,
    required this.recordedAt,
  });
}
