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

  /// نسخة بديلة تستخدم [PdfViewerController] لتحميل نص صفحة بالرقم فقط
  /// (بدون الحاجة إلى كائن [PdfPage]) — مفيدة عند التطبيق من قائمة السياق
  /// حيث لا يتوفر كائن الصفحة مباشرة.
  /// إذا كانت الصفحة محمّلة بالفعل، تُعيد القيمة المخزّنة فوراً.
  Future<PdfPageText?> ensureLoadedByPageNumber(
    int pageNumber,
    PdfViewerController controller,
  ) async {
    final existing = _cache[pageNumber];
    if (existing != null) return existing;

    final inFlight = _loading[pageNumber];
    if (inFlight != null) return inFlight;

    try {
      final doc = controller.document;
      if (doc == null) return null;
      if (pageNumber < 1 || pageNumber > doc.pages.length) return null;
      final page = doc.pages[pageNumber - 1];
      return ensureLoaded(page);
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _cache.clear();
    _loading.clear();
  }
}
