String formatMoney(int cents) {
  final whole = cents ~/ 100;
  final frac = cents.remainder(100).toString().padLeft(2, '0');
  return '$whole.$frac';
}
