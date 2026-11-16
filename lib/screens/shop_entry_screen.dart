import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../data/settings_service.dart';
import '../data/shop_provisioning_service.dart';
import '../build_config.dart';
import '../app_state.dart';
import '../utils/slug.dart';
import '../data/provisioning.dart';
import 'qr_scan_page.dart';

/// Shop entry screen: the shopkeeper enters the shop code provided by the admin.
///
/// This is the "onboarding" screen for the POS app. It validates the code
/// against the list of known shops and opens the register if valid.
class ShopEntryScreen extends StatefulWidget {
  const ShopEntryScreen({super.key});

  @override
  State<ShopEntryScreen> createState() => _ShopEntryScreenState();
}

class _ShopEntryScreenState extends State<ShopEntryScreen> {
  SettingsService get _settings => context.read<SettingsService>();

  final _codeController = TextEditingController();
  bool _loading = false;

  Future<void> _scanQr() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (token == null || token.isEmpty) return;
    await _handleToken(token);
  }

  Future<void> _handleToken(String token) async {
    try {
      final payload = Provisioning.verify(token);
      if (payload == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('invalidShopCode'.tr())),
          );
        }
        return;
      }
      final code = (payload['shop_key'] as String?)?.trim().toLowerCase();
      final name = payload['business_name'] as String?;
      // The key becomes a filename (myhanout_<key>.db) — reject anything that is
      // not a plain slug, even from a QR.
      if (code == null ||
          code.isEmpty ||
          name == null ||
          name.isEmpty ||
          !isValidShopKey(code)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('invalidShopCode'.tr())),
          );
        }
        return;
      }
      await _settings.setCurrentShopKey(code);
      await _settings.saveBusinessName(name);
      if (!mounted) return;
      context.read<AppState>().shopKey = code;
      context.read<AppState>().businessName = name;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('invalidShopCode'.tr())),
        );
      }
    }
  }
  Future<void> _joinShop() async {
    final code = _codeController.text.trim().toLowerCase();
    if (code.isEmpty) return;
    // The typed key becomes a filename (myhanout_<key>.db). Reject separators,
    // dots and traversal before it reaches Db.open.
    if (!isValidShopKey(code)) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('invalidShopCode'.tr())),
        );
      }
      return;
    }
    setState(() => _loading = true);

    if (kIsAdmin) {
      final list = await _settings.getShopList();
      if (!list.contains(code)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('invalidShopCode'.tr())),
          );
        }
        setState(() => _loading = false);
        return;
      }
      await _settings.setCurrentShopKey(code);
      if (mounted) Navigator.of(context).pop();
      setState(() => _loading = false);
      return;
    }

    // End-user: offline join. No server-registry call — the typed code is
    // accepted locally and binds this install to the shop. The QR path is the
    // real provisioning (it carries the business name); a typed code leaves the
    // stored name untouched, editable later in Settings.
    await _settings.setCurrentShopKey(code);
    final name = await _settings.getBusinessName();
    if (!mounted) return;
    final app = context.read<AppState>();
    app.shopKey = code;
    app.businessName = name;
    setState(() => _loading = false);
  }

  Future<void> _addShop() async {
    final nameController = TextEditingController();
    final keyController = TextEditingController();
    String lastAutoKey = '';
    nameController.addListener(() {
      final auto = slugify(nameController.text);
      if (keyController.text.isEmpty || keyController.text == lastAutoKey) {
        keyController.text = auto;
        lastAutoKey = auto;
      }
    });
    keyController.addListener(() {
      if (keyController.text != lastAutoKey) lastAutoKey = '';
    });
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('addShop'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'businessName'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: 'shopKey'.tr(),
                border: const OutlineInputBorder(),
              ),
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('cancel'.tr())),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final keyInput = keyController.text.trim();
              if (name.isEmpty) return;
              // Capture the ambassadors before the await: using a BuildContext
              // across the gap is a crash if this State is disposed meanwhile.
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ShopProvisioningService.createShop(
                  name: name,
                  key: keyInput.isEmpty ? null : keyInput,
                  settings: _settings,
                );
                if (mounted) navigator.pop(true);
              } catch (e) {
                if (!mounted) return;
                final msg = e is DuplicateShopKeyException
                    ? 'shopKeyDuplicate'.tr()
                    : 'shopKeyRequired'.tr();
                messenger.showSnackBar(
                  SnackBar(content: Text(msg)),
                );
              }
            },
            child: Text('createShop'.tr()),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('appName'.tr())),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'shopEntryTitle'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('shopEntrySubtitle'.tr(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: 'shopCode'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.qr_code_scanner),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text('scanQr'.tr()),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading ? null : _joinShop,
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('joinShop'.tr()),
            ),
            if (kIsAdmin) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _addShop,
                child: Text('addShop'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
