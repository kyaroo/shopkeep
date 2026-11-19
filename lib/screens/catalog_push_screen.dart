import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/catalog_sync_client.dart';
import '../data/settings_service.dart';
import '../data/signer_import.dart';
import '../data/sync_config.dart';
import '../models/catalog_entry.dart';
import '../services/catalog_pull_service.dart';
import '../services/catalog_push_service.dart';
import '../services/catalog_version_service.dart';
import '../services/push_tracker_service.dart';
import '../theme.dart';
import '../utils/shop_l10n.dart';

/// « Distribution du catalogue » — admin-only.
///
/// Builds ONE signed `.myhanout` delta covering **every generation** between
/// the shop's registered version `M` and the admin's local version `N`
/// (`base = M`, `target = N`), then hands it to the shop. The shopkeeper stays
/// 100 % offline: the file travels by WhatsApp / Android share, never by a
/// server round-trip.
///
/// The version is a **monotone counter** (seed = 1, then 2, 3, …). The delta
/// carries `base_version` = the generation the shop is on (server truth) and
/// `target_version` = the admin's generation. The shopkeeper's apply path
/// rejects any delta whose base does not match what it has installed, and its
/// verifier accepts any `target > base`.
class CatalogPushScreen extends StatefulWidget {
  /// Settings store (shop keys + installed catalog version). Defaults to the
  /// app-wide provider.
  final SettingsService? settings;

  /// Catalog source. Defaults to the shared [CatalogDb] singleton.
  final CatalogRepository? repository;

  /// Sync-client factory. Defaults to [SyncConfig.defaultClient]; injectable so
  /// tests can supply a fake without touching SharedPreferences.
  final CatalogSyncClientFactory? clientFactory;

  /// Root public key for the directory lookup. Defaults to the baked root;
  /// tests inject a throwaway trust anchor.
  final List<int>? rootPublicKey;

  /// Payload builder. Defaults to [CatalogPushBuilder.buildPayload]; tests
  /// inject a prebuilt payload (signing is real async).
  final CatalogPayloadBuilder? builder;

  /// Writes the delta file and hands it over. Defaults to a temp file +
  /// share sheet; tests inject a no-op (file IO cannot be awaited inside a
  /// `testWidgets` FakeAsync zone).
  final Future<void> Function(
      String shopKey, int target, String fileName, String json)? deliverer;

