import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../data/db.dart';
import '../utils/money.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  Future<void> _scanToAdd(BuildContext context) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code == null || !context.mounted) return;
    final cart = Provider.of<CartProvider>(context, listen: false);
    final product = await _lookup(code, cart);
    if (product == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barcode not found in inventory')),
        );
      }
      return;
    }
    cart.addToCart(product);
  }

  Future<dynamic> _lookup(String code, CartProvider cart) async {
    // Use DB through provider's products cache first, then DB.
    final inCache = cart.products.where((p) => p.barcode == code).firstOrNull;
    if (inCache != null) return inCache;
    // Fallback: query DB directly via a barcode lookup.
    return Db().getByBarcode(code);
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan to add',
            onPressed: () => _scanToAdd(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: cart.isEmpty
                ? const Center(
                    child: Text(
                        'Cart is empty.\nTap the scanner or a product to add.',
                        textAlign: TextAlign.center),
                  )
                : ListView.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final line = cart.lines[i];
                      final p = line.product;
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text('${formatMoney(p.priceCents)} each'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () =>
                                  cart.setQty(p, line.qty - 1),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text('${line.qty}',
                                  textAlign: TextAlign.center),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => cart.setQty(p, line.qty + 1),
                            ),
                          ],
                        ),
                        onLongPress: () => cart.removeAt(i),
                      );
                    },
                  ),
          ),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Items: ${cart.itemCount}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      'Total: ${formatMoney(cart.totalCents)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: cart.isEmpty
                        ? null
                        : () async {
                            try {
                              final total = await cart.completeSale();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Sale complete — ${formatMoney(total)}')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Sale failed: $e'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('Complete sale'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BarcodeScanPage extends StatelessWidget {
  const BarcodeScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null) Navigator.pop(context, code);
        },
      ),
    );
  }
}
