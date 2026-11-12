import 'package:flutter/material.dart';
import 'package:myhanout/main.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';

/// Stateless route resolver that replaces the inline `ShopHost` / `EndUserHost`
/// guards in `main.dart`.
///
/// [appState] drives the route: an empty `shopKey` routes to the shop-entry
/// screen; a populated `shopKey` routes to the shop's home app.
///
/// The router also owns the [AppState] provider: every branch (shop entry,
/// POS home, settings) reads it via `context.watch/read<AppState>()`, so it
/// must be exposed here, above both branches. The [Consumer] rebuilds the
/// route when the shop changes at runtime (shop join / switch).
///
/// Keep this widget free of business logic: all decisions are delegated to the
/// public API on [AppState].
class AppRouter extends StatelessWidget {
  final AppState appState;

  const AppRouter({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.shopKey.isEmpty) {
            return const ShopEntryApp();
          }
          return MyhanoutApp(
            key: ValueKey(state.shopKey),
            shopKey: state.shopKey,
            businessName: state.businessName,
          );
        },
      ),
    );
  }
}
