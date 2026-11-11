import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart';
import '../providers/catalog_provider.dart';
import '../models/catalog_entry.dart';
import 'catalog_scan_page.dart';
import 'capture_dialog.dart';
import 'sync_settings_dialog.dart';
import 'browse_page.dart';

/// Home screen: search + list of catalog entries + a scan FAB.
/// Tapping a row opens the edit dialog; the FAB scans a new barcode.
class CatalogHomePage extends StatefulWidget {
  const CatalogHomePage({super.key});

  @override
  State<CatalogHomePage> createState() => _CatalogHomePageState();
}

class _CatalogHomePageState extends State<CatalogHomePage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      context.read<CatalogProvider>().load(search: _search.text.trim());
    });
    context.read<SyncService>().loadSyncConfig();
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CatalogScanPage()),
    );
    if (code == null || !mounted) return;
    final provider = context.read<CatalogProvider>();
    // 1) Local hit? Open the existing entry directly.
    final existing = await provider.get(code);
    if (!mounted) return;
    if (existing != null) {
      await showDialog(
        context: context,
        builder: (_) => CaptureDialog(barcode: code, existing: existing),
      );
      return;
    }
    // 2) Not local — try the server catalog (OFF-derived). Show a spinner
    //    while resolving so the owner sees progress; prefill on hit.
    Map<String, dynamic>? prefill;
    if (mounted) {
      prefill = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ResolveDialog(
          future: provider.resolveFromServer(code),
        ),
      );
    }
    if (!mounted) return;
    // 3) Open capture form: prefilled from server, or blank on miss/offline.
    await showDialog(
      context: context,
      builder: (_) => CaptureDialog(barcode: code, prefill: prefill),
    );
  }

  Future<void> _syncNow() async {
    final ok = await context.read<CatalogProvider>().syncNow();
    if (!mounted) return;
    final msg = context.read<SyncService>().syncMessage ?? '';
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _openSyncSettings() {
    final config = context.read<SyncService>().syncConfig;
    if (config == null) return;
    showDialog(
      context: context,
      builder: (_) => SyncSettingsDialog(config: config),
    );
  }

  void _openBrowse() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BrowsePage()),
    );
  }

  Widget _productLeading(CatalogEntry e) {
    if (e.photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          e.photo!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }
    // No embedded photo: branded market glyph (market-tint teal) instead of the
    // former grey `Icons.inventory_2` fallback, so every product row has a
    // consistent small product mark.
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.store, color: Colors.white, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final entries = catalog.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Mapper'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sync',
            onSelected: (value) {
              if (value == 'sync') _syncNow();
              if (value == 'browse') _openBrowse();
              if (value == 'settings') _openSyncSettings();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'browse',
                child: Row(children: const [
                  Icon(Icons.travel_explore),
                  SizedBox(width: 8),
                  Text('Browse catalog'),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'sync',
                child: Row(children: const [
                  Icon(Icons.cloud_upload_outlined),
                  SizedBox(width: 8),
                  Text('Sync now'),
                ]),
              ),
              const PopupMenuItem<String>(
                value: 'settings',
                child: Row(children: [
                  Icon(Icons.settings_outlined),
                  SizedBox(width: 8),
                  Text('Sync settings'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name, barcode or category',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: catalog.loading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? Center(
                        child: Text(
                          _search.text.trim().isEmpty
                              ? 'No products yet.\nTap the scanner to add one.'
                              : 'No matches.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          return ListTile(
                            leading: _productLeading(e),
                            title: Text(e.name),
                            subtitle: Text([
                              e.category,
                              e.barcode,
                            ].where((s) => s != null && s.isNotEmpty).join('  •  ')),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error),
                              tooltip: 'Delete',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: Text('deleteProduct'.tr()),
                                    content: Text('Remove "${e.name}" from the catalog?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: Text('cancel'.tr())),
                                      TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: Text('delete'.tr(),
                                              style: TextStyle(color: Theme.of(context).colorScheme.error))),
                                    ],
                                  ),
                                );
                                if (ok == true && mounted) {
                                  final provider =
                                      // ignore: use_build_context_synchronously
                                      context.read<CatalogProvider>();
                                  await provider.delete(e.barcode);
                                }
                              },
                            ),
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  CaptureDialog(barcode: e.barcode, existing: e),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scan,
        tooltip: 'Scan barcode',
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

/// Modal spinner shown while a scanned barcode is resolved against the server
/// catalog. Resolves the [future] once and pops with its result (the prefill
/// map, or null on miss/offline) so the capture form opens immediately after.
class _ResolveDialog extends StatelessWidget {
  final Future<Map<String, dynamic>?> future;
  const _ResolveDialog({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
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
