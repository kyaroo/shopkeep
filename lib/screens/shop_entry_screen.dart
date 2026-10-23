import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../data/config.dart';
import '../theme.dart';

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
  final _codeController = TextEditingController();
  bool _loading = false;

  Future<void> _joinShop() async {
    final code = _codeController.text.trim().toLowerCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);

    final list = await Config.getShopList();
    if (!list.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('invalidShopCode'.tr())),
      );
      setState(() => _loading = false);
      return;
    }

    await Config.setCurrentShopKey(code);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addShop() async {
    final nameController = TextEditingController();
    final keyController = TextEditingController();
    nameController.addListener(() {
      if (keyController.text.isEmpty) {
        keyController.text = _slugify(nameController.text);
      }
    });
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final key = keyController.text.trim().toLowerCase();
              if (name.isEmpty || key.isEmpty) return;
              await Config.addShop(key, name);
              await Config.setCurrentShopKey(key);
              await Config.saveBusinessName(name);
              if (context.mounted) Navigator.pop(context, true);
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

  String _slugify(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('myhanoutadmin')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.point_of_sale, size: 64, color: Colors.teal),
            const SizedBox(height: 24),
            Text(
              'shopEntryTitle'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('shopEntrySubtitle'.tr(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
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
            const SizedBox(height: 12),
            TextButton(
              onPressed: _addShop,
              child: Text('addShop'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
