import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'admin_home_app.dart';
import 'data/settings_service.dart';

/// Standalone admin entry point. Opens the SAME non-blocking shell as the
/// `ADMIN=true` build of `main.dart`; `AdminSetupScreen` is a section inside it,
/// not an app root.
const supportedLocales = [
  Locale('en'),
  Locale('fr'),
  Locale('ar'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  const settings = ConfigSettingsService();
  runApp(const AdminHomeApp(settings: settings));
}

// Kept as a thin alias for any tooling that referenced the old root.
class AdminSetupApp extends StatelessWidget {
  final SettingsService settings;
  const AdminSetupApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) => AdminHomeApp(settings: settings);
}
