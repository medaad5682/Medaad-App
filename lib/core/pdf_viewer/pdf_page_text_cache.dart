import 'package:pdfrx/pdfrx.dart';

/// ذاكرة تخزين مؤقت لنص كل صفحة (PdfPageText) لأن رسم التمييز/التسطير يحدث
/// بشكل متزامن (synchronous) داخل pagePaintCallbacks، بينما تحميل النص من PDFium
/// عملية غير متزامنة (async). لذلك نقوم بتحميل النص مسبقاً عند فتح كل صفحة
/// ونخزّنه هنا، ليكون متاحاً فوراً عند الرسم.
class PdfPageTextCache {
  final Map<int, PdfPageText> _cache = {};
  final Map<int, Future<PdfPageText>> _loading = {};

  /// نص الصفحة إن كان محمّلاً مسبقاً، أو null إذا لم يتم تحميله بعد.
  /// يُعيد null أيضاً إذا كانت القيمة المخزّنة تحتوي charRects فارغة
  /// (نتيجة تحميل جزئي مبكر)، مما يجبر paint() على إعادة المحاولة.
  PdfPageText? peek(int pageNumber) {
    final cached = _cache[pageNumber];
    // ── Fix: don't return a cached entry with empty charRects.
    // Empty charRects means the page text was loaded before PDFium finished
    // decoding the page (common for pages 2-4 of encrypted/compressed PDFs).
    // Returning null here forces paint() to schedule a reload, so the next
    // frame gets a fully-populated charRects and can draw the annotations.
    if (cached != null && cached.charRects.isEmpty) {
      _cache.remove(pageNumber);
      return null;
    }
    return cached;
  }

  /// يُبطل الإدخال المخزّن لصفحة معينة حتى يُعاد تحميلها في الدورة التالية.
  /// يُستدعى من paint() عندما يجد أن charRects المخزّنة لا تنتج أي مستطيلات
  /// لتعليق موجود — علامة على أن التحميل الأول كان ناقصاً.
  void invalidate(int pageNumber) {
    _cache.remove(pageNumber);
    // أيضاً نلغي أي طلب تحميل معلّق لنضمن إعادة الطلب من صفر.
    _loading.remove(pageNumber);
  }

  /// يضمن تحميل نص الصفحة وتخزينه. يُستدعى من FutureBuilder/onViewerReady
  /// قبل الحاجة الفعلية للرسم، بحيث يكون [peek] جاهزاً عند أول إعادة رسم.
  Future<PdfPageText> ensureLoaded(PdfPage page) {
    final existing = _cache[page.pageNumber];
    // ── Fix: skip a cached entry with empty charRects so we reload it.
    if (existing != null && existing.charRects.isNotEmpty) {
      return Future.value(existing);
    }

    final inFlight = _loading[page.pageNumber];
    if (inFlight != null) return inFlight;

    final future = page.loadStructuredText().then((text) {
      // ── Fix: only promote to the permanent cache when charRects is populated.
      // If charRects is still empty (page not yet decoded), we leave _cache
      // empty for this page so the next call to ensureLoaded retries the load.
      if (text.charRects.isNotEmpty) {
        _cache[page.pageNumber] = text;
      }
      _loading.remove(page.pageNumber);
      return text;
    });
    _loading[page.pageNumber] = future;
    return future;
  }

  /// نسخة بديلة تستخدم [PdfViewerController] لتحميل نص صفحة بالرقم فقط
  /// (بدون الحاجة إلى كائن [PdfPage]) — مفيدة عند التطبيق من قائمة السياق
  /// حيث لا يتوفر كائن الصفحة مباشرة.
  /// إذا كانت الصفحة محمّلة بالفعل بـ charRects غير فارغة، تُعيد القيمة فوراً.
  Future<PdfPageText?> ensureLoadedByPageNumber(
    int pageNumber,
    PdfViewerController controller,
  ) async {
    final existing = _cache[pageNumber];
    // ── Fix: same guard as ensureLoaded — skip empty-charRects entries.
    if (existing != null && existing.charRects.isNotEmpty) return existing;

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
