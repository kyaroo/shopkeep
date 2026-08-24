import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../models/product.dart';
import '../models/product_lookup_result.dart';
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
    if (product != null) {
      cart.addToCart(product);
      return;
    }
    // Local miss: try Open Food Facts to capture the item, then add it.
    final result = await cart.lookupProduct(code);
    if (!context.mounted) return;
    if (result == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Not in inventory and not found online — add it manually from Inventory')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final created = await showDialog<Product>(
      context: context,
      builder: (_) => _NewFromScanDialog(result: result),
    );
    if (created != null && context.mounted) {
      cart.addToCart(created);
    }
  }

  Future<dynamic> _lookup(String code, CartProvider cart) async {
    final inCache = cart.products.where((p) => p.barcode == code).firstOrNull;
    if (inCache != null) return inCache;
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

/// Shown at Checkout when a scanned barcode isn't in inventory but was
/// found on Open Food Facts. Pre-fills name; manager sets the price, then
/// it's saved to inventory and added to the cart.
class _NewFromScanDialog extends StatefulWidget {
  final ProductLookupResult result;
  const _NewFromScanDialog({required this.result});

  @override
  State<_NewFromScanDialog> createState() => _NewFromScanDialogState();
}

class _NewFromScanDialogState extends State<_NewFromScanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '1');
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return AlertDialog(
      title: const Text('New item from scan'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.displayName,
                  style: Theme.of(context).textTheme.titleMedium),
              if (r.quantity != null) Text('Qty: ${r.quantity}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                    labelText: 'Your price (cents) *',
                    hintText: 'e.g. 1990 = 19.90'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 ? 'Enter a whole number' : null;
                },
              ),
              TextFormField(
                controller: _stock,
                decoration: const InputDecoration(labelText: 'Stock qty *'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 ? 'Enter a whole number' : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() => _saving = true);
                  final p = Product(
                    name: r.displayName,
                    barcode: r.barcode.isEmpty ? null : r.barcode,
                    priceCents: int.parse(_price.text.trim()),
                    stockQty: int.parse(_stock.text.trim()),
                  );
                  if (!mounted) return;
                  final cart =
                      Provider.of<CartProvider>(context, listen: false);
                  final navigator = Navigator.of(context);
                  await cart.saveProduct(p);
                  if (mounted) navigator.pop(p);
                },
          child: const Text('Add & put in cart'),
        ),
      ],
    );
  }
}

