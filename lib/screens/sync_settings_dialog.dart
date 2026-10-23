import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../data/sync_config.dart';

/// Lets the owner set the sync server URL + token. Fully optional — the app
/// works offline without it. Sync stays manual ("Sync now"), never automatic.
class SyncSettingsDialog extends StatefulWidget {
  final SyncConfig config;
  const SyncSettingsDialog({super.key, required this.config});

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _device;

  bool _catalogOpen = false;
  bool _loadingOpen = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.config.url ?? '');
    _token = TextEditingController(text: widget.config.token ?? '');
    _device = TextEditingController(text: widget.config.deviceId);
    if (widget.config.isConfigured) {
      _fetchOpenState();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _device.dispose();
    super.dispose();
  }

  Future<void> _fetchOpenState() async {
    setState(() => _loadingOpen = true);
    try {
      final client = widget.config.client();
      final open = await client.getCatalogOpen();
      client.close();
      if (mounted) setState(() => _catalogOpen = open);
    } catch (_) {
      // ignore; keep default
    } finally {
      if (mounted) setState(() => _loadingOpen = false);
    }
  }

  Future<void> _toggleOpen(bool value) async {
    setState(() => _loadingOpen = true);
    try {
      final client = widget.config.client();
      final open = await client.setCatalogOpen(value);
      client.close();
      if (mounted) setState(() => _catalogOpen = open);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingOpen = false);
    }
  }

  Future<void> _save() async {
    final config = SyncConfig(
      url: _url.text,
      token: _token.text,
      deviceId: _device.text.trim().isEmpty
          ? 'mapper-owner-01'
          : _device.text.trim(),
      lastSyncedAt: widget.config.lastSyncedAt,
    );
    await context.read<CatalogProvider>().saveSyncConfig(config);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://catalog.example.com',
              ),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _token,
              decoration: const InputDecoration(labelText: 'Token'),
            ),
            TextField(
              controller: _device,
              decoration: const InputDecoration(labelText: 'Device ID'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Accept pushes (server open)'),
              value: _catalogOpen,
              onChanged: _loadingOpen ? null : _toggleOpen,
              subtitle: _loadingOpen
                  ? const Text('Loading...')
                  : Text(_catalogOpen ? 'Pushes enabled' : 'Pushes disabled'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sync is manual only — tap "Sync now" in the menu. The app works '
              'fully offline without a server.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
