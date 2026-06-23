import 'package:pdfrx/pdfrx.dart';

/// ذاكرة تخزين مؤقت لنص كل صفحة (PdfPageText) لأن رسم التمييز/التسطير يحدث
/// بشكل متزامن (synchronous) داخل pagePaintCallbacks، بينما تحميل النص من PDFium
/// عملية غير متزامنة (async). لذلك نقوم بتحميل النص مسبقاً عند فتح كل صفحة
/// ونخزّنه هنا، ليكون متاحاً فوراً عند الرسم.
class PdfPageTextCache {
  final Map<int, PdfPageText> _cache = {};
  final Map<int, Future<PdfPageText>> _loading = {};

  /// أرقام الصفحات التي تم تخزين نص فارغ (charRects خالٍ) لها مؤقتاً.
  /// نص فارغ غالباً لا يعني أن الصفحة بلا نص حقيقي، بل أن [PdfPage] كان
  /// لا يزال "placeholder" (isLoaded == false) عند وقت التحميل — راجع
  /// تعليق [ensureLoaded] أدناه. نحتفظ بهذه القائمة لإعادة المحاولة لاحقاً
  /// بدل اعتبار النص الفارغ نتيجة نهائية موثوقة.
  final Set<int> _emptyResultPages = {};

  /// نص الصفحة إن كان محمّلاً مسبقاً وموثوقاً، أو null إذا لم يتم تحميله بعد
  /// أو كانت النتيجة المخزنة فارغة (مشتبه بها، راجع [ensureLoaded]).
  PdfPageText? peek(int pageNumber) {
    if (_emptyResultPages.contains(pageNumber)) return null;
    return _cache[pageNumber];
  }

  /// هل لدينا نص حقيقي (غير فارغ) محفوظ لهذه الصفحة؟
  bool hasReliableText(int pageNumber) =>
      _cache.containsKey(pageNumber) && !_emptyResultPages.contains(pageNumber);

  /// يضمن تحميل نص الصفحة وتخزينه. يُستدعى من FutureBuilder/onViewerReady
  /// قبل الحاجة الفعلية للرسم، بحيث يكون [peek] جاهزاً عند أول إعادة رسم.
  ///
  /// ── إصلاح جذري لمشكلة عدم ظهور التمييز/التسطير على بعض الصفحات ──
  /// pdfrx يحمّل الصفحات بشكل تدريجي (progressive loading). الصفحات التي لم
  /// يتم تحميلها فعلياً بعد من PDFium تُمثَّل بكائن "placeholder" مؤقت
  /// (isLoaded == false) يحمل أبعاد آخر صفحة تم تحميلها فعلاً (لا أبعاده
  /// الحقيقية!). استدعاء loadStructuredText() على هذا الـ placeholder يُرجع
  /// نصاً فارغاً (charRects: []) فوراً دون أي خطأ.
  ///
  /// إذا قمنا بتخزين هذا النص الفارغ بشكل نهائي، فإن أي تمييز/تسطير يتم
  /// إنشاؤه على هذه الصفحة سيُحفظ بنجاح (لأن الحفظ لا يعتمد على النص) لكنه
  /// لن يُرسم أبداً بعد ذلك — لأن lineRectsForRange() يعمل على charRects
  /// فارغة فيُرجع قائمة فارغة دائماً، حتى بعد أن يكتمل تحميل الصفحة الحقيقية
  /// داخل pdfrx. هذا تحديداً هو سبب المشكلة التي تظهر أكثر في الصفحات القصيرة
  /// (لأن المستخدم يتجاوزها بسرعة أكبر أثناء التحميل التدريجي، فتزيد فرصة
  /// "اللحاق" بصفحة لا تزال placeholder).
  ///
  /// الحل: لا نعتبر نتيجة فارغة (charRects.isEmpty) نتيجة نهائية موثوقة.
  /// نخزّنها مؤقتاً (لتفادي إعادة الطلب المتكرر فوراً) لكن نُبقي الصفحة قابلة
  /// لإعادة المحاولة لاحقاً (عبر [invalidate] الذي يُستدعى عند
  /// PdfDocumentPageStatusChangedEvent، أو ببساطة عبر استدعاء [ensureLoaded]
  /// مرة أخرى).
  Future<PdfPageText> ensureLoaded(PdfPage page) {
    final existing = _cache[page.pageNumber];
    if (existing != null && !_emptyResultPages.contains(page.pageNumber)) {
      return Future.value(existing);
    }

    final inFlight = _loading[page.pageNumber];
    if (inFlight != null) return inFlight;

    // ── إصلاح إضافي عند المصدر ──
    // بدل الاعتماد فقط على "عدم تخزين نتيجة فارغة بشكل نهائي" (وهو خط دفاع
    // ثانٍ مفيد)، نستخدم هنا واجهة pdfrx الرسمية المخصصة تحديداً لهذه الحالة:
    // page.waitForLoaded() تنتظر حتى تصبح الصفحة محمّلة فعلياً (isLoaded == true)
    // من PDFium قبل أن نحاول قراءة نصها على الإطلاق، فنتجنب استدعاء
    // loadStructuredText() على صفحة "placeholder" من الأساس. نضع حد زمني
    // معقول كي لا تتعطل العملية إلى الأبد في حال وثيقة تالفة أو صفحة لن
    // تكتمل تحميلها أبداً؛ في تلك الحالة الوحيدة نستخدم [page] كما هي.
    final future = page
        .waitForLoaded(timeout: const Duration(seconds: 8))
        .then((loadedPage) => (loadedPage ?? page).loadStructuredText())
        .then((text) {
      _cache[page.pageNumber] = text;
      if (text.charRects.isEmpty) {
        _emptyResultPages.add(page.pageNumber);
      } else {
        _emptyResultPages.remove(page.pageNumber);
      }
      _loading.remove(page.pageNumber);
      return text;
    });
    _loading[page.pageNumber] = future;
    return future;
  }

  /// يُبطل أي نص مخزّن لصفحة معينة، لإجبار إعادة تحميله من PDFium في المرة
  /// القادمة التي يُطلب فيها. يُستدعى عند PdfDocumentPageStatusChangedEvent
  /// (أي حين يستبدل pdfrx الصفحة الـ placeholder بالصفحة الحقيقية المحمّلة).
  void invalidate(int pageNumber) {
    _cache.remove(pageNumber);
    _emptyResultPages.remove(pageNumber);
    _loading.remove(pageNumber);
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
    if (existing != null && !_emptyResultPages.contains(pageNumber)) return existing;

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
    _emptyResultPages.clear();
  }
}
