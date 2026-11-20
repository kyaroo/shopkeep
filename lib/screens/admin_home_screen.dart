import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalog_db.dart';
import '../data/catalog_delta.dart';
import '../data/catalog_sync_client.dart';
import '../data/settings_service.dart';
import '../data/signer_import.dart';
import '../data/signers_directory.dart';
import '../data/signing.dart';
import '../data/sync_config.dart';
import '../models/catalog_prefill.dart';
import '../providers/catalog_provider.dart';
import '../screens/admin_setup_screen.dart';
import '../screens/browse_page.dart';
import '../screens/capture_dialog.dart';
import '../screens/catalog_push_screen.dart';
import '../screens/catalog_scan_page.dart';
import '../screens/settings_screen.dart';
import '../screens/signer_import_screen.dart';
import '../screens/sync_settings_dialog.dart';
import '../services/catalog_publish_service.dart';
import '../services/catalog_pull_service.dart';
import '../utils/shop_l10n.dart';

/// A pushed route returning; all signer-related pushes go through this so the
/// chip / banner / security text refresh no matter which entry point was used.
typedef _PushRoute = Future<void> Function(Widget page);

/// The admin flavor's always-available shell (decision 1a).
///
/// A fresh admin install opens HERE: no shop and no signer required. Shop
/// creation / join is a section, never a gate. The missing-signer banner is
/// informational and never blocks a surface. Shop-bound data says so
/// explicitly instead of crashing.
class AdminHome extends StatefulWidget {
  const AdminHome({
    super.key,
    this.rootPublicKey,
    this.clientFactory,
    this.repository,
  });

  /// Trust root for the signer chip / pushed import screen. Production leaves
  /// this null so the baked root is used; tests inject a THROWAWAY root.
  final List<int>? rootPublicKey;

  /// Sync-client factory for the catalog pull/publish/push surfaces.
  /// Defaults to [SyncConfig.defaultClient]; tests inject a fake.
  final CatalogSyncClientFactory? clientFactory;