  const CatalogPushScreen({
    super.key,
    this.settings,
    this.repository,
    this.clientFactory,
    this.rootPublicKey,
    this.builder,
    this.deliverer,
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

  static const int _pageSize = 20;
  static const int _diffPageSize = 100;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int? _minVersion;
  int? _maxVersion;
  List<ShopRow> _shops = [];
  int _total = 0;
  bool _hasMore = false;
  bool _shopsLoading = false;
  bool _loadingMore = false;
  String? _shopsError;
  List<CatalogEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _localVersionCache = 0;

  ShopRow? _selected;
  bool _building = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Initial load: catalog metadata once, then the first shop page.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.init();
      final entries = await _repo.all();
      final local = await _settings.getCatalogVersion();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _localVersionCache = local;
        _loading = false;
      });
      await _fetchShops(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'catalogPushLoadFailed'.tr();
      });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = _searchController.text.trim();
      _fetchShops(reset: true);
    });
  }

  void _setVersionRange(int? min, int? max) {
    if (_minVersion == min && _maxVersion == max) return;
    _minVersion = min;
    _maxVersion = max;
    _fetchShops(reset: true);
  }

  /// GET /v1/shops/search with q + version range + limit/offset paging.
  Future<void> _fetchShops({required bool reset}) async {
    final offset = reset ? 0 : _shops.length;
    if (!reset && !_hasMore) return;
    if (mounted) {
      setState(() {
        if (reset) {
          _shopsLoading = true;
          _shopsError = null;
        } else {
          _loadingMore = true;
        }
      });
    }
    try {
      final client = await _clientFactory();
      ShopSearchResult result;
      try {
        result = await client.searchShops(
          q: _query,
          minVersion: _minVersion,
          maxVersion: _maxVersion,
          limit: _pageSize,
          offset: offset,
        );
      } finally {
        client.close();
      }
      if (!mounted) return;
      setState(() {
        _shops = reset
            ? List<ShopRow>.of(result.items)
            : <ShopRow>[..._shops, ...result.items];
        _total = result.total;
        _hasMore = result.hasMore;
        _shopsLoading = false;
        _loadingMore = false;
      });
    } on SyncException {
      // Server unreachable / token rejected: no shop list to target, but the
      // admin's own catalog stays usable.
      if (!mounted) return;
      setState(() {
        if (reset) _shops = const [];
        _total = 0;
        _hasMore = false;
        _shopsLoading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shopsLoading = false;
        _loadingMore = false;
        _shopsError = 'catalogPushLoadFailed'.tr();
      });
    }
  }

  /// Group the loaded page by catalog version for the section headers.
  Map<int, List<ShopRow>> _groupedShops() {
    final groups = <int, List<ShopRow>>{};
    for (final shop in _shops) {
      (groups[shop.catalogVersion] ??= <ShopRow>[]).add(shop);
    }
    final sorted = <int, List<ShopRow>>{};
    for (final key in groups.keys.toList()..sort()) {
      sorted[key] = groups[key]!;
    }
    return sorted;
  }

  /// The version the admin's catalog is at: the seed is 1 and every applied
  /// delta advances it, so the local value is the distribution target.
  Future<int> _localVersion() => _settings.getCatalogVersion();

  Future<void> _buildAndShare() async {
    final shop = _selected;
    if (shop == null || _building) return;

    setState(() => _building = true);
    try {
      final signerId = await _settings.getActiveSignerId();
      final seed = signerId == null ? null : await _settings.getSignerKey(signerId);
      if (signerId == null || seed == null) {
        if (mounted) setState(() => _building = false);
        _snack(false, 'catalogPushNoSigner'.tr());
        return;
      }
      // Re-check the role from the ROOT-verified directory at push time: an
      // edited `active_signer_id` must never turn a salesman into a distributor.
      final role = await SignerSeedImport.activeRole(
        _settings,
        rootPublicKey: widget.rootPublicKey,
      );
      if (!SignerSeedImport.canPush(role)) {
        if (mounted) setState(() => _building = false);
        _snack(false, 'Only founder or admin signers can distribute');
        return;
      }

      final m = shop.catalogVersion;
      if (m <= 0) {
        if (mounted) setState(() => _building = false);
        _snack(false,
            'catalogPushNoBase'.tr(namedArgs: {'key': shop.shopKey}));
        return;
      }

      final n = await _localVersion();
      if (!mounted) return;
      if (m > n) {
        setState(() => _building = false);
        _snack(
          false,
          'catalogPushBaseMismatch'.tr(namedArgs: {
            'key': shop.shopKey,
            'local': '$n',
            'remote': '$m',
          }),
        );
        return;
      }
      if (m == n) {
        setState(() => _building = false);
        _snack(
          false,
          shopInfoTr(context, 'catalogPushUpToDate',
              namedArgs: {'key': shop.shopKey, 'version': '$n'}),
        );
        return;
      }

      // One multi-generation diff: base = M (shop), target = N (admin).
      final client = await _clientFactory();
      CatalogDiffRange range;
      try {
        range = await fetchCatalogDiff(client,
            fromVersion: m, limit: _diffPageSize);
      } finally {
        client.close();
      }
      if (!mounted) return;

      // Last change wins per barcode, restricted to generations M+1..N.
      final folded = <String, CatalogDiffChange>{};
      for (final c in range.changes) {
        if (c.version <= m || c.version > n) continue;
        folded[c.barcode] = c;
      }
      final changes = folded.values.toList();
      final upserts = <CatalogEntry>[];
      final deletes = <String>[];
      for (final c in changes) {
        if (c.isDelete) {
          deletes.add(c.barcode);
        } else if (c.row != null) {
          upserts.add(c.row!);
        }
      }

      final localBarcodes = _entries.map((e) => e.barcode).toSet();
      final additions =
          upserts.where((e) => !localBarcodes.contains(e.barcode)).length;
      final updates = upserts.length - additions;

      if (!mounted) return;
      setState(() => _building = false);

      final confirmed = await _confirmDelivery(
        shop.shopKey,
        m,
        n,
        changes.length,
        additions,
        updates,
        deletes.length,
      );
      if (confirmed != true || !mounted) return;
      await _deliver(shop.shopKey, m, n, upserts, deletes);
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

  /// Builds the delta, reports the shop's new generation, then hands the file
  /// to the system share sheet.
  Future<void> _deliver(
    String shopKey,
    int base,
    int target,
    List<CatalogEntry> entries,
    List<String> deletes,
  ) async {
    setState(() => _building = true);
    try {
      final signerId = await _settings.getActiveSignerId();
      final seed = signerId == null ? null : await _settings.getSignerKey(signerId);
      if (signerId == null || seed == null) {
        if (mounted) setState(() => _building = false);
        _snack(false, 'catalogPushNoSigner'.tr());
        return;
      }

      final result = await (widget.builder ?? CatalogPushBuilder.buildPayload)(
        localVersion: target,
        shopVersion: base,
        targetVersion: target,
        signerId: signerId,
        privateSeed: seed,
        entries: entries,
        deletes: deletes,
      );

      if (!mounted) return;
      setState(() => _building = false);
      _snack(
        true,
        'catalogPushBuilt'.tr(namedArgs: {
          'key': shopKey,
          'count': '${result.upserts}',
          'size': (result.json.length / 1024).toStringAsFixed(1),
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

      // The version is reported only after the user confirmed the handover.
      await _recordDelivery(shopKey, target);
      if (!mounted) return;
      await (widget.deliverer ?? _defaultDeliver)(
          shopKey, target, CatalogPushBuilder.fileName(shopKey, target),
          result.json);
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack(false, 'catalogPushFailed'.tr(namedArgs: {'error': '$e'}));
    }
  }

  /// Default delivery: write the signed delta to a temp file and hand it to
  /// the system share sheet (WhatsApp / file manager).
  Future<void> _defaultDeliver(
      String shopKey, int target, String fileName, String json) async {
    final dir = Directory.systemTemp.createTempSync('myhanout_push_');
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(json, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.myhanout')],
      subject: 'myhanout catalog v$target — $shopKey',
    );
  }

  /// Confirmation box: M → N, the generation gap, and the change counts.
  /// Reporting a version that was never delivered would desynchronise the
  /// server's truth, so nothing is built before this returns true.
  Future<bool?> _confirmDelivery(
    String shopKey,
    int base,
    int target,
    int total,
    int additions,
    int updates,
    int deletes,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(shopInfoTr(context, 'catalogPushConfirmTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shopInfoTr(context, 'catalogPushConfirmSummary', namedArgs: {
              'key': shopKey,
              'base': '$base',
              'target': '$target',
              'diff': '${target - base}',
            })),
            const SizedBox(height: 8),
            Text(shopInfoTr(context, 'catalogPushConfirmCounts', namedArgs: {
              'total': '$total',
              'additions': '$additions',
              'updates': '$updates',
              'deletes': '$deletes',
            })),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(shopInfoTr(context, 'catalogPushConfirmAction')),
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
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: shopInfoTr(context, 'catalogPushSearchHint'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _versionChip(shopInfoTr(context, 'catalogPushAllVersions'),
                        null, null),
                    _versionChip(
                        shopInfoTr(context, 'catalogPushVersionNever'), 0, 0),
                    _versionChip(shopInfoTr(context, 'catalogPushVersionOne'), 1, 1),
                    _versionChip(
                        shopInfoTr(context, 'catalogPushVersionTwoPlus'), 2, null),
                  ],
                ),
                const SizedBox(height: 8),
                if (_shopsError != null)
                  Text(_shopsError!, style: TextStyle(color: status.danger)),
                if (_shopsLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_shops.isEmpty)
                  Text(_query.isEmpty
                      ? 'catalogPushNoShops'.tr()
                      : shopInfoTr(context, 'catalogPushNoSearchResults'))
                else
                  Text(
                    shopInfoTr(context, 'catalogPushShowing',
                        namedArgs: {
                          'count': '${_shops.length}',
                          'total': '$_total',
                        }),
                    style: Theme.of(context).extension<AppTextStyles>()!.meta(context),
                  ),
                ..._groupedShops().entries.expand((group) => [
                      const SizedBox(height: 8),
                      Text(
                        shopInfoTr(context, 'catalogPushGroupVersion',
                            namedArgs: {'version': '${group.key}'}),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      ...group.value.map(_shopTile),
                    ]),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  _selectionCard(_selected!),
                ],
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_hasMore)
                  OutlinedButton.icon(
                    onPressed: () => _fetchShops(reset: false),
                    icon: const Icon(Icons.expand_more),
                    label: Text(shopInfoTr(context, 'catalogPushLoadMore')),
                  ),
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

  /// Shop version M, admin version N and the gap N−M for the selected shop.
  Widget _selectionCard(ShopRow shop) {
    final m = shop.catalogVersion;
    final n = _localVersionCache;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shop.businessName.isEmpty ? shop.shopKey : shop.businessName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(shopInfoTr(context, 'catalogPushVersionsLine', namedArgs: {
              'shop': '$m',
              'admin': '$n',
            })),
            Text(shopInfoTr(context, 'catalogPushDifferenceLine', namedArgs: {
              'diff': '${n - m}',
            })),
          ],
        ),
      ),
    );
  }

  Widget _versionChip(String label, int? min, int? max) {
    final selected = _minVersion == min && _maxVersion == max;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setVersionRange(min, max),
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
