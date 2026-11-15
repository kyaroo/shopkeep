import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/catalog_sync_client.dart';
import '../data/settings_service.dart';
import '../data/sync_config.dart';
import '../models/catalog_entry.dart';
import '../services/catalog_version_service.dart';
import '../services/catalog_push_service.dart';
import '../services/push_tracker_service.dart';
import '../theme.dart';

/// « Distribution du catalogue » — admin-only.
///
/// Builds a signed `.myhanout` delta from the admin's local catalog and hands
/// it to one shop. The shopkeeper stays 100 % offline: the file travels by
/// WhatsApp / Android share, never by a server round-trip.
///
/// The version is a **monotone counter** (seed = 1, then 2, 3, …). The delta
/// carries `base_version` = the generation the shop is on (server truth) and
/// `target_version` = the next one. The shopkeeper's apply path rejects any
/// delta whose base does not match what it has installed.
class CatalogPushScreen extends StatefulWidget {
  /// Settings store (shop keys + installed catalog version). Defaults to the
  /// app-wide provider.
  final SettingsService? settings;

  /// Catalog source. Defaults to the shared [CatalogDb] singleton.
  final CatalogRepository? repository;

  /// Sync-client factory. Defaults to [SyncConfig.defaultClient]; injectable so
  /// tests can supply a fake without touching SharedPreferences.
  final CatalogSyncClientFactory? clientFactory;

  const CatalogPushScreen({
    super.key,
    this.settings,
    this.repository,
    this.clientFactory,
  });

  @override
  State<CatalogPushScreen> createState() => _CatalogPushScreenState();
}

class _CatalogPushScreenState extends State<CatalogPushScreen> {
  final PushTracker _tracker = PushTracker();

  SettingsService get _settings =>
      widget.settings ?? context.read<SettingsService>();

  CatalogRepository get _repo =>
      widget.repository ?? context.read<CatalogRepository>();

  CatalogSyncClientFactory get _clientFactory =>
      widget.clientFactory ?? SyncConfig.defaultClient;

  List<ShopRow> _shops = [];
  List<CatalogEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _localVersionCache = 0;

