import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../data/catalog_sync_client.dart';
import '../data/settings_service.dart';
import '../data/shop_provisioning_service.dart';
import '../data/provisioning.dart';
import '../utils/slug.dart';
import '../utils/app_log.dart';
import '../utils/shop_l10n.dart';
import '../data/sync_config.dart';
import 'listing_push_screen.dart';
import 'shop_entry_screen.dart';
import 'shop_info_screen.dart';
import '../services/shop_export_service.dart';

/// Admin setup screen: create / manage shops.
///
/// This is a separate app entry point in the admin APK. It never shows
/// checkout, inventory, or sales — only shop management.
class AdminSetupScreen extends StatefulWidget {
  /// When true this is a section inside the admin home shell, not an app root.
  final bool embedded;

  /// Trust root for the pushed Shop-info / listing screens. Production leaves
  /// this null (baked root); tests inject a throwaway root.
  final List<int>? rootPublicKey;

  /// Sync-client factory for server registration. Defaults to
  /// [SyncConfig.defaultClient]; tests inject a fake.
  final CatalogSyncClientFactory? clientFactory;

  const AdminSetupScreen({
    super.key,
    this.embedded = false,
    this.rootPublicKey,
    this.clientFactory,
  });

  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  SettingsService get _settings => context.read<SettingsService>();

  final _nameController = TextEditingController();
  final _shopKeyController = TextEditingController();

  // Optional contact fields. Empty is fine and never blocks creation; they are
  // forwarded to the server registration when present.
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();

  List<String> _shopKeys = [];
  bool _loading = true;

  /// Last created shop + its registration outcome, surfaced as an explicit
  /// state (the local shop stays usable either way).
  String? _createdKey;
  bool _createdRegistered = false;

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

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
    final list = await _settings.getShopList();
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
      final result = await ShopProvisioningService.createShop(
        name: name,
        key: requestedKey.isEmpty ? null : requestedKey,
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        phone: _phoneController.text.trim(),
        settings: _settings,
        clientFactory: widget.clientFactory,
      );
      if (mounted) {
        setState(() {
          _createdKey = result.shopKey;
          _createdRegistered = result.registered;
        });
        _showProvisioningQr(result.shopKey, name);
        _nameController.clear();
        _shopKeyController.clear();
        _addressController.clear();
        _cityController.clear();
        _ownerNameController.clear();
        _phoneController.clear();
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

  @override
  void dispose() {
    _nameController.dispose();
    _shopKeyController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Writes an export artifact to a temp file and hands it to the share sheet.
  /// The shop's own listing / history are per-shop rows; the admin device has
  /// the shop DB only for shops it created here.
  Future<void> _shareExport(
      String format, String shopKey, Future<String> Function() build) async {
    try {
      await ShopExportService.shareJson(format, shopKey, await build());
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

  Future<void> _exportHistory(String key) => _shareExport(
        ShopExportService.historyFormat,
        key,
        () => ShopExportService.historyJson(key),
      );

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
                final client =
                    await (widget.clientFactory ?? SyncConfig.defaultClient)();
                await client.deleteShop(key);
                client.close();
              } catch (e) {
                logWarning('server shop deletion failed (local copy removed)',
                    error: e);
              }
              await _settings.removeShop(key);
              await _settings.removeShopBusinessName(key);
              if (mounted) Navigator.pop(context);
              _loadShops();
            },
            child: Text('delete'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  /// Explicit registration outcome for the shop just created. The local shop
  /// is usable either way; this only tells the admin whether the server knows
  /// about it.
  Widget _registrationStateCard(String key, bool registered) {
    final scheme = Theme.of(context).colorScheme;
    final body = registered
        ? shopInfoTr(context, 'shopCreatedRegistered', namedArgs: {'key': key})
        : shopInfoTr(context, 'shopCreatedNotRegistered',
            namedArgs: {'key': key});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              registered ? Icons.check_circle : Icons.cloud_off,
              color: registered ? scheme.primary : scheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopInfoTr(context,
                        registered ? 'shopRegistered' : 'shopNotRegistered'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 8),
                        // Optional contact fields. Empty is fine: they are
                        // forwarded to the server registration when present and
                        // stay editable later on the shop-info screen.
                        TextField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText: shopInfoTr(context, 'shopInfoAddress'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _cityController,
                          decoration: InputDecoration(
                            labelText: shopInfoTr(context, 'shopInfoCity'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ownerNameController,
                          decoration: InputDecoration(
                            labelText: shopInfoTr(context, 'shopInfoOwnerName'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: shopInfoTr(context, 'shopInfoPhone'),
                            border: const OutlineInputBorder(),
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
                if (_createdKey != null) ...[
                  const SizedBox(height: 16),
                  _registrationStateCard(_createdKey!, _createdRegistered),
                ],
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
                              subtitle: Text('${'shopKey'.tr()}: $key'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.qr_code),
                                    tooltip: 'showQr'.tr(),
                                    onPressed: () async {
                                      final name = await _settings.getShopBusinessName(key) ?? key;
                                      if (!mounted) return;
                                      _showProvisioningQr(
                                        key,
                                        name,
                                      );
                                    },
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'info') {
                                        await _push(
                                            ShopInfoScreen(shopKey: key));
                                        // The name / contact fields may have
                                        // changed on the server.
                                        _loadShops();
                                      }
                                      if (v == 'listing') {
                                        await _push(ListingPushScreen(
                                          shopKey: key,
                                          rootPublicKey: widget.rootPublicKey,
                                        ));
                                      }
                                      if (v == 'history') await _exportHistory(key);
                                      if (v == 'delete') _confirmDelete(key);
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem<String>(
                                        value: 'info',
                                        child: Text(shopInfoTr(
                                            context, 'shopInfo')),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'listing',
                                        child: Text(shopInfoTr(
                                            context, 'shopMenuExportListing')),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'history',
                                        child: Text(shopInfoTr(
                                            context, 'shopMenuExportHistory')),
                                      ),
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
                          }),
                      ],
                    ),
                  ),
                ),
                // Catalog / distribution tools live in the AdminHome Catalog
                // tab only (decisions 2a, 3a, 4b). No duplicate card here.
                if (widget.embedded) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.login),
                      title: Text('joinShop'.tr()),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ShopEntryScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text('adminSetup'.tr())),
      body: body,
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
  String? _token;
  String? _error;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  Future<void> _regenerate() async {
    const store = ConfigSettingsService();
    final signerId = await store.getActiveSignerId();
    final seed = signerId == null ? null : await store.getSignerKey(signerId);
    if (!mounted) return;
    if (signerId == null || seed == null) {
      setState(() => _error = 'no signer key on this device');
      return;
    }
    final token = await ShopProvisioningService.buildProvisioningToken(
      widget.shopKey,
      widget.businessName,
      signerId: signerId,
      privateSeed: seed,
      ttlSeconds: _ttlSeconds,
    );
    if (mounted) setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    // Re-signed on every TTL change: the QR is only ever shown, never persisted.
    final token = _token;
    return AlertDialog(
      title: Text('shopCreated'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (token != null)
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
              if (v != null) {
                setState(() => _ttlSeconds = v);
                _regenerate();
              }
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
