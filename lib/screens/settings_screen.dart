import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../build_config.dart';
import '../data/import_export.dart';
import '../data/settings_service.dart';
import '../data/signers_directory.dart';
import '../data/signing.dart';
import '../screens/signer_import_screen.dart';
import '../services/shop_export_service.dart';
import '../theme.dart';

/// Settings screen.
///
/// Two flavors, one file — the compile-time [kIsAdmin] decides the body:
///
///  * **admin** (embedded in the AdminHome Settings tab): the installed catalog
///    generation, the app build version, and the signer material (directory +
///    import). No business-name or shop-provisioning surface lives here any
///    more: creating / joining a shop moved to the Shops tab, and the business
///    name is edited per shop on the shop-info screen.
///  * **shopkeeper**: the stored business name (read-only — it was recorded by
///    the salesman in the signed QR) and the shop-bound exports. The catalog
///    export stays admin-only.
class SettingsScreen extends StatefulWidget {
  final String shopKey;

  /// When true, render only the scrollable body (no [Scaffold]/AppBar) so the
  /// admin Settings tab can host it directly.
  final bool embedded;

  /// Trust root for the signers directory / pushed import screen. Production
  /// leaves this null (baked root); tests inject a throwaway root.
  final List<int>? rootPublicKey;

  const SettingsScreen({
    super.key,
    required this.shopKey,
    this.embedded = false,
    this.rootPublicKey,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _settings => context.read<SettingsService>();

  late final TextEditingController _nameController;

  /// Bumped when the signer import returns so the directory / active-signer
  /// rows re-run their futures.
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadBusinessName();
  }

  Future<void> _loadBusinessName() async {
    final name = await _settings.getBusinessName();
    if (mounted) _nameController.text = name;
  }

  Future<void> _importSignerKey() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignerImportScreen(rootPublicKey: widget.rootPublicKey),
      ),
    );
    if (mounted) setState(() => _refresh++);
  }

  /// Writes [json] to a temp file and hands it to the system share sheet.
  /// IO / share failures surface as the standard export-failed snackbar.
  Future<void> _shareJson(String format, String shopKey, String json) async {
    try {
      await ShopExportService.shareJson(format, shopKey, json);
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

  /// The universal catalog. **Admin only** — the catalog is the admin's
  /// artifact, never the shopkeeper's. Metadata only, never photos.
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

  /// Shop-bound data has no meaning on a fresh admin install (no shop yet).
  /// Show an explicit state instead of opening an empty shop DB.
  void _noShop() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No shop selected — choose a shop first')),
    );
  }

  /// The shop's own price/stock listing. Shopkeeper flavor only.
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

  /// The shop's own sales history. Shopkeeper flavor only.
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

  @override
  void dispose() {
    _nameController.dispose();
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                // The catalog is the ADMIN's artifact. This guard is the whole
                // point: an earlier version of the backup card sat outside it
                // and rendered the catalog action in both flavors.
                if (kIsAdmin)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2),
                    title: Text('exportCatalog'.tr()),
                    onTap: _exportCatalog,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Build version: a compile-time dart-define, so no plugin and no
        // package_info lookup (which would be a platform channel on every
        // open).
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('appVersionLabel'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                Text(
                  const String.fromEnvironment('APP_VERSION',
                      defaultValue: 'dev'),
                  style: Theme.of(context).extension<AppTextStyles>()!.name(context),
                ),
              ],
            ),
          ),
        ),
        // The admin's signer material (directory + import) lives HERE, in the
        // Settings tab — the old Security tab is gone. Both cards are
        // admin-only; the shopkeeper branch below renders no signer surface.
        if (kIsAdmin) ...[
          const SizedBox(height: 12),
          _SignersDirectoryCard(
            refresh: _refresh,
            settings: _settings,
            rootPublicKey: widget.rootPublicKey,
          ),
          const SizedBox(height: 12),
          _SignerKeyCard(
            refresh: _refresh,
            settings: _settings,
            onImport: _importSignerKey,
          ),
        ],
        if (!kIsAdmin) ...[
          const SizedBox(height: 12),
          _businessNameCard(),
          const SizedBox(height: 12),
          _backupCard(),
        ],
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr())),
      body: body,
    );
  }

  /// The stored provisioning value. Read-only on both flavors: on shopkeeper it
  /// was recorded by the salesman in the signed QR, and on admin it is edited
  /// per shop on the shop-info screen instead.
  Widget _businessNameCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('businessName'.tr(),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
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
    );
  }

  /// Shop-bound exports. Shopkeeper only — the admin flavor has no shop DB on
  /// this device, and the catalog export is the admin artifact (above).
  Widget _backupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('backup'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
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
            ListTile(
              leading: const Icon(Icons.download),
              title: Text('restoreBackup'.tr()),
              onTap: _importCatalog,
            ),
          ],
        ),
      ),
    );
  }
}

/// Signers directory, loaded through the root-verified loader so a tampered
/// `active_signer_id` or a scanned override cannot lie about who may sign.
class _SignersDirectoryCard extends StatelessWidget {
  const _SignersDirectoryCard({
    required this.refresh,
    required this.settings,
    this.rootPublicKey,
  });

  final int refresh;
  final SettingsService settings;
  final List<int>? rootPublicKey;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signers directory',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FutureBuilder<SignersDirectory>(
              key: ValueKey<int>(refresh),
              future: SignersDirectoryLoader.load(
                settings: settings,
                rootPublicKey: rootPublicKey,
              ),
              builder: (context, snap) {
                if (snap.hasError || !snap.hasData) {
                  return const Text('Directory unavailable');
                }
                final dir = snap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('version: ${dir.version}'),
                    const SizedBox(height: 8),
                    ...dir.signers.map(
                      (s) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(s.name.isEmpty ? s.id : s.name),
                        subtitle: Text('${s.id} · ${s.role.name}'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Active signer + the import entry point (moved from the old Security tab).
class _SignerKeyCard extends StatelessWidget {
  const _SignerKeyCard({
    required this.refresh,
    required this.settings,
    required this.onImport,
  });

  final int refresh;
  final SettingsService settings;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signer key', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              key: ValueKey<int>(refresh),
              future: settings.getActiveSignerId(),
              builder: (context, snap) => Text(
                'Active signer: ${snap.data ?? 'none'}',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.key),
              label: const Text('Import signer key'),
            ),
          ],
        ),
      ),
    );
  }
}
