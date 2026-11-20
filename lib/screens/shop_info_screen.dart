import 'package:flutter/material.dart';

import '../data/catalog_sync_client.dart';
import '../data/sync_config.dart';
import '../services/shop_info_client.dart';
import '../utils/shop_l10n.dart';

/// Per-shop info screen.
///
/// The four contact fields are editable for BOTH roles. The business name is
/// editable only for an `owner` token — the role comes from the server
/// (`GET /v1/sync/status`), and while it is unknown the field is read-only
/// (fail closed). The server still enforces the same rule on PATCH.
class ShopInfoScreen extends StatefulWidget {
  final String shopKey;

  /// Injectable so tests never touch SharedPreferences or real HTTP.
  final ShopInfoClientFactory? clientFactory;

  /// Supplies the token whose role decides business-name editability. Defaults
  /// to [SyncConfig.defaultClient]; tests inject a fake.
  final CatalogSyncClientFactory? syncClientFactory;

  const ShopInfoScreen({
    super.key,
    this.shopKey = '',
    this.clientFactory,
    this.syncClientFactory,
  });

  @override
  State<ShopInfoScreen> createState() => _ShopInfoScreenState();
}

class _ShopInfoScreenState extends State<ShopInfoScreen> {
  late final TextEditingController _keyController;
  final _businessName = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();

  ShopInfoClient? _client;
  ShopInfo? _info;

  /// Server-reported token role. `null` while unknown → business name is
  /// read-only (never optimistically editable).
  String? _role;
  bool get _canEditBusinessName => _role == 'owner';

  bool _loading = false;
  String? _error;

  ShopInfoClientFactory get _factory =>
      widget.clientFactory ??
      () async => ShopInfoClient.fromConfig(await SyncConfig.load());

