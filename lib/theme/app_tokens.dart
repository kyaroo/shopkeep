import 'package:flutter/material.dart';

/// 4 / 8 / 12 / 16 / 24 pt spacing scale — the register contract.
class AppSpacing {
  AppSpacing._();
  static const xs = 4;
  static const s = 8;
  static const m = 12;
  static const l = 16;
  static const xl = 24;
}

/// Registered type styles from the "Market Trust — Zellij Earth" system.
///
/// Sized in logical pixels so a sale total is identical at any device DPI.
/// Colors are resolved from the theme at the call site (light/dark aware).
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  /// [fontFamily] is the app's active face: 'Tajawal' for Arabic (RTL script)
  /// and 'Inter' for Latin — 5 static weights (400/500/600/700/800) with
  /// tabular-figures on money/unit styles. No Roboto is used anywhere.
  final String? fontFamily;

  const AppTextStyles(this.fontFamily);

  @override
  AppTextStyles copyWith({String? fontFamily}) =>
      AppTextStyles(fontFamily ?? this.fontFamily);

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    return AppTextStyles(other.fontFamily);
  }

  /// Sale total — the single most glanceable number (arm's-length, bright shop).
  TextStyle total(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 28.0,
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurface,
        debugLabel: 'AppTextStyles.total',
      );

  /// Per-line subtotal (bold, tabular).
  TextStyle lineTotal(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 18.0,
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurface,
        debugLabel: 'AppTextStyles.lineTotal',
      );

  /// Unit line price (16–18px).
  TextStyle linePrice(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 16.0,
        fontWeight: FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurface,
        debugLabel: 'AppTextStyles.linePrice',
      );

  /// Product name.
  TextStyle name(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 16.0,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
        debugLabel: 'AppTextStyles.name',
      );

  /// Meta / barcodes / secondary numbers (dim).
  TextStyle meta(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 12.0,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        debugLabel: 'AppTextStyles.meta',
      );

  /// Field / button labels.
  TextStyle label(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
        debugLabel: 'AppTextStyles.label',
      );
}

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
  final Color primary;
  final Color onPrimary;

  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.primary,
    required this.onPrimary,
  });

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? primary,
    Color? onPrimary,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
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
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    );
  }
}
