/// Money helpers for ShopKeeper.
///
/// The data model stores prices as integer cents (`priceCents`). These helpers
/// bridge the gap between what the owner types/sees (dirhams, "19.90" or
/// "19,90") and the stored cents. Single source of truth for price input and
/// display across checkout and inventory.
library;

/// Parses a dirham string the owner types into integer cents.
///
/// Accepts "19.90", "19,90" (comma decimal), and space thousands separators
/// ("1 250" or "1 250,50"). Throws [FormatException] on invalid/negative input
/// so callers can surface a friendly inline error instead of crashing.
int parseDirhamsToCents(String input) {
  // Strip spaces (thousands separators), normalize comma decimal to dot.
  final normalized = input.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (normalized.isEmpty) throw const FormatException('empty');
  final value = double.tryParse(normalized);
  if (value == null || value < 0) throw const FormatException('invalid');
  return (value * 100).round();
}

/// Formats integer cents as a dirham amount: space thousands separator, comma
/// decimal, "MAD" suffix — e.g. 125050 -> "1 250,50 MAD".
///
/// Western (Latin) digits are used in all locales, matching common Moroccan
/// practice. Locale-independent by design (avoids intl locale-data init issues
/// under easy_localization).
String formatMoney(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  final wholeStr = _groupThousands(whole.toString());
  final sign = negative ? '-' : '';
  return '$sign$wholeStr,$frac MAD';
}

/// Formats integer cents as a plain editable dirham string for a price input
/// field (no currency symbol): 1990 -> "19.90", 2000 -> "20.00".
/// Round-trips through [parseDirhamsToCents].
String formatDirhamsInput(int cents) {
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '$whole.$frac';
}

/// Groups a digit string with space thousands separators: "125050" -> "125 050".
String _groupThousands(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return buf.toString();
}
