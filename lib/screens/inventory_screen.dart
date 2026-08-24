import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../utils/money.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      Provider.of<CartProvider>(context, listen: false)
          .loadProducts(search: _search.text.trim());
    });
  }

  Future<void> _showProductForm({Product? existing}) async {
    final saved = await showDialog<Product>(
      context: context,
      builder: (_) => ProductFormDialog(existing: existing),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(existing != null ? 'Updated' : 'Added to inventory')),
      );
    }
  }

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${p.name}" from inventory?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await Provider.of<CartProvider>(context, listen: false)
          .deleteProduct(p.id!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final products = cart.products;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: cart.productsLoading
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? const Center(
                        child: Text('No products yet.\nTap + to add one.',
                            textAlign: TextAlign.center))
                    : ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = products[i];
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(
                                '${formatMoney(p.priceCents)}  •  stock: ${p.stockQty}'
                                '${p.barcode != null ? '  •  ${p.barcode}' : ''}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showProductForm(existing: p),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _confirmDelete(p),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductForm(),
        tooltip: 'Add product',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ProductFormDialog extends StatefulWidget {
  final Product? existing;
  const ProductFormDialog({super.key, this.existing});

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _barcode = TextEditingController();
  bool _saving = false;
  bool _lookingUp = false;
  bool _lookedUp = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _name.text = p.name;
      _price.text = p.priceCents.toString();
      _stock.text = p.stockQty.toString();
      _barcode.text = p.barcode ?? '';
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code == null || !mounted) return;
    setState(() => _barcode.text = code);

    // If this barcode is already in inventory, don't overwrite the name.
    final inInventory =
        Provider.of<CartProvider>(context, listen: false).products.any(
      (p) => p.barcode == code,
    );
    if (inInventory) return;

    // Offline-first: local miss -> try Open Food Facts to pre-fill.
    setState(() => _lookingUp = true);
    final result = await Provider.of<CartProvider>(context, listen: false)
        .lookupProduct(code);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _name.text = result.displayName;
        _lookedUp = true;
      });
    }
    setState(() => _lookingUp = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final p = Product(
      id: widget.existing?.id,
      name: _name.text.trim(),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      priceCents: int.parse(_price.text.trim()),
      stockQty: int.parse(_stock.text.trim()),
    );
    await Provider.of<CartProvider>(context, listen: false).saveProduct(p);
    if (mounted) Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit product' : 'Add product'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'Name *',
                  suffixIcon: _lookingUp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              if (_lookedUp)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Auto-filled from barcode scan — set your price.',
                      style: TextStyle(fontSize: 12, color: Colors.green)),
                ),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                    labelText: 'Price (cents) *', hintText: 'e.g. 1990 = 19.90'),
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
              TextFormField(
                controller: _barcode,
                decoration: InputDecoration(
                  labelText: 'Barcode (optional)',
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _scan),
                ),
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
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save')),
      ],
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
