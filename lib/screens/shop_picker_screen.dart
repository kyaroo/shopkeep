import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../data/config.dart';
import '../theme.dart';

/// Shop picker: list all known shops, switch active shop, or open settings/admin.
class ShopPickerScreen extends StatefulWidget {
  const ShopPickerScreen({super.key});

  @override
  State<ShopPickerScreen> createState() => _ShopPickerScreenState();
}

class _ShopPickerScreenState extends State<ShopPickerScreen> {
  List<String> _shopKeys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    final list = await Config.getShopList();
    setState(() {
      _shopKeys = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('shops'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _shopKeys.isEmpty
              ? Center(child: Text('noShopsFound'.tr()))
              : ListView(
                  children: [
                    ListTile(
                      title: Text('activeShop'.tr()),
                      subtitle: Text(
                        _shopKeys.isNotEmpty ? _shopKeys.first : 'none'.tr(),
                      ),
                      trailing: const Icon(Icons.check_circle),
                    ),
                    const Divider(),
                    Text('shops'.tr(), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._shopKeys.map((key) {
                      return ListTile(
                        title: Text(key),
                        subtitle: Text('shopKey'.tr() + ': ' + key),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () {
                          Config.setCurrentShopKey(key);
                          Navigator.of(context).pop();
                        },
                      );
                    }),
                  ],
                ),
    );
  }
}
