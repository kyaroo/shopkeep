import 'package:flutter/material.dart';

import '../data/sync_config.dart';
import '../services/shop_info_client.dart';
import '../utils/shop_l10n.dart';

/// Per-shop info screen. Admin-only in practice (the route is only reachable
/// from the `if (kIsAdmin)` menu branch); the server call itself needs no local
/// role logic — it just sends the stored token, founder or salesman alike.
class ShopInfoScreen extends StatefulWidget {
  final String shopKey;

  /// Injectable so tests never touch SharedPreferences or real HTTP.
  final ShopInfoClientFactory? clientFactory;

  const ShopInfoScreen({
    super.key,
    this.shopKey = '',
    this.clientFactory,
  });

  @override
  State<ShopInfoScreen> createState() => _ShopInfoScreenState();
}

class _ShopInfoScreenState extends State<ShopInfoScreen> {
  late final TextEditingController _keyController;
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();

  ShopInfoClient? _client;
  ShopInfo? _info;
  bool _loading = false;
  String? _error;

  ShopInfoClientFactory get _factory =>
      widget.clientFactory ??
      () async => ShopInfoClient.fromConfig(await SyncConfig.load());

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.shopKey);
    if (widget.shopKey.trim().isNotEmpty) _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
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
    _address.text = info.address;
    _city.text = info.city;
    _ownerName.text = info.ownerName;
    _phone.text = info.phone;
  }

  Future<void> _save() async {
    final info = _info;
    if (info == null) return;
    final patch = ShopInfoPatch(
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
