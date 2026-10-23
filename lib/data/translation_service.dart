import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of an Arabic-script suggestion for a product name.
class ArabicSuggestion {
  final String arabic;
  final double match; // 0..1 quality from the service
  ArabicSuggestion(this.arabic, this.match);
}

/// Capture-time assist: suggests the Arabic-script rendering of a French/Latin
/// product name. Used ONCE at capture — never in any read path, so the catalog
/// stays offline for reads. If the service is unavailable, callers fall back to
/// manual entry; nothing breaks.
///
/// Uses MyMemory (no key, verified fr→ar). The client is swappable for a
/// dedicated transliteration service later without changing callers.
class TranslationService {
  final http.Client _client;
  TranslationService({http.Client? client}) : _client = client ?? http.Client();

  /// Suggests Arabic script for [frenchName]. Returns null on any failure
  /// (network, parse, empty) so the caller just keeps manual entry.
  Future<ArabicSuggestion?> suggestArabic(String frenchName) async {
    final name = frenchName.trim();
    if (name.isEmpty) return null;
    final uri = Uri.parse(
        'https://api.mymemory.translated.net/get?q=${Uri.encodeQueryComponent(name)}&langpair=fr|ar');
    try {
      final resp = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final rd = data['responseData'] as Map<String, dynamic>?;
      final text = (rd?['translatedText'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      final match = (rd?['match'] as num?)?.toDouble() ?? 0.0;
      return ArabicSuggestion(text, match);
    } on Exception {
      return null;
    }
  }

  void close() => _client.close();
}
