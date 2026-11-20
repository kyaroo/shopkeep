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

  /// Admin flavor only: the founder opened a shop's POS from the Shops tab.
  ///
  /// Deliberately NOT persisted — a cold start always lands back in the admin
  /// shell, so the POS is a session detour, not a standing mode.
  bool _posMode = false;

  String get shopKey => _shopKey;
  String get businessName => _businessName;
  bool get posMode => _posMode;

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

  set posMode(bool v) {
    if (_posMode == v) return;
    _posMode = v;
    notifyListeners();
  }
}
