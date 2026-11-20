import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../data/settings_service.dart';
import '../services/shop_export_service.dart';
import '../data/shop_provisioning_service.dart';
import '../data/import_export.dart';
import '../screens/shop_entry_screen.dart';
import '../app_state.dart';
import '../utils/slug.dart';
import '../build_config.dart';
import '../services/attribution_service.dart';
import '../theme.dart';

/// Plain `yyyy-MM-dd HH:mm` — deliberately locale-independent, so the trail is
/// unambiguous whatever the app language is (and so `intl` date initialization
/// is not required on this screen).
String _formatTimestamp(int epochMs) {
  if (epochMs <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Settings screen: business name, shop management, export/import.
class SettingsScreen extends StatefulWidget {
  final String shopKey;

  /// When true, render only the scrollable body (no [Scaffold]/AppBar) so the
  /// admin Settings tab can host it directly.
  final bool embedded;

  const SettingsScreen({super.key, required this.shopKey, this.embedded = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _settings => context.read<SettingsService>();

  late TextEditingController _nameController;
  final _shopNameController = TextEditingController();
  final _shopKeyController = TextEditingController();

  List<String> _shopKeys = [];
  String _currentShopKey = '';
  bool _loadingShops = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadBusinessName();
    _loadShops();
    String lastAutoKey = '';
    _shopKeyController.addListener(() {});
    _shopNameController.addListener(() {
      final auto = slugify(_shopNameController.text);
      if (_shopKeyController.text.isEmpty || _shopKeyController.text == lastAutoKey) {
        _shopKeyController.text = auto;
        lastAutoKey = auto;
      }
    });
    _shopKeyController.addListener(() {
      if (_shopKeyController.text != lastAutoKey) lastAutoKey = '';
    });
  }

  Future<void> _loadBusinessName() async {
    final name = await _settings.getBusinessName();
    if (mounted) _nameController.text = name;
  }

  Future<void> _loadShops() async {
    final list = await _settings.getShopList();
    final current = await _settings.getCurrentShopKey();
    if (mounted) {
      setState(() {
        _shopKeys = list;
        _currentShopKey = current;
        _loadingShops = false;
      });
    }
  }

  Future<void> _saveBusinessName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await _settings.saveBusinessName(name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('businessNameSaved'.tr())),
      );
    }
  }

  Future<void> _addShop() async {
    final name = _shopNameController.text.trim();
    if (name.isEmpty) return;
    final keyInput = _shopKeyController.text.trim();
    try {
      await ShopProvisioningService.createShop(
        name: name,
        key: keyInput.isEmpty ? null : keyInput,
        registerOnServer: false,
        settings: _settings,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('shopCreated'.tr())),
        );
        _shopNameController.clear();
        _shopKeyController.clear();
        _loadShops();
      }
    } catch (e) {
      if (mounted) {
        final msg = e is DuplicateShopKeyException
            ? 'shopKeyDuplicate'.tr()
            : 'shopKeyRequired'.tr();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  Future<void> _useShop(String key) async {
    final appState = context.read<AppState>();
    await _settings.setCurrentShopKey(key);
    final name = await _settings.getBusinessName();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('shopSelected'.tr(namedArgs: {'key': key}))),
      );
      Navigator.of(context).pop();
    }
    appState.shopKey = key;
    appState.businessName = name;
  }

  Future<void> _confirmDeleteShop(String key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('deleteShop'.tr()),
        content: Text('deleteShopConfirm'.tr(namedArgs: {'key': key})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _settings.removeShop(key);
    if (mounted) {
      _loadShops();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('shopDeleted'.tr())),
      );
    }
  }

  /// Writes [json] to a temp file and hands it to the system share sheet.
  ///
  /// One path for all three exports: the old code built the JSON, then wrote a
  /// hard-coded *empty* [Catalog] to the file and shared that, so the real
  /// payload was discarded and the `Share.share(json)` fallback was
  /// unreachable (`writeCatalog` always creates the file).
  Future<void> _shareJson(String format, String shopKey, String json) async {
    try {
      final temp = Directory.systemTemp.createTempSync('myhanout_');
      final name = ShopExportService.fileName(format, shopKey);
      final file = File('${temp.path}/$name');
      await file.writeAsString(json);
      await Share.shareXFiles([XFile(file.path)], subject: name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('exported'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'exportFailed'.tr()} $e')),
        );
      }
    }
  }

  /// Shop-bound data has no meaning on a fresh admin install (no shop yet).
  /// Show an explicit state instead of opening an empty shop DB.
  void _noShop() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No shop selected — choose a shop first')),
    );
  }

  /// The shop's own price/stock listing. Available in both flavors.
  Future<void> _exportListing() async {
    if (widget.shopKey.isEmpty) {
      _noShop();
      return;
    }
    await _shareJson(
      ShopExportService.listingFormat,
      widget.shopKey,
      await ShopExportService.listingJson(widget.shopKey),
    );
  }

  /// The shop's own sales history. Available in both flavors.
  Future<void> _exportHistory() async {
    if (widget.shopKey.isEmpty) {
      _noShop();
      return;
    }
    await _shareJson(
      ShopExportService.historyFormat,
      widget.shopKey,
      await ShopExportService.historyJson(widget.shopKey),
    );
  }

  /// The universal catalog. **Admin only** — see the `kIsAdmin` guard on the
  /// menu entry. Metadata only, never photos.
  Future<void> _exportCatalog() async {
    await _shareJson(
      ShopExportService.catalogFormat,
      widget.shopKey,
      await ShopExportService.catalogJson(),
    );
  }

  Future<void> _importCatalog() async {
    if (widget.shopKey.isEmpty) {
      _noShop();
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    try {
      final json = await File(path).readAsString();
      await importCatalogJson(widget.shopKey, json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('imported'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'importFailed'.tr()} $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shopNameController.dispose();
    _shopKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
          // Installed catalog generation. Read-only, no network: the value
          // advances when a `.myhanout` delta is applied on this device.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('catalogVersionLabel'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  FutureBuilder<int>(
                    future: _settings.getCatalogVersion(),
                    builder: (context, snap) => Text(
                      '${snap.data ?? 0}',
                      style: Theme.of(context)
                          .extension<AppTextStyles>()!
                          .name(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Attribution: who pushed which catalog generation, and who changed a
          // price or stock level. Read-only, from local tables.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('attribution'.tr(),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (widget.shopKey.isEmpty)
                    const Text('No shop selected')
                  else
                    FutureBuilder<List<AttributionEntry>>(
                      future: AttributionService.recent(shopKey: widget.shopKey),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final entries = snap.data!;
                      if (entries.isEmpty) {
                        return Text('attributionEmpty'.tr());
                      }
                      return Column(
                        children: [
                          for (final e in entries)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                e.kind == 'catalog'
                                    ? Icons.inventory_2_outlined
                                    : Icons.sell_outlined,
                              ),
                              title: Text(e.actor.isEmpty
                                  ? 'attributionUnknown'.tr()
                                  : e.actor),
                              subtitle: Text(
                                '${e.kind == 'catalog' ? 'attributionCatalog'.tr() : 'attributionListing'.tr()} · ${e.detail}',
                              ),
                              trailing: Text(_formatTimestamp(e.at)),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('businessName'.tr(),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  // Provisioning data: on the shopkeeper flavor the name was
                  // recorded by the salesman in the signed QR, so there is no
                  // editing affordance at all — only the stored value. The
                  // branch is compile-time, so the editing widgets are stripped
                  // from the shopkeeper build and `_saveBusinessName` is
                  // unreachable from its UI.
                  if (kIsAdmin) ...[
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'businessName'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _saveBusinessName,
                      child: Text('save'.tr()),
                    ),
                  ] else
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _nameController,
                      builder: (context, value, _) => Text(
                        value.text,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (kIsAdmin) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('shopManagement'.tr(),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _shopNameController,
                    decoration: InputDecoration(
                      labelText: 'businessName'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _shopKeyController,
                    decoration: InputDecoration(
                      labelText: 'shopKey'.tr(),
                      border: const OutlineInputBorder(),
                      helperText: 'autoGenerated'.tr(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _addShop,
                    child: Text('createShop'.tr()),
                  ),
                  const Divider(height: 24),
                  if (_loadingShops)
                    const Center(child: CircularProgressIndicator())
                  else if (_shopKeys.isEmpty)
                    Text('noShopsFound'.tr())
                  else
                    ..._shopKeys.map((key) {
                      final isCurrent = key == _currentShopKey;
                      return ListTile(
                        title: Text(key),
                        subtitle: Text(isCurrent ? 'currentShop'.tr() : '${'shopKey'.tr()}: $key'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'use') _useShop(key);
                            if (v == 'delete') _confirmDeleteShop(key);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem<String>(value: 'use', child: Text('useShop'.tr())),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('delete'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ),
                          ],
                        ),
                      );
                    }),
                  const Divider(height: 24),
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: Text('joinShop'.tr()),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ShopEntryScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('backup'.tr(), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  // The listing and the history are the SHOPKEEPER's own data:
                  // they live in the per-shop DB on that device, so the admin
                  // flavor cannot produce them and says so instead.
                  if (kIsAdmin)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Listing and history exports live on the shopkeeper app.',
                      ),
                    )
                  else ...[
                    if (widget.shopKey.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No shop selected — shop-bound exports are unavailable',
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.list_alt),
                      title: Text('exportListing'.tr()),
                      onTap: _exportListing,
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text('exportHistory'.tr()),
                      onTap: _exportHistory,
                    ),
                  ],
                  // The catalog is UNIVERSAL — the admin's artifact, never the
                  // shopkeeper's. This guard is the whole point: an earlier
                  // version of this card sat outside the kIsAdmin spread and
                  // rendered the catalog action in both flavors.
                  if (kIsAdmin)
                    ListTile(
                      leading: const Icon(Icons.inventory_2),
                      title: Text('exportCatalog'.tr()),
                      onTap: _exportCatalog,
                    ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: Text('restoreBackup'.tr()),
                    onTap: _importCatalog,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr())),
      body: body,
    );
  }
}
