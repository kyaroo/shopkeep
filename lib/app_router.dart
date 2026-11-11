import 'package:flutter/material.dart';
import 'package:myhanout/main.dart';
import 'app_state.dart';

/// Stateless route resolver that replaces the inline `ShopHost` / `EndUserHost`
/// guards in `main.dart`.
///
/// [appState] drives the route: an empty `shopKey` routes to the shop-entry
/// screen; a populated `shopKey` routes to the shop's home app.
///
/// Keep this widget free of business logic: all decisions are delegated to the
/// public API on [AppState].
class AppRouter extends StatelessWidget {
  final AppState appState;

  const AppRouter({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    if (appState.shopKey.isEmpty) {
      return const ShopEntryApp();
    }
    return MyhanoutApp(
      shopKey: appState.shopKey,
      businessName: appState.businessName,
    );
  }
}
