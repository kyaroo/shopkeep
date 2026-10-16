library;

import 'package:flutter/material.dart';

/// "Market Trust — Zellij Earth" design system for ShopKeeper.
///
/// Principle: register-speed and trust over trendiness — optimized for
/// one-thumb, one-glance use at 60–90cm in a bright shop by a non-technical
/// owner. Hues are drawn from Moroccan craft rather than the stock Flutter
/// theme: a deep "mendelez" teal (commerce/retail in the MENA context, calm
/// and legible in bright light) sits on a warm plaster/ivory backdrop, with
/// saffron amber reserved exclusively for low-stock attention, and emerald +
/// deep red for success/attention semantics.
///
/// Semantic stock colors (success / warning / danger) are exposed as a
/// [ThemeExtension] so screens never hardcode Colors.red/green/orange — they
/// read from the theme, which also makes dark mode possible via one switch.
///
/// Light + dark share the same seed so the brand reads consistently across
/// brightness modes. [ColorScheme] uses only non-deprecated fields; the
/// warm-taupe "variant" tone is carried as [onSurfaceVariant] (used by the
/// inventory summary and any meta text), never as the now-deprecated
/// [surfaceVariant].

/// Register-distance type + spacing tokens for the design system.
///
/// Optimized for one-thumb, one-glance at 60–90cm in a bright shop. Numeric
/// tokens are fixed px so a sale total never reflows under the thumb; a scale
/// would re-flow the checkout row under the thumb.

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
  /// [fontFamily] is the app's active face: 'Tajawal' for Arabic, the system
  /// sans (Roboto) otherwise. Inter is intentionally NOT pinned here — it is a
  /// follow-up font-asset step, not part of the token system.
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
        fontWeight: FontWeight.w500,
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

/// "Market Trust — Zellij Earth" brand palette.
class AppPalette {
  AppPalette._();

  // ---------------------------------------------------------------------------
  // Light (foreground)
  // ---------------------------------------------------------------------------
  /// Warm plaster/ivory — far from the stark white of stock Material.
  static const Color surface = Color(0xFFF6F1E7);

  /// Near-black text on light surfaces.
  static const Color surfaceDim = Color(0xFF141414);

  /// Warm taupe for meta / barcodes / secondary text (not pure grey).
  static const Color surfaceVariant = Color(0xFF5C544A);

  /// Mendelez teal — the commerce anchor (MENA context, bright-shop legible).
  static const Color primary = Color(0xFF0D6E5C);

  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color primaryContainer = Color(0xFFCDE6DC);

  /// Saffron — attention only (low stock / scan hint). Never decorative.
  static const Color amber = Color(0xFFF2A104);

  static const Color amberOnSurface = Color(0xFF3E2A00);

  /// Tamegroute emerald — growth / success / rack-stock-ok.
  static const Color success = Color(0xFF1B5E20);

  static const Color onSuccess = Color(0xFFFFFFFF);

  /// Darkened orange — attention (used on white fills where amber fails AA).
  static const Color warning = Color(0xFFE65100);

  static const Color onWarning = Color(0xFFFFFFFF);

  /// Deep red, echoes Berber-rug leather — delete / out-of-stock.
  static const Color danger = Color(0xFF991B1B);

  static const Color onDanger = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Dark (background)
  // ---------------------------------------------------------------------------
  static const Color darkSurface = Color(0xFF121212); // #121212 family
  static const Color darkSurfaceDim = Color(0xFFE7E7E7);
  static const Color darkSurfaceVariant = Color(0xFF8A8273); // warm light taupe
  static const Color darkPrimary = Color(0xFF0D6E5C); // same seed, luminous
  static const Color darkOnPrimary = Color(0xFFFFFFFF);
  static const Color darkPrimaryContainer = Color(0xFF3F8A7C);
  static const Color darkAmber = Color(0xFFF2A104);
  static const Color darkAmberOnSurface = Color(0xFF5C3A00);
  static const Color darkSuccess = Color(0xFF1B5E20);
  static const Color darkOnSuccess = Color(0xFFFFFFFF);
  static const Color darkWarning = Color(0xFFE65100);
  static const Color darkOnWarning = Color(0xFFFFFFFF);
  static const Color darkDanger = Color(0xFF991B1B);
  static const Color darkOnDanger = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Semantic status extensions, one per brightness
  // ---------------------------------------------------------------------------
  static const AppColors lightStatus = AppColors(
    success: success,
    onSuccess: onSuccess,
    warning: warning,
    onWarning: onWarning,
    danger: danger,
    onDanger: onDanger,
  );

  static const AppColors darkStatus = AppColors(
    success: darkSuccess,
    onSuccess: darkOnSuccess,
    warning: darkWarning,
    onWarning: darkOnWarning,
    danger: darkDanger,
    onDanger: darkOnDanger,
  );

  /// Builds the app [ThemeData] from the Market Trust palette.
  /// [fontFamily] is passed by the caller (Tajawal for Arabic, else null).
  /// [brightness] switches between the local-context light and dark themes.
  static ThemeData theme({
    String? fontFamily,
    Brightness brightness = Brightness.light,
  }) {
    final isDark = brightness == Brightness.dark;

    // Surface + text colors (per brightness).
    final surfaceColor = isDark ? darkSurface : surface;
    final onSurfaceColor = isDark ? darkSurfaceDim : surfaceDim;
    final surfaceVariantColor = isDark ? darkSurfaceVariant : surfaceVariant;

    // Brand + error colors (per brightness).
    final primaryColor = isDark ? darkPrimary : primary;
    final onPrimaryColor = isDark ? darkOnPrimary : onPrimary;
    final primaryContainerColor = isDark ? darkPrimaryContainer : primaryContainer;
    final errorColor = isDark ? darkDanger : danger;
    final onErrorColor = isDark ? darkOnDanger : onDanger;

    // Material color scheme using only non-deprecated fields. The brand hue is
    // the Mendelez teal; error = deep red; amber/success/warning live in the
    // AppColors extension (not the scheme).
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: onPrimaryColor,
      primaryContainer: primaryContainerColor,
      onPrimaryContainer: onPrimaryColor,
      secondary: primaryColor, // brand as secondary for actions/links
      onSecondary: onPrimaryColor,
      secondaryContainer: primaryContainerColor,
      onSecondaryContainer: onPrimaryColor,
      error: errorColor,
      onError: onErrorColor,
      errorContainer: errorColor,
      onErrorContainer: onErrorColor,
      surface: surfaceColor,
      onSurface: onSurfaceColor,
      onSurfaceVariant: surfaceVariantColor,
      outline: onSurfaceColor,
      outlineVariant: surfaceVariantColor,
      shadow: onSurfaceColor,
      scrim: brightness == Brightness.dark
          ? Color.lerp(darkSurface, Colors.black54, 0.7)
          : const Color(0xFF333333),
    );

    final status = isDark ? darkStatus : lightStatus;
    final textStyles = AppTextStyles(fontFamily);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: [status, textStyles],
      scaffoldBackgroundColor: surfaceColor,
    );
  }
}
