import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/sale.dart';
import '../utils/money.dart';

class SaleDetailScreen extends StatelessWidget {
  final Sale sale;
  const SaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('saleDetail'.tr())),
      body: Column(
        children: [
          // Header: date + total
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Text(
                  _formatDateTime(sale.dateTime),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(sale.totalCents),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Line items
          Expanded(
            child: ListView.separated(
              itemCount: sale.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = sale.items[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            '${item.quantity} × ${formatMoney(item.unitPriceCents)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            formatMoney(item.lineTotalCents),
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
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) {
    final y = d.year.toString();
    final mo = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$y-$mo-$da $h:$mi';
  }
}
