import 'package:flutter/material.dart';

/// Global notifiers used to switch the active shop at runtime without
/// restarting the app.
final ValueNotifier<String> appShopKeyNotifier = ValueNotifier<String>('default');
final ValueNotifier<String> appBusinessNameNotifier =
    ValueNotifier<String>('Maison du Marché');
