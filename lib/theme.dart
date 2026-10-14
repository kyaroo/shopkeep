library;

import 'package:flutter/material.dart';

/// "Market Trust" design system for ShopKeeper.
///
/// Principle: register-speed and trust over trendiness — optimized for
/// one-thumb, one-glance use at 60–90cm in a bright shop by a non-technical
/// owner. Deep teal-green reads "commerce/retail" in the MENA context and
/// stays legible in bright light; amber is reserved EXCLUSIVELY for low-stock
/// attention so it always means "look here".
///
/// Semantic stock colors (success / warning / danger) are exposed as a
/// [ThemeExtension] so screens never hardcode Colors.red/green/orange — they
/// read from the theme, which also makes dark mode possible later.

/// Semantic status colors + on-color pairs for stock badges and money states.
/// Kept separate from [ColorScheme] because Material3 has no first-class
/// "success/warning/danger" slots.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;

  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
  });

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
    );
  }
}

/// Brand palette — "Market Trust".
class AppPalette {
  AppPalette._();

  static const Color primary = Color(0xFF0E7C66); // deep teal-green
  static const Color primaryContainer = Color(0xFFC8F0E4);
  static const Color amber = Color(0xFFF2A104); // low-stock attention ONLY

  // Semantic status colors (WCAG-passing on white / as avatar fills).
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE65100); // darkened orange — AA on white
  static const Color danger = Color(0xFFC62828);

  static const AppColors lightStatus = AppColors(
    success: success,
    onSuccess: Colors.white,
    warning: warning,
    onWarning: Colors.white,
    danger: danger,
    onDanger: Colors.white,
  );

  /// Builds the app [ThemeData] from the Market Trust palette.
  /// [fontFamily] is passed by the caller (Tajawal for Arabic, else null/Inter).
  static ThemeData theme({String? fontFamily}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      primaryContainer: primaryContainer,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: const [lightStatus],
    );
  }
}
