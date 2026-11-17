import 'dart:io';

import 'package:flutter/services.dart';

import '../services/listing_import_service.dart';
import 'settings_service.dart';

/// Entry point for `.myhanoutlisting` shop listing bundles.
///
/// Mirrors [MyhanoutFile] for the listing channel: Android routes a VIEW intent
/// to `MainActivity`, which exposes the URI over the `myhanout/view` method
/// channel; this class reads it and hands the bytes to
/// [ListingImportService], which verifies before writing anything.
class ListingImportFile {
  static const MethodChannel _channel = MethodChannel('myhanout/view');

  /// Reads a listing bundle from a `file://` or `content://` URI.
  ///
  /// Returns a rejected outcome (never null, never throws) when the URI cannot
  /// be read, so a caller can always show something.
  static Future<ListingImportOutcome> applyUri(
    String uri, {
    SettingsService? settings,
  }) async {
    final String? json;
    try {
      json = await _channel.invokeMethod<String>('readUri', {'uri': uri});
    } catch (_) {
      return ListingImportOutcome.rejected('unreadable file');
    }
    if (json == null || json.isEmpty) {
      return ListingImportOutcome.rejected('unreadable file');
    }
    return ListingImportService.apply(json, settings: settings);
  }

  /// Reads a listing bundle from a plain file path (file picker).
  static Future<ListingImportOutcome> applyPath(
    String path, {
    SettingsService? settings,
  }) async {
    try {
      return await ListingImportService.apply(
        await File(path).readAsString(),
        settings: settings,
      );
    } catch (_) {
      return ListingImportOutcome.rejected('unreadable file');
    }
  }
}