  /// Catalog store used by « Update catalog ». Defaults to [CatalogDb.instance];
  /// tests inject an in-memory transactional repository.
  final TransactionalCatalogRepository? repository;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with WidgetsBindingObserver {
  int _tab = 0;

  /// Founder/admin gate for the Catalog tab's add / edit / delete affordances.
  bool _canPush = false;

  /// Bumped whenever a pushed route returns or the app resumes, so the
  /// signer chip / banner / security section re-run their futures. `const`
  /// children would be skipped on a parent rebuild, hence the explicit value.
  int _refresh = 0;

  CatalogSyncClientFactory get _clientFactory =>
      widget.clientFactory ?? SyncConfig.defaultClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRole());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _refresh++);
      _refreshRole();
    }
  }

  /// Re-reads the active signer's role from the ROOT-verified directory so a
  /// tampered `active_signer_id` cannot unlock management.
  Future<void> _refreshRole() async {
    final settings = context.read<SettingsService>();
    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: widget.rootPublicKey,
    );
    if (mounted) {
      setState(() => _canPush = SignerSeedImport.canPush(role));
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      setState(() => _refresh++);
      await _refreshRole();
    }
  }

  CatalogPullService _pullService() => CatalogPullService(
        settings: context.read<SettingsService>(),
        repository: widget.repository ?? CatalogDb.instance,
        clientFactory: _clientFactory,
      );

  CatalogPublishService _publishService() => CatalogPublishService(
        settings: context.read<SettingsService>(),
        clientFactory: _clientFactory,
      );

  /// « Update catalog » — pull every generation from the local one to the
  /// server's latest, with a confirmation showing the counts.
  Future<void> _updateCatalog() async {
    final service = _pullService();
    final preview = await service.preview();
    if (!mounted) return;
    if (!preview.ok) {
      _snack(
        false,
        shopInfoTr(context, 'updateCatalogFailed',
            namedArgs: {'error': preview.error ?? ''}),
      );
      return;
    }
    if (preview.difference <= 0 || preview.isEmpty) {
      _snack(
        false,
        shopInfoTr(context, 'catalogUpToDate',
            namedArgs: {'version': '${preview.toVersion}'}),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(shopInfoTr(context, 'updateCatalogConfirmTitle')),
        content: Text(shopInfoTr(
          context,
          'updateCatalogConfirmBody',
          namedArgs: {
            'local': '${preview.fromVersion}',
            'latest': '${preview.toVersion}',
            'diff': '${preview.difference}',
            'total': '${preview.upserts + preview.deletes}',
            'upserts': '${preview.upserts}',
            'deletes': '${preview.deletes}',
          },
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(shopInfoTr(context, 'updateCatalog')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final result = await service.pull();
    if (!mounted) return;
    if (result.ok) {
      _snack(
        true,
        shopInfoTr(context, 'updateCatalogDone',
            namedArgs: {'version': '${result.toVersion}'}),
      );
    } else {
      _snack(
        false,
        shopInfoTr(context, 'updateCatalogFailed',
            namedArgs: {'error': result.error ?? ''}),
      );
    }
  }

  /// « Publish changes » — push local changes, then adopt the server's new
  /// global generation. The confirmation shows the version change.
  Future<void> _publishChanges() async {
    final provider = context.read<CatalogProvider>();
    final result = await _publishService().publish(push: provider.syncNow);
    if (!mounted) return;
    if (!result.ok) {
      _snack(
        false,
        shopInfoTr(context, 'publishFailed',
            namedArgs: {'error': result.error ?? ''}),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(shopInfoTr(context, 'publishDoneTitle')),
        content: Text(shopInfoTr(context, 'publishDoneBody',
            namedArgs: {
              'old': '${result.oldVersion}',
              'new': '${result.newVersion}',
            })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openSyncSettings() async {
    final config = await SyncConfig.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SyncSettingsDialog(config: config),
    );
    // The URL/token may have changed — re-probe the pill and refresh the chip.
    if (mounted) setState(() => _refresh++);
  }

  /// The host owns the add/scan action for the embedded catalog list.
  Future<void> _scanAdd() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CatalogScanPage()),
    );
    if (code == null || !mounted) return;
    final provider = context.read<CatalogProvider>();
    final existing = await provider.get(code);
    if (!mounted) return;
    CatalogPrefill? prefill;
    if (existing == null) {
      prefill = await showDialog<CatalogPrefill>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ResolveDialog(
          future: provider.resolveFromServer(code),
        ),
      );
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => CaptureDialog(
        barcode: code,
        existing: existing,
        prefill: prefill,
      ),
    );
  }

  void _snack(bool ok, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            ok ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin · myhanout'),
        actions: [
          _SignerChip(refresh: _refresh, rootPublicKey: widget.rootPublicKey),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _SignerBanner(
            refresh: _refresh,
            rootPublicKey: widget.rootPublicKey,
            push: _push,
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                AdminSetupScreen(
                  embedded: true,
                  rootPublicKey: widget.rootPublicKey,
                  clientFactory: widget.clientFactory,
                ),
                _catalogSection(),
                _settingsSection(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          // The active signer may have changed on a pushed route.
          _refreshRole();
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.storefront), label: 'Shops'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2), label: 'Catalog'),
          NavigationDestination(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  /// The Catalog tab: « Sync parameters » (pull / publish / server config) on
  /// top, then the distribution actions and the paged local catalog list
  /// (embedded [BrowsePage]); per-row edit/delete are folded into the list and
  /// gated by the founder/admin role.
  Widget _catalogSection() {
    return Column(
      children: [
        _syncParametersCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: () => _push(CatalogPushScreen(
                  clientFactory: _clientFactory,
                  rootPublicKey: widget.rootPublicKey,
                )),
                icon: const Icon(Icons.share),
                label: Text(shopInfoTr(context, 'catalogDistribute')),
              ),
              FilledButton.icon(
                onPressed: _canPush ? _scanAdd : null,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(shopInfoTr(context, 'catalogAddProduct')),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: BrowsePage(
            localOnly: true,
            embedded: true,
            canManage: _canPush,
          ),
        ),
      ],
    );
  }

  /// « Sync parameters » — the server pull/publish actions plus a live pill
  /// reporting token presence and the AUTHENTICATED catalog-version probe. It
  /// lives at the top of the Catalog tab: this is catalog/server state, not a
  /// settings page.
  Widget _syncParametersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(shopInfoTr(context, 'syncParameters'),
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                _SyncStatusPill(
                  refresh: _refresh,
                  clientFactory: _clientFactory,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // One row of three actions — no ListTiles: the card sits above a
            // paged list, so it must stay a single compact line.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: shopInfoTr(context, 'updateCatalog'),
                  icon: const Icon(Icons.cloud_download),
                  onPressed: _updateCatalog,
                ),
                IconButton(
                  tooltip: shopInfoTr(context, 'publishChanges'),
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: _publishChanges,
                ),
                IconButton(
                  tooltip: shopInfoTr(context, 'syncSettings'),
                  icon: const Icon(Icons.sync),
                  onPressed: _openSyncSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The Settings tab IS the settings page (no second tap). The admin flavor
  /// hosts the signers directory + import here (the former signers tab is gone).
  Widget _settingsSection() {
    return SettingsScreen(
      embedded: true,
      shopKey: '',
      rootPublicKey: widget.rootPublicKey,
    );
  }
}

/// Modal spinner shown while a scanned barcode is resolved against the server
/// catalog. Resolves the [future] once and pops with its result (the prefill
/// map, or null on miss/offline) so the capture form opens immediately after.
class _ResolveDialog extends StatelessWidget {
  final Future<CatalogPrefill?> future;
  const _ResolveDialog({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CatalogPrefill?>(
      future: future,
      builder: (context, snap) {
        // Pop as soon as the future settles (data or null). Defer the pop to
        // after the current frame so we never mutate the tree mid-build.
        if (snap.connectionState == ConnectionState.done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(snap.data);
            }
          });
        }
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Looking up product…')),
            ],
          ),
        );
      },
    );
  }
}

/// Small status pill for « Sync parameters ».
///
/// Probes the AUTHENTICATED `GET /v1/catalog/version` endpoint (not a public
/// health route): a 200 means the token is accepted AND the server is up,
/// 401/403 means the token itself is the problem, and anything else — or a
/// network error — means the server could not be reached. Distinguishing
/// "rejected" from "unreachable" is the whole point: they need different fixes.
class _SyncStatusPill extends StatefulWidget {
  const _SyncStatusPill({required this.refresh, required this.clientFactory});

  final int refresh;
  final CatalogSyncClientFactory clientFactory;

  @override
  State<_SyncStatusPill> createState() => _SyncStatusPillState();
}

enum _PillState { loading, unconfigured, missing, ok, rejected, down }

class _SyncStatusPillState extends State<_SyncStatusPill> {
  _PillState _state = _PillState.loading;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void didUpdateWidget(covariant _SyncStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) _probe();
  }

  Future<void> _probe() async {
    if (mounted) setState(() => _state = _PillState.loading);
    try {
      final config = await SyncConfig.load();
      final urlPresent = config.url != null && config.url!.trim().isNotEmpty;
      final tokenPresent =
          config.token != null && config.token!.trim().isNotEmpty;
      if (!urlPresent) {
        // SyncConfig.load falls back to the default host, so this only fires
        // when the stored URL is explicitly empty.
        if (!mounted) return;
        setState(() => _state = _PillState.unconfigured);
        return;
      }
      if (!tokenPresent) {
        if (!mounted) return;
        setState(() => _state = _PillState.missing);
        return;
      }
      final client = await widget.clientFactory();
      try {
        final code = await client.catalogVersionStatus();
        if (!mounted) return;
        setState(() => _state = switch (code) {
              200 => _PillState.ok,
              401 || 403 => _PillState.rejected,
              _ => _PillState.down,
            });
      } finally {
        client.close();
      }
    } catch (_) {
      // Network error (or the probe failed before the request): the server
      // could not be reached. Never hang on "Checking…".
      if (!mounted) return;
      setState(() => _state = _PillState.down);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String label;
    final Color bg;
    final Color fg;
    switch (_state) {
      case _PillState.loading:
        label = shopInfoTr(context, 'syncStatusChecking');
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
      case _PillState.unconfigured:
        label = shopInfoTr(context, 'syncStatusUnconfigured');
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
      case _PillState.missing:
        label = shopInfoTr(context, 'syncStatusMissing');
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
      case _PillState.ok:
        label = shopInfoTr(context, 'syncStatusOk');
        bg = scheme.primaryContainer;
        fg = scheme.onSurface;
      case _PillState.rejected:
        label = shopInfoTr(context, 'syncStatusRejected');
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
      case _PillState.down:
        label = shopInfoTr(context, 'syncStatusDown');
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Compact, ALWAYS-visible chip in the AppBar. Shows only public signer
/// metadata — id, role, or a stored-only boolean — never any seed bytes.
///
/// Founder/admin active → `id · role`. No active founder/admin signer but a
/// salesman seed on device → `id · stored only` (explicitly not distribution).
/// Otherwise → `No signer`.
class _SignerChip extends StatelessWidget {
  const _SignerChip({required this.refresh, this.rootPublicKey});

  /// Rebuilt on route return / resume so the label is never stale.
  final int refresh;
  final List<int>? rootPublicKey;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    return FutureBuilder<String>(
      key: ValueKey<int>(refresh),
      future: _signerLabel(settings),
      builder: (context, snap) {
        final label = snap.data;
        if (label == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        );
      },
    );
  }

  Future<String> _signerLabel(SettingsService settings) async {
    final id = await settings.getActiveSignerId();
    // Role is re-read from the ROOT-verified directory (baked root in prod,
    // throwaway root in tests) so a tampered prefs value cannot lie here.
    final role = await SignerSeedImport.activeRole(
      settings,
      rootPublicKey: rootPublicKey,
    );
    if (id != null && id.isNotEmpty && role != null &&
        SignerSeedImport.canPush(role)) {
      return '$id · ${role.name}';
    }

    // No active founder/admin signer: is a salesman seed merely stored?
    final directory = await SignersDirectoryLoader.load(
      settings: settings,
      rootPublicKey: rootPublicKey,
    );
    for (final signer in directory.signers) {
      if (signer.role == SignerRole.salesman &&
          await settings.getSignerKey(signer.id) != null) {
        return '${signer.id} · stored only';
      }
    }
    return 'No signer';
  }
}

/// NON-BLOCKING reminder when no active signer exists. It never gates a tab.
/// Disappears as soon as an import sets the active id and the route returns
/// ([refresh] changes), without gating any surface (decision 1a).
class _SignerBanner extends StatelessWidget {
  const _SignerBanner({
    required this.refresh,
    this.rootPublicKey,
    required this.push,
  });

  final int refresh;
  final List<int>? rootPublicKey;
  final _PushRoute push;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    return FutureBuilder<String?>(
      key: ValueKey<int>(refresh),
      future: settings.getActiveSignerId(),
      builder: (context, snap) {
        // While loading, render nothing instead of flashing a stale banner.
        // `hasData` is false for a completed future that returned null, so use
        // connectionState — null is the expected "no signer" result here.
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final id = snap.data;
        if (id != null && id.isNotEmpty) return const SizedBox.shrink();
        return MaterialBanner(
          content: const Text('No signer key — import one to enable distribution'),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          actions: [
            TextButton(
              onPressed: () => push(
                SignerImportScreen(rootPublicKey: rootPublicKey),
              ),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }
}