  ShopRow? _selected;
  bool _building = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<ShopRow> shops;
      try {
        final client = await _clientFactory();
        try {
          shops = await client.listShops();
        } finally {
          client.close();
        }
      } on SyncException {
        // Server unreachable / token rejected: the admin's own catalog is still
        // usable, but there is no shop list to target.
        shops = const [];
      }
      await _repo.init();
      final entries = await _repo.all();
      final local = await _settings.getCatalogVersion();
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _entries = entries;
        _localVersionCache = local;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'catalogPushLoadFailed'.tr();
      });
    }
  }

  /// The version the admin's catalog is at: the seed is 1 and every applied
  /// delta advances it, so the local value is the next target when nothing has
  /// been delivered yet.
  Future<int> _localVersion() => _settings.getCatalogVersion();

  Future<void> _buildAndShare() async {
    final shop = _selected;
    if (shop == null || _building) return;

    final base = shop.catalogVersion;
    if (base <= 0) {
      _snack(false, 'catalogPushNoBase'.tr(namedArgs: {'key': shop.shopKey}));
      return;
    }

    setState(() => _building = true);
    try {
      final local = await _localVersion();
      final target = base + 1;
      final result = CatalogPushBuilder.buildPayload(
        localVersion: local,
        shopVersion: base,
        entries: _entries,
      );

      final dir = Directory.systemTemp.createTempSync('myhanout_push_');
      final file = File(
          '${dir.path}/${CatalogPushBuilder.fileName(shop.shopKey, target)}');
      await file.writeAsString(result.json, flush: true);

      if (!mounted) return;
      setState(() => _building = false);
      _snack(
        true,
        'catalogPushBuilt'.tr(namedArgs: {
          'key': shop.shopKey,
          'count': '${result.upserts}',
          'size': (file.lengthSync() / 1024).toStringAsFixed(1),
          'version': '$target',
        }),
      );
      if (!result.photosUntouched) {
        // The budget acted: say so rather than silently shipping smaller
        // photos. Name/category always survive.
        _snack(
          false,
          'catalogPushPhotosAdjusted'.tr(namedArgs: {
            'trimmed': '${result.photosTrimmed}',
            'dropped': '${result.photosDropped}',
          }),
        );
      }


      // The file is delivered by hand (WhatsApp / share sheet). The version is
      // only reported to the server once the user confirms it was handed over.
      final delivered = await _confirmDelivery(shop.shopKey, target, file);
      if (delivered == true && mounted) {
        await _recordDelivery(shop.shopKey, target);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/vnd.myhanout')],
          subject: 'myhanout catalog v$target — ${shop.shopKey}',
        );
      }
    } on CatalogBaseMismatchException catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack(
        false,
        'catalogPushBaseMismatch'.tr(namedArgs: {
          'key': shop.shopKey,
          'local': '${e.local}',
          'remote': '${e.remote}',
        }),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack(false, 'catalogPushFailed'.tr(namedArgs: {'error': '$e'}));
    }
  }

  /// Asks the user to confirm the file actually reached the shop. Reporting a
  /// version that was never delivered would desynchronise the server's truth.
  Future<bool?> _confirmDelivery(String shopKey, int target, File file) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('catalogPushConfirmTitle'.tr()),
        content: Text('catalogPushConfirmBody'.tr(namedArgs: {
          'key': shopKey,
          'version': '$target',
          'file': file.uri.pathSegments.last,
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('catalogPushConfirm'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _recordDelivery(String shopKey, int target) async {
    _tracker.record(shopKey, target, DateTime.now().millisecondsSinceEpoch);
    try {
      final client = await _clientFactory();
      try {
        await CatalogVersionService(client).report(shopKey, target);
      } finally {
        client.close();
      }
    } on Exception {
      // Best-effort: the delivery happened, the server just does not know yet.
      // The next delivery re-reports.
    }
  }

  void _snack(bool ok, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      appBar: AppBar(title: Text('catalogPushTitle'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!,
                          style: TextStyle(color: status.danger)),
                    ),
                  ),
                Text('catalogPushCatalog'.tr(),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'catalogPushCatalogMeta'.tr(namedArgs: {
                    'count': '${_entries.length}',
                    'version': '$_localVersionCache',
                  }),
                  style: Theme.of(context).extension<AppTextStyles>()!.meta(context),
                ),
                const SizedBox(height: 16),
                Text('catalogPushTarget'.tr(),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_shops.isEmpty)
                  Text('catalogPushNoShops'.tr())
                else
                  ..._shops.map(_shopTile),
                const Divider(height: 32),
                FilledButton.icon(
                  onPressed: (_selected == null || _building) ? null : _buildAndShare,
                  icon: _building
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share),
                  label: Text('catalogPushBuild'.tr()),
                ),
                const SizedBox(height: 24),
                Text('catalogPushHistory'.tr(),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_tracker.all.isEmpty)
                  Text('catalogPushNoHistory'.tr())
                else
                  ..._tracker.all.map(_historyTile),
              ],
            ),
    );
  }

  Widget _shopTile(ShopRow shop) {
    final isSelected = _selected?.shopKey == shop.shopKey;
    return ListTile(
      selected: isSelected,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected
            ? Theme.of(context).extension<AppColors>()!.primary
            : null,
      ),
      title: Text(shop.businessName.isEmpty ? shop.shopKey : shop.businessName),
      subtitle: Text('catalogPushShopVersion'
          .tr(namedArgs: {'key': shop.shopKey, 'version': '${shop.catalogVersion}'})),
      onTap: () => setState(() => _selected = shop),
    );
  }

  Widget _historyTile(PushRecord record) {
    final date = DateTime.fromMillisecondsSinceEpoch(record.recordedAt);
    final label = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle, size: 18),
      title: Text('catalogPushHistoryRow'.tr(namedArgs: {
        'key': record.shopKey,
        'version': '${record.targetVersion}',
        'date': label,
      })),
    );
  }
}
