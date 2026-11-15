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
///
/// This file is a barrel: the register-distance type/spacing tokens live in
/// `app_tokens.dart`, and the palette plus the [AppPalette.theme] builder in
/// `app_palette.dart`. Import `theme.dart` — the split is internal.
library;

export 'theme/app_palette.dart';
export 'theme/app_tokens.dart';
