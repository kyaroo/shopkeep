import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'screens/admin_setup_screen.dart';

const supportedLocales = [
  Locale('en'),
  Locale('fr'),
  Locale('ar'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(AdminSetupApp());
}

class AdminSetupApp extends StatelessWidget {
  const AdminSetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('fr'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: const AdminSetupScreen(),
    );
  }
}
