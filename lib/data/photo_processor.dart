import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Downscales a picked image to the mapper's storage policy:
/// max width 128px, JPEG quality 60, EXIF stripped, ~5-15KB.
///
/// Returns null if the image can't be decoded (graceful degradation — the
/// name+category always survive; a missing photo is acceptable).
Uint8List? processPhoto(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return null;

  img.Image resized = decoded;
  if (decoded.width > 128) {
    resized = img.copyResize(decoded, width: 128);
  }

  final jpg = img.encodeJpg(resized, quality: 60);

  // Hard cap: if a photo somehow exceeds ~50KB after downscale, reject it.
  // Keeps the export file small as the catalog grows.
  if (jpg.length > 50 * 1024) return null;

  return jpg;
}
