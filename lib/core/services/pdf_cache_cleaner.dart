import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

/// Deletes pdfrx's on-disk PDF cache.
///
/// WHY IT STILL EXISTS
/// Online mode no longer uses that cache: the viewer downloads the PDF into
/// memory (`OnlinePdfFetcher`) and opens it with `PdfViewer.custom`, so nothing
/// new is written. But earlier app versions opened online PDFs with
/// `PdfViewer.uri`, which makes pdfrx save every PDF it displays, as a
/// PLAINTEXT file, to
///
///     <cacheDir>/pdfrx.cache/<sha1[0:2]>/<sha1[2:4]>/<sha1[4:]>.pdf
///
/// and never deletes it. Devices that ran those versions still hold those
/// files, so `SplashScreen` calls [wipe] on every cold start: the first launch
/// after the update purges them, and later launches are a cheap no-op.
///
/// (Keeping the call is also a safety net should anything ever route a PDF
/// through pdfrx's URI loader again.)
class PdfCacheCleaner {
  PdfCacheCleaner._();

  /// Folder name pdfrx uses under its cache directory. Must match
  /// `PdfFileCache.getCacheFilePathForUri` in pdfrx_engine.
  static const String _pdfrxCacheFolder = 'pdfrx.cache';

  /// Deletes pdfrx's whole PDF cache folder. Never throws.
  static Future<void> wipe() async {
    try {
      final dir = await _cacheDirectory();
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
      debugPrint('🧹 PdfCacheCleaner: removed ${dir.path}');
    } catch (e) {
      // Cleanup is best-effort: it must never break startup.
      debugPrint('PdfCacheCleaner: wipe failed ($e)');
    }
  }

  static Future<Directory> _cacheDirectory() async {
    // Same resolution order pdfrx uses: an explicit override wins, otherwise the
    // temporary directory. (At cold start pdfrx has not initialised yet, so
    // Pdfrx.cacheDirectoryPath is still null and the fallback applies.)
    final base =
        Pdfrx.cacheDirectoryPath ?? (await getTemporaryDirectory()).path;
    return Directory('$base${Platform.pathSeparator}$_pdfrxCacheFolder');
  }
}
