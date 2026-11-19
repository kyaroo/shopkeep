import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/settings_service.dart';
import '../data/signer_import.dart';
import 'qr_scan_page.dart';

/// Settings → Security → « Import signer key » (decision 4a).
///
/// Accepts a `myhanout-signer-seed-v1` envelope by QR scan (primary) or by
/// picking a `.myhanoutseed` text file (fallback), decision 2a. Verification is
/// delegated to [SignerSeedImport] — root-verified directory, exact 32-byte
/// seed, derived public key match. The raw envelope is cleared the moment the
/// import returns; only public id / name / role are shown. Nothing is logged,
/// displayed or copied to the clipboard.
class SignerImportScreen extends StatefulWidget {
  /// Injected for tests; production reads the app-wide provider.
  final SettingsService? settings;

  /// Injected trust root for tests; production uses the baked root.
  final List<int>? rootPublicKey;

  const SignerImportScreen({super.key, this.settings, this.rootPublicKey});

  @override
  State<SignerImportScreen> createState() => _SignerImportScreenState();
}

class _SignerImportScreenState extends State<SignerImportScreen> {
  SettingsService get _settings =>
      widget.settings ?? context.read<SettingsService>();

  final _pasteController = TextEditingController();
  SignerImportResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    // Never keep the (possibly secret-bearing) pasted string alive.
    _pasteController.clear();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final envelope = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (envelope != null && envelope.isNotEmpty && mounted) {
      await _import(envelope);
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['myhanoutseed'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    final envelope = await File(path).readAsString();
    await _import(envelope);
  }

  Future<void> _import(String envelope) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await SignerSeedImport.import(
      envelope,
      settings: _settings,
      rootPublicKey: widget.rootPublicKey,
    );
    // Drop the raw envelope immediately — do not store it in state.
    envelope = '';
    _pasteController.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  void _showError(String code) {
    final message = switch (code) {
      SignerSeedImport.errBadFormat => 'Unrecognized seed envelope format',
      SignerSeedImport.errBadSeedLength => 'Seed must be exactly 32 bytes',
      SignerSeedImport.errUnknownSigner =>
        'Signer id is not in the trusted directory',
      SignerSeedImport.errKeyMismatch =>
        'Seed does not match the signer public key',
      SignerSeedImport.errDirectory => 'Signers directory unavailable',
      _ => 'Invalid signer seed',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import signer key')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Scan the founder\'s signer QR, or pick a .myhanoutseed file. '
            'The seed is verified against the trusted signers directory before '
            'it is stored.',
          ),
          const SizedBox(height: 20),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else ...[
            FilledButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose .myhanoutseed file'),
            ),
            const SizedBox(height: 20),
            const Text('Or paste an envelope:'),
            const SizedBox(height: 8),
            TextField(
              controller: _pasteController,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'myhanout-signer-seed-v1 envelope',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _import(_pasteController.text),
              child: const Text('Import'),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 24),
            _resultCard(_result!),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(SignerImportResult result) {
    if (!result.ok) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showError(result.error!));
      return const SizedBox.shrink();
    }
    final signer = result.signer!;
    final roleName = signer.role.name;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Signer imported',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('id: ${signer.id}'),
            Text('name: ${signer.name.isEmpty ? signer.id : signer.name}'),
            Text('role: $roleName'),
            const SizedBox(height: 12),
            if (result.activated)
              const Text('Active signer for distribution.')
            else
              Text('Stored, but not activated: role “$roleName” cannot '
                  'distribute catalogs or listings.'),
          ],
        ),
      ),
    );
  }
}
