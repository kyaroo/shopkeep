import 'package:flutter/material.dart';

import 'app_tokens.dart';

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
    primary: primary,
    onPrimary: onPrimary,
  );

  static const AppColors darkStatus = AppColors(
    success: darkSuccess,
    onSuccess: darkOnSuccess,
    warning: darkWarning,
    onWarning: darkOnWarning,
    danger: darkDanger,
    onDanger: darkOnDanger,
    primary: darkPrimary,
    onPrimary: darkOnPrimary,
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
      // ---- Component theme defaults (UI spec v1.0) ----
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: onSurfaceColor,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: surfaceVariantColor.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: surfaceVariantColor.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: errorColor, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: errorColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: surfaceVariantColor.withValues(alpha: 0.2)),
        ),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: surfaceVariantColor,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
