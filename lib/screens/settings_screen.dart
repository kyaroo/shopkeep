import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../data/config.dart';
import '../data/import_export.dart';
import '../screens/shop_entry_screen.dart';
import '../theme.dart';

/// Settings screen: business name, export/import, close shop.
class SettingsScreen extends StatefulWidget {
  final String shopKey;
  const SettingsScreen({super.key, required this.shopKey});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: Config.getBusinessName().toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveBusinessName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await Config.saveBusinessName(name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('businessNameSaved'.tr())),
      );
    }
  }

  Future<void> _exportCatalog() async {
    try {
      final json = await catalogToJson(widget.shopKey);
      // Write to a temp file and share via share_plus
      final temp = Directory.systemTemp.createTempSync('myhanout_');
      final file = File('${temp.path}/catalog_${widget.shopKey}.json');
      writeCatalog(
        Catalog(
          version: 1,
          exportedAt: DateTime.now().millisecondsSinceEpoch,
          shopKey: widget.shopKey,
          products: [],
          sales: [],
          saleItems: [],
          auditLog: [],
        ),
        file,
      );
      if (!await file.exists()) {
        // Fallback: just share the JSON string
        await Share.share(json);
      } else {
        await Share.shareXFiles([XFile(file.path)]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('exported'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('exportFailed' + ' ' + e.toString())),
        );
      }
    }
  }

  Future<void> _importCatalog() async {
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
          SnackBar(content: Text('importFailed' + ' ' + e.toString())),
        );
      }
    }
  }

  Future<void> _deleteShop() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('deleteShop'.tr()),
        content: Text('deleteShopConfirm'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () {
              Config.removeShop(widget.shopKey);
              if (mounted) Navigator.pop(context);
            },
            child: Text('delete'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('businessName'.tr(),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
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
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('backup'.tr(), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.share),
                    title: Text('exportCatalog'.tr()),
                    onTap: _exportCatalog,
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: Text('importCatalog'.tr()),
                    onTap: _importCatalog,
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('shop'.tr(), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: Text('joinShop'.tr()),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ShopEntryScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete),
                    title: Text('deleteShop'.tr()),
                    onTap: _deleteShop,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
