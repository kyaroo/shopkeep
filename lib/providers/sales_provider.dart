import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models/sale.dart';

/// View state for the sales-history screen.
///
/// Owns the selected range, the loaded sales and the derived stats, and is the
/// only place that touches the shop database for this screen — the widget
/// renders [sales]/[stats] and asks for a reload via [setRange] (rule 3/9:
/// UI never reaches the data layer directly).
class SalesProvider with ChangeNotifier {
  final String shopKey;

  SalesProvider(
    this.shopKey, {
    DateTime? start,
    DateTime? end,
  }) {
    final now = DateTime.now();
    _start = start ?? DateTime(now.year, now.month, now.day);
    _end = end ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
    ready = load();
  }

  /// Completes after the first [load], so a caller (or a test) can await the
  /// initial state instead of guessing how many event-loop turns it takes.
  late final Future<void> ready;

  late DateTime _start;
  late DateTime _end;
  List<Sale> _sales = [];
  Map<String, int> _stats = {};
  bool _loading = true;

  List<Sale> get sales => _sales;
  Map<String, int> get stats => _stats;
  bool get loading => _loading;
  DateTime get start => _start;
  DateTime get end => _end;

  /// Reloads the current range.
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final db = await Db.open(shopKey);
    final startMs = _start.millisecondsSinceEpoch;
    final endMs = _end.millisecondsSinceEpoch;
    final sales = await db.getSales(shopKey, startMs: startMs, endMs: endMs);
    final stats = await db.getSalesStats(shopKey, startMs: startMs, endMs: endMs);
    _sales = sales;
    _stats = stats;
    _loading = false;
    notifyListeners();
  }

  /// Moves the range (inclusive start, inclusive end) and reloads.
  Future<void> setRange(DateTime start, DateTime end) async {
    _start = DateTime(start.year, start.month, start.day);
    _end = DateTime(end.year, end.month, end.day, 23, 59, 59);
    await load();
  }
}
