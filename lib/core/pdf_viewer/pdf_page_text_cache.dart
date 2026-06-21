import 'package:pdfrx/pdfrx.dart';

/// ذاكرة تخزين مؤقت لنص كل صفحة (PdfPageText) لأن رسم التمييز/التسطير يحدث
/// بشكل متزامن (synchronous) داخل pagePaintCallbacks، بينما تحميل النص من PDFium
/// عملية غير متزامنة (async). لذلك نقوم بتحميل النص مسبقاً عند فتح كل صفحة
/// ونخزّنه هنا، ليكون متاحاً فوراً عند الرسم.
class PdfPageTextCache {
  final Map<int, PdfPageText> _cache = {};
  final Map<int, Future<PdfPageText>> _loading = {};

  /// نص الصفحة إن كان محمّلاً مسبقاً، أو null إذا لم يتم تحميله بعد.
  PdfPageText? peek(int pageNumber) => _cache[pageNumber];

  /// يضمن تحميل نص الصفحة وتخزينه. يُستدعى من FutureBuilder/onViewerReady
  /// قبل الحاجة الفعلية للرسم، بحيث يكون [peek] جاهزاً عند أول إعادة رسم.
  Future<PdfPageText> ensureLoaded(PdfPage page) {
    final existing = _cache[page.pageNumber];
    if (existing != null) return Future.value(existing);

    final inFlight = _loading[page.pageNumber];
    if (inFlight != null) return inFlight;

    final future = page.loadStructuredText().then((text) {
      _cache[page.pageNumber] = text;
      _loading.remove(page.pageNumber);
      return text;
    });
    _loading[page.pageNumber] = future;
    return future;
  }

  void clear() {
    _cache.clear();
    _loading.clear();
  }
}
