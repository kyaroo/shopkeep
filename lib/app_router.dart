import 'package:flutter/material.dart';
import 'package:myhanout/main.dart';
import 'package:provider/provider.dart';
import 'admin_home_app.dart';
import 'app_state.dart';
import 'build_config.dart';
import 'data/settings_service.dart';

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
  final SettingsService settings;

  const AppRouter({super.key, required this.appState, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          // Admin flavor opens its non-blocking shell — except when the founder
          // explicitly opened one shop's POS from the Shops tab. `posMode` is
          // in-memory only, so it never survives a cold start.
          if (kIsAdmin) {
            if (state.posMode && state.shopKey.isNotEmpty) {
              return MyhanoutApp(
                key: ValueKey(state.shopKey),
                shopKey: state.shopKey,
                businessName: state.businessName,
                settings: settings,
              );
            }
            return AdminHomeApp(settings: settings);
          }
          if (state.shopKey.isEmpty) {
            return ShopEntryApp(settings: settings);
          }
          return MyhanoutApp(
            key: ValueKey(state.shopKey),
            shopKey: state.shopKey,
            businessName: state.businessName,
            settings: settings,
          );
        },
      ),
    );
  }
}