  CatalogSyncClientFactory get _syncFactory =>
      widget.syncClientFactory ?? SyncConfig.defaultClient;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.shopKey);
    if (widget.shopKey.trim().isNotEmpty) _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _businessName.dispose();
    _address.dispose();
    _city.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _client?.close();
    super.dispose();
  }

  String _message(ShopInfoException e) {
    final detail = e.message;
    if (e is ShopInfoNotFoundException) {
      return shopInfoTr(context, 'shopInfoNotFound',
          namedArgs: {'key': _keyController.text.trim()});
    }
    if (e is ShopInfoForbiddenException) {
      final key = e.statusCode == 401 ? 'shopInfoAuthFailed' : 'shopInfoForbidden';
      return shopInfoTr(context, key,
          namedArgs: {'status': '${e.statusCode ?? ''}', 'detail': detail});
    }
    if (e is ShopInfoBadRequestException) {
      return shopInfoTr(context, 'shopInfoBadRequest',
          namedArgs: {'detail': detail});
    }
    if (e is ShopInfoConflictException) {
      return shopInfoTr(context, 'shopInfoConflict',
          namedArgs: {'detail': detail});
    }
    return shopInfoTr(context, 'shopInfoLoadFailed',
        namedArgs: {'detail': detail});
  }

  Future<void> _load() async {
    final shopKey = _keyController.text.trim();
    if (shopKey.isEmpty) {
      if (mounted) {
        setState(() => _error = shopInfoTr(context, 'shopInfoShopKey'));
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      // An injected client is trusted (tests/dependency injection); only the
      // default path needs the persisted URL + token to be configured.
      if (widget.clientFactory == null && !(await SyncConfig.load()).isConfigured) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = shopInfoTr(context, 'shopInfoNotConfigured');
        });
        return;
      }
      final client = await _factory();
      _client?.close();
      _client = client;
      final info = await client.fetch(shopKey);
      if (!mounted) return;
      _fill(info);
      setState(() {
        _info = info;
        _loading = false;
      });
      // The role decides whether the business name is editable. Fail closed:
      // any error leaves `_role` null (read-only).
      await _resolveRole();
    } on ShopInfoException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = shopInfoTr(context, 'shopInfoLoadFailed',
            namedArgs: {'detail': '$e'});
      });
    }
  }

  void _fill(ShopInfo info) {
    _businessName.text = info.businessName;
    _address.text = info.address;
    _city.text = info.city;
    _ownerName.text = info.ownerName;
    _phone.text = info.phone;
  }

  /// Reads the token's role from `GET /v1/sync/status`. Any failure leaves the
  /// role unknown, which renders the business name read-only.
  Future<void> _resolveRole() async {
    try {
      final client = await _syncFactory();
      try {
        final role = await client.syncRole();
        if (mounted) setState(() => _role = role);
      } finally {
        client.close();
      }
    } catch (_) {
      if (mounted) setState(() => _role = null);
    }
  }

  Future<void> _save() async {
    final info = _info;
    if (info == null) return;
    final businessNameChanged =
        _canEditBusinessName && _businessName.text.trim() != info.businessName;
    final patch = ShopInfoPatch(
      // Sent ONLY when it changed (and only when the role allows it): an
      // untouched name must never travel, so a salesman's patch cannot be
      // turned into a rename by a stale controller.
      businessName:
          businessNameChanged ? _businessName.text.trim() : null,
      address: _address.text != info.address ? _address.text.trim() : null,
      city: _city.text != info.city ? _city.text.trim() : null,
      ownerName:
          _ownerName.text != info.ownerName ? _ownerName.text.trim() : null,
      phone: _phone.text != info.phone ? _phone.text.trim() : null,
    );
    if (patch.isEmpty) {
      _snack(shopInfoTr(context, 'shopInfoNoChanges'));
      return;
    }
    setState(() => _loading = true);
    try {
      final client = _client ?? await _factory();
      _client = client;
      final updated = await client.patch(_keyController.text.trim(), patch);
      if (!mounted) return;
      _fill(updated);
      setState(() {
        _info = updated;
        _loading = false;
        _error = null;
      });
      _snack(shopInfoTr(context, 'shopInfoSaved'));
    } on ShopInfoException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = shopInfoTr(context, 'shopInfoSaveFailed',
            namedArgs: {'detail': '$e'});
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(shopInfoTr(context, 'shopInfoTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _keyController,
            decoration: InputDecoration(
              labelText: shopInfoTr(context, 'shopInfoShopKey'),
              hintText: shopInfoTr(context, 'shopInfoShopKeyHint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.search),
            label: Text(shopInfoTr(context, 'shopInfoLoad')),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
          if (_info != null && !_loading) ...[
            const SizedBox(height: 20),
            _sectionTitle(shopInfoTr(context, 'shopInfoProvisioner')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _readOnly(
                        shopInfoTr(context, 'shopInfoSignerId'),
                        _info!.provisionerSignerId),
                    _readOnly(shopInfoTr(context, 'shopInfoSignerName'),
                        _info!.provisionerName),
                    _readOnly(shopInfoTr(context, 'shopInfoSignerRole'),
                        _info!.provisionerRole),
                    _readOnly(shopInfoTr(context, 'shopInfoCatalogVersion'),
                        '${_info!.catalogVersion}'),
                    const SizedBox(height: 4),
                    Text(
                      shopInfoTr(context, 'shopInfoReadOnlyHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(shopInfoTr(context, 'shopInfoBusinessName')),
            // Owner token → editable. Salesman, or a role that could not be
            // resolved → read-only (the server would answer 403 anyway).
            if (_canEditBusinessName)
              TextField(
                controller: _businessName,
                decoration: InputDecoration(
                  labelText: shopInfoTr(context, 'shopInfoBusinessName'),
                  border: const OutlineInputBorder(),
                ),
              )
            else
              _readOnly(shopInfoTr(context, 'shopInfoBusinessName'),
                  _info!.businessName),
            const SizedBox(height: 10),
            _sectionTitle(shopInfoTr(context, 'shopInfoAddress')),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                  labelText: shopInfoTr(context, 'shopInfoAddress'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _city,
              decoration: InputDecoration(
                  labelText: shopInfoTr(context, 'shopInfoCity'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ownerName,
              decoration: InputDecoration(
                  labelText: shopInfoTr(context, 'shopInfoOwnerName'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: shopInfoTr(context, 'shopInfoPhone'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(shopInfoTr(context, 'shopInfoSave')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _readOnly(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label)),
            Expanded(child: Text(value.isEmpty ? '—' : value)),
          ],
        ),
      );
}
