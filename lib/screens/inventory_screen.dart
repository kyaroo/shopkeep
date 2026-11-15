import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/product.dart';
import '../models/catalog_prefill.dart';
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
  final ScrollController _scroll = ScrollController();
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      Provider.of<CartProvider>(context, listen: false)
          .loadProducts(search: _search.text.trim());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
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
    // Paged: the list renders what is loaded; scrolling near the end fetches
    // the next page. The summary reports the real total. Deferred to after the
    // frame — notifying listeners during build would throw.
    if (_scroll.hasClients &&
        _scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 200) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cart.loadMoreProducts();
      });
    }
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
                  final selected = await Navigator.of(context).push<CatalogPrefill>(
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
                      initialBarcode: selected.barcode,
                      initialName: selected.name,
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
                  'count': '${cart.totalProducts}',
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
                      controller: _scroll,
                      itemCount:
                          products.length + (cart.loadingMoreProducts ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        if (i >= products.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child:
                                Center(child: CircularProgressIndicator()),
                          );
                        }
                        final p = products[i];
return ListTile(
  leading: p.photo != null
      ? ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(p.photo!,
              width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 132),
        )
      : StockBadge(
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

  /// True only when the barcode was resolved from the LOCAL catalog. Distinguishes
  /// a catalog product from one typed by hand (CAT3b) — the admin's OFF lookup
  /// sets [_lookedUp] but not this, because it is not our catalog.
  bool _fromCatalog = false;
  Uint8List? _photo;

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
      _photo = p.photo;
    } else {
      if (widget.initialBarcode != null) _barcode.text = widget.initialBarcode!;
      if (widget.initialName != null) _name.text = widget.initialName!;
      if (_threshold.text.isEmpty) _threshold.text = '5';
      if (_stock.text.isEmpty) _stock.text = '0';
    }
    // Opened from a catalog row / scan with a barcode: resolve name + photo
    // from the LOCAL catalog (offline, zero data).
    if (widget.existing == null && widget.initialBarcode != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resolveFromCatalog(widget.initialBarcode!),
      );
    }
  }

  /// Local-catalog lookup by barcode. Returns true when the catalog had it
  /// (name + photo applied). Never touches the network.
  Future<bool> _resolveFromCatalog(String code) async {
    try {
      final catalog = Provider.of<CatalogProvider>(context, listen: false);
      final entry = await catalog.get(code);
      if (entry != null && mounted) {
        setState(() {
          if (_name.text.trim().isEmpty) _name.text = entry.name;
          _photo = entry.photo;
          _lookedUp = true;
          _fromCatalog = true;
        });
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (code == null || !mounted) return;
    setState(() => _barcode.text = code);

    // Database-backed: the inventory list is paged, so the in-memory list is
    // only the loaded window.
    final existing = await Provider.of<CartProvider>(context, listen: false)
        .findByBarcode(code);
    if (existing != null) return;

    setState(() => _lookingUp = true);
    // Local catalog first (zero data).
    final resolved = await _resolveFromCatalog(code);
    if (!mounted) return;
    if (resolved) {
      setState(() => _lookingUp = false);
      return;
    }
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
    final barcode = _barcode.text.trim();
    final p = Product(
      id: widget.existing?.id,
      name: _name.text.trim(),
      barcode: barcode.isEmpty ? null : barcode,
      priceCents: parseDirhamsToCents(_price.text.trim()),
      stockQty: int.tryParse(_stock.text.trim()) ?? 0,
      lowStockThreshold: int.tryParse(_threshold.text.trim()) ?? 5,
      photo: _photo,
      // Editing keeps the row's provenance; a new row is 'catalog' only when
      // the barcode was resolved locally, otherwise it is a local addition.
      source: widget.existing?.source ??
          ((_fromCatalog && barcode.isNotEmpty) ? 'catalog' : 'local'),
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
              if (_photo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _photo!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        cacheWidth: 216,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 40),
                      ),
                    ),
                  ),
                ),
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

