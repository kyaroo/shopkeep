import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/product.dart';
import '../models/catalog_prefill.dart';
import '../providers/cart_provider.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'browse_page.dart';
import 'product_form_dialog.dart';
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
                      separatorBuilder: (_, _) => const Divider(height: 1),
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
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      cacheWidth: 132),
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
