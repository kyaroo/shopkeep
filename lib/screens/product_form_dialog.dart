import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../theme.dart';
import '../utils/money.dart';
import 'scan_page.dart';

/// Add/edit product dialog.
///
/// Kept separate from the inventory list so each file has one responsibility:
/// this one owns the form, its catalog prefill and its scan flow.
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
