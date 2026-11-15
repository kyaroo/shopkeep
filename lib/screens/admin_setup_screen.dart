import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../build_config.dart';
import '../data/config.dart';
import '../data/shop_provisioning_service.dart';
import '../utils/slug.dart';
import '../data/provisioning.dart';
import '../data/sync_config.dart';
import '../providers/catalog_provider.dart';
import '../data/catalog_sync_client.dart';
import 'catalog_home_page.dart';
import 'catalog_push_screen.dart';

/// Admin setup screen: create / manage shops.
///
/// This is a separate app entry point in the admin APK. It never shows
/// checkout, inventory, or sales — only shop management.
class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({super.key});

  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  final _nameController = TextEditingController();
  final _shopKeyController = TextEditingController();
  List<String> _shopKeys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadShops();
    String lastAutoKey = '';
    _shopKeyController.addListener(() {});
    _nameController.addListener(() {
      final auto = slugify(_nameController.text);
      if (auto.isEmpty) return;
      if (_shopKeyController.text.isEmpty || _shopKeyController.text == lastAutoKey) {
        _shopKeyController.text = auto;
        lastAutoKey = auto;
      }
    });
    _shopKeyController.addListener(() {
      if (_shopKeyController.text != lastAutoKey) lastAutoKey = '';
    });
  }

  Future<void> _loadShops() async {
    final list = await Config.getShopList();
    if (mounted) {
      setState(() {
        _shopKeys = list;
        _loading = false;
      });
    }
  }

  Future<void> _addShop() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final requestedKey = _shopKeyController.text.trim();
    try {
      final key = await ShopProvisioningService.createShop(
        name: name,
        key: requestedKey.isEmpty ? null : requestedKey,
      );
      if (mounted) {
        _showProvisioningQr(key, name);
        _nameController.clear();
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

  void _showProvisioningQr(String shopKey, String businessName) {
    showDialog(
      context: context,
      builder: (_) => ProvisioningQrDialog(
        shopKey: shopKey,
        businessName: businessName,
      ),
    );
  }

  void _confirmDelete(String key) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('deleteShop'.tr()),
        content: Text('deleteShopConfirm'.tr(namedArgs: {'key': key})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () async {
              // Best-effort server deletion.
              try {
                final client = await SyncConfig.defaultClient();
                await client.deleteShop(key);
                client.close();
              } catch (_) {}
              await Config.removeShop(key);
              await Config.removeShopBusinessName(key);
              if (mounted) Navigator.pop(context);
              _loadShops();
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
      appBar: AppBar(title: Text('adminSetup'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('addShop'.tr(),
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameController,
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('shopsList'.tr(),
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        if (_shopKeys.isEmpty)
                          Text('noShopsFound'.tr())
                        else
                          ..._shopKeys.map((key) {
                            return ListTile(
                              title: Text(key),
                              subtitle: Text('shopKey'.tr() + ': ' + key),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.qr_code),
                                    tooltip: 'showQr'.tr(),
                                    onPressed: () async {
                                      final name = await Config.getShopBusinessName(key) ?? key;
                                      if (!mounted) return;
                                      _showProvisioningQr(
                                        key,
                                        name,
                                      );
                                    },
                                  ),
                                  PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'delete') _confirmDelete(key);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('delete'.tr(),
                                        style: TextStyle(
                                            color: Theme.of(context).colorScheme.error)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                          }),
                      ],
                    ),
                  ),
                ),
                if (kIsAdmin) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Catalog (founder)',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChangeNotifierProvider(
                                    create: (_) => CatalogProvider()..init(),
                                    child: const CatalogHomePage(),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Open Catalog'),
                          ),
                          const SizedBox(height: 8),
                          // Distribution du catalogue: build a signed `.myhanout`
                          // delta and hand it to one shop (WhatsApp / share).
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CatalogPushScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('Distribute catalog'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Provisioning QR for one shop, with a TTL selector (B4).
///
/// The chosen lifetime is signed INTO the token (`ttl_seconds`), so the shop's
/// phone decides how long the code stays valid — no server round-trip, and the
/// admin can hand the same shop a short code today and a long one later.
class ProvisioningQrDialog extends StatefulWidget {
  final String shopKey;
  final String businessName;

  const ProvisioningQrDialog({
    super.key,
    required this.shopKey,
    required this.businessName,
  });

  @override
  State<ProvisioningQrDialog> createState() => _ProvisioningQrDialogState();
}

class _ProvisioningQrDialogState extends State<ProvisioningQrDialog> {
  int _ttlSeconds = defaultProvisioningTtlSeconds;

  @override
  Widget build(BuildContext context) {
    // Re-signed on every TTL change: the QR is only ever shown, never persisted.
    final token = ShopProvisioningService.buildProvisioningToken(
      widget.shopKey,
      widget.businessName,
      ttlSeconds: _ttlSeconds,
    );
    return AlertDialog(
      title: Text('shopCreated'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(data: token, size: 200),
          const SizedBox(height: 8),
          SelectableText(widget.shopKey,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(widget.businessName),
          const SizedBox(height: 12),
          // Label + dropdown: the value lives in the token, not in a setting.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('provisioningTtlLabel'.tr(),
                style: Theme.of(context).textTheme.bodySmall),
          ),
          DropdownButton<int>(
            value: _ttlSeconds,
            isExpanded: true,
            onChanged: (v) {
              if (v != null) setState(() => _ttlSeconds = v);
            },
            items: provisioningTtlChoices.entries
                .map((e) => DropdownMenuItem<int>(
                      value: e.key,
                      child: Text(e.value.tr()),
                    ))
                .toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('close'.tr())),
      ],
    );
  }
}
