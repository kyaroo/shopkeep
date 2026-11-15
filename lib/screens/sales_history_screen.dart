import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../providers/sales_provider.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'sale_detail_screen.dart';

/// Sales history for the active shop. Stateless: all state and data access
/// live in [SalesProvider].
class SalesHistoryScreen extends StatelessWidget {
  const SalesHistoryScreen({super.key});

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final sales = context.read<SalesProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? sales.start : sales.end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final start = isStart ? picked : sales.start;
    final end = isStart ? sales.end : picked;
    await sales.setRange(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
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
                    label: Text(_formatDate(sales.start)),
                    onPressed: () => _pickDate(context, true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formatDate(sales.end)),
                    onPressed: () => _pickDate(context, false),
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
                  value: formatMoney(sales.stats['totalRevenueCents'] ?? 0),
                ),
                _StatItem(
                  label: 'salesCount'.tr(),
                  value: '${sales.stats['saleCount'] ?? 0}',
                ),
                _StatItem(
                  label: 'itemsSold'.tr(),
                  value: '${sales.stats['totalItems'] ?? 0}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Sales list
          Expanded(
            child: sales.loading
                ? const Center(child: CircularProgressIndicator())
                : sales.sales.isEmpty
                    ? Center(child: Text('noSalesInPeriod'.tr()))
                    : ListView.separated(
                        itemCount: sales.sales.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final sale = sales.sales[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text('${sale.itemCount}'),
                            ),
                            title: Text(_formatDateTime(sale.dateTime)),
                            subtitle: Text(
                              'itemsCount'.tr(namedArgs: {'count': '${sale.itemCount}'}),
                            ),
                            trailing: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatMoney(sale.totalCents),
                                style: Theme.of(context)
                                    .extension<AppTextStyles>()!
                                    .lineTotal(context),
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
