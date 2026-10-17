import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../data/db.dart';
import '../models/sale.dart';
import '../utils/money.dart';
import 'sale_detail_screen.dart';

// Per-shop identity: one APK = one shop for MVP.
// The shopKey is set once at first launch and stored in shared_preferences
// (not yet implemented — default 'default' covers the single-store MVP).
String get shopKey => const String.fromEnvironment('SHOP_KEY', defaultValue: 'default');

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  List<Sale> _sales = [];
  Map<String, int> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final db = await Db.open(shopKey);
    final sales = await db.getSales(shopKey, startMs: _startDate.millisecondsSinceEpoch, endMs: _endDate.millisecondsSinceEpoch);
    final stats = await db.getSalesStats(shopKey, startMs: _startDate.millisecondsSinceEpoch, endMs: _endDate.millisecondsSinceEpoch);
    if (!mounted) return;
    setState(() {
      _sales = sales;
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('salesHistory'.tr())),
      body: Column(
        children: [
          // Date range filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formatDate(_startDate)),
                    onPressed: () => _pickDate(true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formatDate(_endDate)),
                    onPressed: () => _pickDate(false),
                  ),
                ),
              ],
            ),
          ),
          // Summary bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: 'totalRevenue'.tr(),
                  value: formatMoney(_stats['totalRevenueCents'] ?? 0),
                ),
                _StatItem(
                  label: 'salesCount'.tr(),
                  value: '${_stats['saleCount'] ?? 0}',
                ),
                _StatItem(
                  label: 'itemsSold'.tr(),
                  value: '${_stats['totalItems'] ?? 0}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Sales list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                    ? Center(child: Text('noSalesInPeriod'.tr()))
                    : ListView.separated(
                        itemCount: _sales.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final sale = _sales[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text('${sale.itemCount}'),
                            ),
                            title: Text(_formatDateTime(sale.dateTime)),
                            subtitle: Text(
                              'itemsCount'.tr(namedArgs: {'count': '${sale.itemCount}'}),
                            ),
                            trailing: Text(
                              formatMoney(sale.totalCents),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SaleDetailScreen(sale: sale),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${_formatDate(d)} $h:$m';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
