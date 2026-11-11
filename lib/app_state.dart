import 'package:flutter/material.dart';

/// Single source of truth for the active shop + business name.
///
/// Previously the two `ValueNotifier`s lived at package scope (`app_state.dart`),
/// which made them a hidden global dependency of every screen and provider.
/// They are now owned by this one `ChangeNotifier`, exposed via
/// `MultiProvider`, and read as `context.watch<AppState>().shopKey`.
class AppState extends ChangeNotifier {
  String _shopKey = 'default';
  String _businessName = 'Maison du Marché';

  String get shopKey => _shopKey;
  String get businessName => _businessName;

  set shopKey(String v) {
    if (_shopKey == v) return;
    _shopKey = v;
    notifyListeners();
  }

  set businessName(String v) {
    if (_businessName == v) return;
    _businessName = v;
    notifyListeners();
  }
}
