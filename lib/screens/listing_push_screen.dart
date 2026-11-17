import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/settings_service.dart';
import '../services/listing_export_service.dart';

/// « Exporter la liste » — builds a signed `.myhanoutlisting` for one shop and
/// hands it over (WhatsApp / share sheet), exactly like the catalog delta.
///
/// The counterpart of the shopkeeper's « Importer la boutique ». Until this
/// screen existed, `ListingExportBuilder` had no caller and the listing channel
/// could not be exercised end to end.
///
/// No network: the file is delivered by hand, and the shopkeeper verifies it
/// offline against the signers directory.
class ListingPushScreen extends StatefulWidget {
  const ListingPushScreen({super.key, this.exporter, this.deliverer});

  /// Builds the bundle for [shopKey]. Defaults to the real
  /// [ListingExportBuilder.export]; injected by tests, because sqflite cannot
  /// be awaited inside a `testWidgets` FakeAsync zone.
  final Future<ListingExportResult> Function({
    required String shopKey,
    required String signerId,
    required List<int> privateSeed,
  })? exporter;

  /// Writes the bundle to a file and hands it over. Injectable because real
  /// file IO cannot be awaited inside a `testWidgets` FakeAsync zone.
  final Future<void> Function(
      String shopKey, String fileName, String json)? deliverer;

  @override
  State<ListingPushScreen> createState() => _ListingPushScreenState();
}

/// Writes the bundle to a temp file and opens the share sheet.
///
/// `application/octet-stream` matches the `.myhanoutlisting` VIEW intent
/// filter, so the file can be opened straight into the shopkeeper app.
Future<void> _defaultDeliver(
    String shopKey, String fileName, String json) async {
  final dir = Directory.systemTemp.createTempSync('myhanout_listing_');
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(json, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/octet-stream')],
    subject: 'myhanout listing — $shopKey',
  );
}

/// The real export path, kept out of the widget's constructor so tests can
/// substitute it (sqflite cannot run inside a `testWidgets` FakeAsync zone).
Future<ListingExportResult> _defaultExporter({
  required String shopKey,
  required String signerId,
  required List<int> privateSeed,
}) =>
    ListingExportBuilder.export(
      shopKey: shopKey,
      signerId: signerId,
      privateSeed: privateSeed,
    );

class _ListingPushScreenState extends State<ListingPushScreen> {
  SettingsService get _settings => context.read<SettingsService>();

  List<String> _shops = [];
  String _selected = '';
  bool _loading = true;
  bool _building = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _settings.getShopList();
    final current = await _settings.getCurrentShopKey();
    if (!mounted) return;
    setState(() {
      _shops = list;
      _selected =
          list.contains(current) ? current : (list.isEmpty ? '' : list.first);
      _loading = false;
    });
  }

  void _snack(String key, [Map<String, String> args = const {}]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(key.tr(namedArgs: args))),
    );
  }

  Future<void> _exportAndShare() async {
    if (_selected.isEmpty || _building) return;
    setState(() => _building = true);
    try {
      final signerId = await _settings.getActiveSignerId();
      final seed = signerId == null ? null : await _settings.getSignerKey(signerId);
      if (signerId == null || seed == null) {
        // Without a signer there is no attribution; refuse rather than emit an
        // unsigned bundle the shopkeeper would reject anyway.
        if (mounted) setState(() => _building = false);
        _snack('catalogPushNoSigner');
        return;
      }

      final result = await (widget.exporter ?? _defaultExporter)(
        shopKey: _selected,
        signerId: signerId,
        privateSeed: seed,
      );


      if (!mounted) return;
      setState(() => _building = false);
      _snack('listingPushBuilt', {
        'key': _selected,
        'count': '${result.rows}',
        'size': (result.json.length / 1024).toStringAsFixed(1),
      });

      await (widget.deliverer ?? _defaultDeliver)(
          _selected, result.fileName, result.json);
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      _snack('listingPushFailed', {'error': '$e'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('listingPushTitle'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('listingPushExplain'.tr(),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_shops.isEmpty)
            Text('listingPushNoShops'.tr())
          else
            DropdownButton<String>(
              value: _selected.isEmpty ? null : _selected,
              hint: Text('shopKey'.tr()),
              items: [
                for (final key in _shops)
                  DropdownMenuItem(value: key, child: Text(key)),
              ],
              onChanged: (v) => setState(() => _selected = v ?? _selected),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_selected.isEmpty || _building) ? null : _exportAndShare,
            icon: _building
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            label: Text('listingPushAction'.tr()),
          ),
        ],
      ),
    );
  }
}
