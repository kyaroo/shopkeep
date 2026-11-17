import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/product.dart';
import '../models/inventory_filter.dart';
import '../models/catalog_prefill.dart';
import '../providers/cart_provider.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'browse_page.dart';
import 'product_form_dialog.dart';
import '../widgets/stock_badge.dart';
import '../widgets/inventory_thumb.dart';

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
  InventoryFilter _filter = InventoryFilter.all;

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

  /// G2 — recovery affordance for a LOCAL addition.
  ///
  /// A row the shopkeeper typed by hand has no catalog counterpart to fall
  /// back to, so deleting it is the undo: it removes exactly what the local
  /// add created. Catalog rows keep the generic edit/delete actions and never
  /// see this affordance.
  Future<void> _confirmUndoLocal(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('undoLocalAdd'.tr()),
        content: Text('undoLocalConfirm'.tr(namedArgs: {'name': p.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr())),
          // 'undo' and 'cancel' are both "Annuler" in French; the confirm
          // action really is a delete, so label it with the delete key.
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('delete'.tr(),
                  style: TextStyle(
                      color:
                          Theme.of(context).extension<AppColors>()!.warning))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await Provider.of<CartProvider>(context, listen: false)
          .deleteProduct(p.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('localAddUndone'.tr())));
      }
    }
  }

  /// The selected view is low stock (empty state says "inventory OK").
  bool get _isLowStockView => _filter == InventoryFilter.lowStock;

  /// The selected view is local additions (empty state explains what that is).
  bool get _isLocalView => _filter == InventoryFilter.local;

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final allProducts = cart.products;
    final products = _filter.apply(allProducts);
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
          // Wrap, not Row: three chips + the browse action overflow a phone
          // width, and a silently clipped filter chip is worse than a second
          // line.
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text('all'.tr(),
                    style: Theme.of(context)
                        .extension<AppTextStyles>()!
                        .label(context)),
                selected: _filter == InventoryFilter.all,
                onSelected: (_) =>
                    setState(() => _filter = InventoryFilter.all),
              ),
              FilterChip(
                label: Text('lowStock'.tr(),
                    style: Theme.of(context)
                        .extension<AppTextStyles>()!
                        .label(context)),
                selected: _filter == InventoryFilter.lowStock,
                onSelected: (_) =>
                    setState(() => _filter = InventoryFilter.lowStock),
              ),
              FilterChip(
                label: Text('localOnly'.tr(),
                    style: Theme.of(context)
                        .extension<AppTextStyles>()!
                        .label(context)),
                selected: _filter == InventoryFilter.local,
                onSelected: (_) =>
                    setState(() => _filter = InventoryFilter.local),
              ),
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
                              _isLowStockView
                                  ? Icons.check_circle_outline
                                  : Icons.inventory_2_outlined,
                              size: 48,
                              color: Theme.of(context)
                                  .extension<AppColors>()!
                                  .success
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text(
                            _isLowStockView
                                ? 'inventoryOk'.tr()
                                : _isLocalView
                                    ? 'noLocalProducts'.tr()
                                    : 'noProducts'.tr(),
                            textAlign: TextAlign.center,
                            style: _isLowStockView
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
                          // Fixed 44x44 whether or not a photo exists: an
                          // intrinsically-sized leading widget would reserve
                          // its own width and squeeze the name's column.
                          leading: InventoryThumb(photo: p.photo),
                          title: Text(p.name,
                              style: Theme.of(context)
                                  .extension<AppTextStyles>()!
                                  .name(context)),
                          subtitle: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${formatMoney(p.priceCents)} • ${'stockQty'.tr()}: ${p.stockQty}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .extension<AppTextStyles>()!
                                      .meta(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Stock status lives here rather than in the
                              // leading slot so it can never cost the name any
                              // width. Icon-only: a text pill measured 85px
                              // ("En stock") and wrapped this line, which had
                              // only 199px for text + badge together.
                              StockBadge(
                                isOutOfStock: p.isOutOfStock,
                                isLowStock: p.isLowStock,
                                showLabel: false,
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // G2 recovery: local-only, warning-tinted undo
                              // icon, distinct from the neutral edit and the
                              // destructive overflow delete.
                              if (p.isLocal)
                                IconButton(
                                  icon: const Icon(Icons.undo),
                                  tooltip: 'undoLocalAdd'.tr(),
                                  color: Theme.of(context)
                                      .extension<AppColors>()!
                                      .warning,
                                  onPressed: () => _confirmUndoLocal(p),
                                ),
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
