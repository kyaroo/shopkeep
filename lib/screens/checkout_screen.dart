import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/cart_provider.dart';
import '../models/product.dart';
import '../models/product_lookup_result.dart';
import '../data/db.dart';
import '../utils/money.dart';

/// Top-level entry used by the HomePage FAB. Scans a barcode, adds to cart
/// if known, or offers to capture the item from a barcode database.
Future<void> scanToAdd(BuildContext context) async {
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
  final result = await cart.lookupProduct(code);
  if (!context.mounted) return;
  if (result == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('notFoundOnline'.tr())),
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

/// Body of the Checkout tab (the single AppBar/FAB live in HomePage).
class CheckoutBody extends StatelessWidget {
  const CheckoutBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    return Column(
      children: [
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Text('cartEmpty'.tr(), textAlign: TextAlign.center),
                )
              : ListView.separated(
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final line = cart.lines[i];
                    final p = line.product;
                    return ListTile(
                      title: Text(p.name),
                      subtitle:
                          Text('${formatMoney(p.priceCents)} ${'each'.tr()}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => cart.setQty(p, line.qty - 1),
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
                  Text('items'.tr(namedArgs: {'count': '${cart.itemCount}'}),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    'total'.tr(
                        namedArgs: {'amount': formatMoney(cart.totalCents)}),
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
                                    content: Text('saleComplete'.tr(
                                        namedArgs: {'amount': formatMoney(total)}))),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('saleFailed'.tr(
                                        namedArgs: {'error': e.toString()})),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.check),
                  label: Text('completeSale'.tr()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BarcodeScanPage extends StatelessWidget {
  const BarcodeScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('scanBarcode'.tr())),
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
      title: Text('newItemFromScan'.tr()),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.displayName,
                  style: Theme.of(context).textTheme.titleMedium),
              if (r.quantity != null) Text('${'qtyLabel'.tr()}: ${r.quantity}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                decoration: InputDecoration(
                    labelText: '${'yourPrice'.tr()} *',
                    hintText: 'priceHint'.tr()),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 ? 'nameRequired'.tr() : null;
                },
              ),
              TextFormField(
                controller: _stock,
                decoration:
                    InputDecoration(labelText: '${'stockQty'.tr()} *'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 ? 'nameRequired'.tr() : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr())),
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
          child: Text('addAndCart'.tr()),
        ),
      ],
    );
  }
}
