import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'scan_page.dart';
import 'browse_page.dart';
import '../widgets/stock_badge.dart';
/// Top-level entry used by the HomePage FAB. Opens the add/edit product form.
Future<void> showProductForm(BuildContext context, {Product? existing, String? initialBarcode, String? initialName}) async {
  final saved = await showDialog<Product>(
    context: context,
    builder: (_) => ProductFormDialog(existing: existing, initialBarcode: initialBarcode, initialName: initialName),
  );
  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(existing != null
              ? 'updated'.tr()
              : 'addedToInventory'.tr())),
    );
  }
}

/// Body of the Inventory tab (the single AppBar/FAB live in HomePage).
class InventoryBody extends StatefulWidget {
  const InventoryBody({super.key});

  @override
  State<InventoryBody> createState() => _InventoryBodyState();
}

class _InventoryBodyState extends State<InventoryBody> {
  final TextEditingController _search = TextEditingController();
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      Provider.of<CartProvider>(context, listen: false)
          .loadProducts(search: _search.text.trim());
    });
  }

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('deleteProduct'.tr()),
        content: Text('removeConfirm'.tr(namedArgs: {'name': p.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('delete'.tr(),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await Provider.of<CartProvider>(context, listen: false)
          .deleteProduct(p.id!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('deleted'.tr())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final allProducts = cart.products;
    final products = _lowStockOnly
        ? allProducts.where((p) => p.isLowStock).toList()
        : allProducts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'searchHint'.tr(),
              hintStyle: Theme.of(context)
                  .extension<AppTextStyles>()!
                  .label(context),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilterChip(
                label: Text('all'.tr(),
                    style: Theme.of(context)
                        .extension<AppTextStyles>()!
                        .label(context)),
                selected: !_lowStockOnly,
                onSelected: (_) => setState(() => _lowStockOnly = false),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  final selected = await Navigator.of(context).push<Map<String, dynamic>>(
                    MaterialPageRoute(
                      builder: (_) => BrowsePage(
                        localOnly: true,
                        onSelect: (m) {},
                      ),
                    ),
                  );
                  if (selected != null && context.mounted) {
                    showProductForm(
                      context,
                      initialBarcode: selected['barcode'] as String?,
                      initialName: selected['name'] as String?,
                    );
                  }
                },
                icon: const Icon(Icons.travel_explore, size: 18),
                label: const Text('Browse catalog'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text('lowStock'.tr(),
                    style: Theme.of(context)
                        .extension<AppTextStyles>()!
                        .label(context)),
                selected: _lowStockOnly,
                onSelected: (_) => setState(() => _lowStockOnly = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (allProducts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'inventorySummary'.tr(namedArgs: {
                  'count': '${allProducts.length}',
                  'low': '${allProducts.where((p) => p.isLowStock).length}',
                }),
                style: Theme.of(context)
                    .extension<AppTextStyles>()!
                    .meta(context),
              ),
            ),
          ),
        Expanded(
          child: cart.productsLoading
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
Icon(
                              _lowStockOnly
                                  ? Icons.check_circle_outline
                                  : Icons.inventory_2_outlined,
                              size: 48,
                              color: Theme.of(context)
                                  .extension<AppColors>()!
                                  .success
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text(
                            _lowStockOnly
                                ? 'inventoryOk'.tr()
                                : 'noProducts'.tr(),
                            textAlign: TextAlign.center,
                            style: _lowStockOnly
                                ? Theme.of(context)
                                    .extension<AppTextStyles>()!
                                    .name(context)
                                    .copyWith(color: Theme.of(context).extension<AppColors>()!.success)
                                : Theme.of(context)
                                    .extension<AppTextStyles>()!
                                    .name(context),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = products[i];
return ListTile(
  leading: StockBadge(
    isOutOfStock: p.isOutOfStock,
    isLowStock: p.isLowStock,
  ),
                          title: Text(p.name,
                              style: Theme.of(context)
                                  .extension<AppTextStyles>()!
                                  .name(context)),
                          subtitle: Text(
                              '${formatMoney(p.priceCents)}  •  ${'stockQty'.tr()}: ${p.stockQty}'
                              '${p.barcode != null ? '  •  ${p.barcode}' : ''}',
                              style: Theme.of(context)
                                  .extension<AppTextStyles>()!
                                  .meta(context)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'editProduct'.tr(),
                                onPressed: () =>
                                    showProductForm(context, existing: p),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'moreActions'.tr(),
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _confirmDelete(p);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('delete'.tr(),
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
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
    );
  }
}

class ProductFormDialog extends StatefulWidget {
  final Product? existing;
  final String? initialBarcode;
  final String? initialName;
  const ProductFormDialog({super.key, this.existing, this.initialBarcode, this.initialName});

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _threshold = TextEditingController();
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
      _price.text = formatDirhamsInput(p.priceCents);
      _stock.text = p.stockQty.toString();
      _threshold.text = p.lowStockThreshold.toString();
      _barcode.text = p.barcode ?? '';
    } else {
      if (widget.initialBarcode != null) _barcode.text = widget.initialBarcode!;
      if (widget.initialName != null) _name.text = widget.initialName!;
      if (_threshold.text.isEmpty) _threshold.text = '5';
      if (_stock.text.isEmpty) _stock.text = '0';
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (code == null || !mounted) return;
    setState(() => _barcode.text = code);

    final inInventory =
        Provider.of<CartProvider>(context, listen: false).products.any(
      (p) => p.barcode == code,
    );
    if (inInventory) return;

    setState(() => _lookingUp = true);
    // Local catalog first (zero data).
    try {
      final catalog = Provider.of<CatalogProvider>(context, listen: false);
      final entry = await catalog.get(code);
      if (entry != null && mounted) {
        setState(() {
          _name.text = entry.name;
          _lookedUp = true;
        });
        setState(() => _lookingUp = false);
        return;
      }
    } catch (_) {}
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
      priceCents: parseDirhamsToCents(_price.text.trim()),
      stockQty: int.tryParse(_stock.text.trim()) ?? 0,
      lowStockThreshold: int.tryParse(_threshold.text.trim()) ?? 5,
    );
    await Provider.of<CartProvider>(context, listen: false).saveProduct(p);
    if (mounted) Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null
          ? 'editProduct'.tr()
          : 'addProduct'.tr()),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '${'nameRequired'.tr()} *',
                  suffixIcon: _lookingUp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'nameRequired'.tr() : null,
              ),
              if (_lookedUp)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppPalette.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('autoFilledHint'.tr(),
                        style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.amberOnSurface)),
                  ),
                ),
              TextFormField(
                controller: _price,
                decoration: InputDecoration(
                    labelText: '${'yourPrice'.tr()} *',
                    hintText: 'priceHintDirhams'.tr()),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  try {
                    parseDirhamsToCents(v ?? '');
                    return null;
                  } on FormatException {
                    return 'nameRequired'.tr();
                  }
                },
              ),
              TextFormField(
                controller: _stock,
                decoration: InputDecoration(labelText: '${'stockQty'.tr()} *'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 ? 'nameRequired'.tr() : null;
                },
              ),
              TextFormField(
                controller: _threshold,
                decoration: InputDecoration(
                  labelText: 'lowStockThreshold'.tr(),
                  hintText: 'lowStockThresholdHint'.tr(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 ? 'nameRequired'.tr() : null;
                },
              ),
              TextFormField(
                controller: _barcode,
                decoration: InputDecoration(
                  labelText: 'barcodeOptional'.tr(),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.camera_alt), onPressed: _scan),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('deleteProduct'.tr()),
                  content: Text('removeConfirm'.tr(namedArgs: {'name': widget.existing!.name})),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text('cancel'.tr())),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('delete'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                ),
              );
              if (ok == true && mounted) {
                await Provider.of<CartProvider>(context, listen: false).deleteProduct(widget.existing!.id!);
                if (mounted) Navigator.pop(context);
              }
            },
            child: Text('delete'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr())),
        TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('save'.tr())),
      ],
    );
  }
}

