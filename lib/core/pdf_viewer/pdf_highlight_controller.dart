import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/highlight_model.dart';
import '../services/pdf_annotation_store.dart';
import 'pdf_highlight_engine.dart';
import 'pdf_highlight_debug_report.dart';
import 'pdf_page_text_cache.dart';

/// الأداة النشطة في وضع "التمييز/التسطير" بالتحديد الحقيقي للنص.
enum TextMarkupTool { none, highlight, underline }

/// يدير عملية تمييز/تسطير النص الحقيقي: يلتقط التحديد الذي توفره pdfrx،
/// يحوّله إلى [HighlightModel]/[UnderlineModel] دائم، يرسمه بدقة سطر بسطر،
/// ويوفر اكتشاف اللمس على عنصر موجود لتعديل لونه أو حذفه.
class PdfHighlightController {
  PdfHighlightController({
    required this.store,
    required this.textCache,
    required this.onChanged,
  });

  final PdfAnnotationStore store;
  final PdfPageTextCache textCache;

  /// يُستدعى بعد أي تغيير (إضافة/حذف/تعديل) لإعادة بناء الواجهة.
  final VoidCallback onChanged;

  TextMarkupTool activeTool = TextMarkupTool.none;
  int highlightColor = 0xFFFFEB3B; // أصفر افتراضي للتمييز
  int underlineColor = 0xFFEF4444; // أحمر افتراضي للتسطير
  double highlightOpacity = 0.4;

  /// آخر تقرير تشخيص تم إنتاجه من [handleTextSelectionChange]، لعرضه في حوار
  /// قابل للنسخ بعد الضغط على زر تمييز/تسطير. يُستبدل في كل عملية جديدة.
  PdfHighlightDebugReport? lastDebugReport;

  final Map<int, List<HighlightModel>> _highlights = {};
  final Map<int, List<UnderlineModel>> _underlines = {};

  List<HighlightModel> highlightsForPage(int page) => _highlights[page] ?? const [];
  List<UnderlineModel> underlinesForPage(int page) => _underlines[page] ?? const [];

  bool get isActive => activeTool != TextMarkupTool.none;

  /// تحميل التمييز/التسطير المحفوظ لصفحة معينة (يُستدعى عند بناء كل صفحة لأول مرة).
  Future<void> ensurePageLoaded(int pageNumber) async {
    if (!_highlights.containsKey(pageNumber)) {
      _highlights[pageNumber] = await store.loadHighlights(pageNumber);
    }
    if (!_underlines.containsKey(pageNumber)) {
      _underlines[pageNumber] = await store.loadUnderlines(pageNumber);
    }
  }

  Future<void> _persistHighlights(int pageNumber) =>
      store.saveHighlights(pageNumber, _highlights[pageNumber] ?? const []);

  Future<void> _persistUnderlines(int pageNumber) =>
      store.saveUnderlines(pageNumber, _underlines[pageNumber] ?? const []);

  /// يُستدعى من PdfTextSelectionParams.onTextSelectionChange.
  /// نحفظ كائن التحديد الحالي فقط دون تطبيق التمييز/التسطير فوراً،
  /// حتى يتمكن المستخدم من ضبط نقطتَي البداية والنهاية بحرية.
  /// يُطبَّق التمييز/التسطير فقط عند استدعاء [applyPendingSelection].
  PdfTextSelection? _pendingSelection;

  void updatePendingSelection(PdfTextSelection selection) {
    if (selection.hasSelectedText) {
      _pendingSelection = selection;
    }
  }

  /// Clears any pending selection (call after committing or cancelling).
  void clearPendingSelection() {
    _pendingSelection = null;
  }

  /// يُستدعى من زر قائمة السياق بعد أن يُثبّت المستخدم تحديده.
  Future<void> applyPendingSelection(PdfViewerController controller) async {
    final selection = _pendingSelection;
    if (selection == null) return;
    
    // تم التعديل: لا نقوم بمسح pendingSelection فوراً. ننتظر حتى تنجح 
    // عملية الحفظ في handleTextSelectionChange ثم نمسحه هناك.
    await handleTextSelectionChange(selection, controller);
  }

  Future<void> handleTextSelectionChange(
    PdfTextSelection selection,
    PdfViewerController controller,
  ) async {
    final report = PdfHighlightDebugReport(
      toolName: activeTool == TextMarkupTool.highlight
          ? 'تمييز (Highlight)'
          : activeTool == TextMarkupTool.underline
              ? 'تسطير (Underline)'
              : 'بدون أداة نشطة',
    );
    lastDebugReport = report;

    if (activeTool == TextMarkupTool.none) {
      report.log('تم الإلغاء: لا توجد أداة نشطة (activeTool == none).');
      report.markFinished();
      return;
    }
    if (!selection.hasSelectedText) {
      report.log('تم الإلغاء: التحديد (selection) لا يحتوي نصاً محدداً.');
      report.markFinished();
      return;
    }

    report.setSummary('activePageNumber (controller.pageNumber)', controller.pageNumber);
    report.setSummary('totalPages (controller.document?.pages.length)',
        controller.document?.pages.length);
    report.log('بدء المعالجة. selection.hasSelectedText == true.');

    // ── Fix: robust retry for getSelectedTextRanges on decrypted/heavy pages ──
    // الإصلاح الجذري: نقوم بتسخين ذاكرة التخزين المؤقت للنص أولاً لجميع الصفحات
    // المرئية قبل استدعاء getSelectedTextRanges لتجنب حالة السباق التي تسبب
    // فشل التمييز/التسطير على بعض الصفحات دون غيرها.
    //
    // الخطوة 1: محاولة أولى للحصول على النطاقات
    var ranges = await selection.getSelectedTextRanges();
    report.log('المحاولة الأولى لـ getSelectedTextRanges(): ${ranges.length} نطاق.');

    // الخطوة 2: إذا كانت فارغة، نقوم بتسخين الصفحات المجاورة ثم نعيد المحاولة
    if (ranges.isEmpty) {
      report.log('النطاقات فارغة. سيتم تسخين كاش النص للصفحات المجاورة وإعادة المحاولة.');
      // تسخين الصفحات المجاورة للصفحة النشطة
      try {
        final doc = controller.document;
        if (doc != null) {
          final activePage = controller.pageNumber ?? 1;
          for (int p = (activePage - 1).clamp(1, doc.pages.length);
              p <= (activePage + 1).clamp(1, doc.pages.length);
              p++) {
            await textCache.ensureLoadedByPageNumber(p, controller);
            report.log('تم تسخين كاش النص للصفحة $p '
                '(hasReliableText=${textCache.hasReliableText(p)}).');
          }
        }
      } catch (e) {
        report.log('خطأ أثناء تسخين الصفحات المجاورة: $e');
      }

      const retryDelays = [50, 100, 200, 400, 600, 1000];
      for (final delayMs in retryDelays) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        ranges = await selection.getSelectedTextRanges();
        report.log('إعادة محاولة بعد ${delayMs}ms: ${ranges.length} نطاق.');
        if (ranges.isNotEmpty) break;
      }
    }
    if (ranges.isEmpty) {
      report.log('فشل نهائي: لم يتم العثور على أي نطاق نص قابل للتمييز/التسطير.');
      report.markFinished();
      return;
    }

    report.setSummary('rangesFound', ranges.length);

    bool anyApplied = false;
    for (final range in ranges) {
      final rangeLog = <String>[];
      void rlog(String m) => rangeLog.add(m);

      rlog('pageNumber=${range.pageNumber}, start=${range.start}, end=${range.end}');

      if (range.start >= range.end) {
        rlog('تم تجاهل هذا النطاق: start >= end (نطاق فارغ أو غير صالح).');
        report.addRangeDetail({
          'pageNumber': range.pageNumber,
          'start': range.start,
          'end': range.end,
          'skipped': true,
          'log': rangeLog,
        });
        continue;
      }

      await ensurePageLoaded(range.pageNumber);
      await textCache.ensureLoadedByPageNumber(range.pageNumber, controller);

      // ── معلومات تشخيصية: حالة الصفحة في pdfrx وحالة كاش النص لدينا ──
      bool? pageIsLoaded;
      double? pageWidth;
      double? pageHeight;
      int? pageRotationIndex;
      try {
        final doc = controller.document;
        if (doc != null && range.pageNumber >= 1 && range.pageNumber <= doc.pages.length) {
          final page = doc.pages[range.pageNumber - 1];
          pageIsLoaded = page.isLoaded;
          pageWidth = page.width;
          pageHeight = page.height;
          pageRotationIndex = page.rotation.index;
        }
      } catch (e) {
        rlog('خطأ أثناء قراءة معلومات الصفحة من controller.document: $e');
      }
      rlog('page.isLoaded=$pageIsLoaded, page.width=$pageWidth, page.height=$pageHeight, '
          'page.rotation=$pageRotationIndex');

      final cachedText = textCache.peek(range.pageNumber);
      final hasReliableText = textCache.hasReliableText(range.pageNumber);
      rlog('textCache.peek(${range.pageNumber}) == '
          '${cachedText == null ? 'null' : 'PdfPageText(charRects: ${cachedText.charRects.length})'}'
          ', hasReliableText=$hasReliableText');

      // حساب مستطيلات السطور التي سيتم الرسم عليها (نفس المنطق المستخدم في paint())
      List<Map<String, dynamic>> lineRectsLog = [];
      if (cachedText != null) {
        try {
          final lineRects = PdfHighlightEngine.lineRectsForRange(
            pageText: cachedText,
            start: range.start,
            end: range.end,
          );
          lineRectsLog = lineRects
              .map((r) => {
                    'left': r.left,
                    'top': r.top,
                    'right': r.right,
                    'bottom': r.bottom,
                  })
              .toList();
          rlog('lineRectsForRange() أنتج ${lineRects.length} مستطيل (سطر) بإحداثيات صفحة PDF.');
          if (lineRects.isEmpty) {
            rlog('⚠️ تحذير: lineRectsForRange() أرجع قائمة فارغة. '
                'هذا يعني أن التمييز/التسطير سيُحفظ بنجاح لكنه لن يُرسم بصرياً '
                'على الإطلاق حتى تتم إعادة حساب هذه المستطيلات لاحقاً '
                '(غالباً بسبب نص صفحة فارغ/غير موثوق وقت الحفظ).');
          }
        } catch (e) {
          rlog('خطأ أثناء حساب lineRectsForRange(): $e');
        }
      } else {
        rlog('⚠️ تحذير: لا يوجد نص محفوظ موثوق لهذه الصفحة بعد. '
            'سيتم حفظ التمييز/التسطير الآن، وسيُعاد حساب مستطيلات الرسم تلقائياً '
            'في أول إعادة رسم بعد اكتمال تحميل نص الصفحة فعلياً.');
      }

      final id = '${DateTime.now().microsecondsSinceEpoch}_${range.pageNumber}_${range.start}';
      rlog('سيتم إنشاء عنصر جديد بمعرّف id=$id');

      if (activeTool == TextMarkupTool.highlight) {
        final list = _highlights.putIfAbsent(range.pageNumber, () => []);
        final model = HighlightModel(
          id: id,
          pageNumber: range.pageNumber,
          start: range.start,
          end: range.end,
          color: highlightColor,
          opacity: highlightOpacity,
        );
        list.add(model);
        await _persistHighlights(range.pageNumber);
        anyApplied = true;
        rlog('تم إضافة HighlightModel وحفظه محلياً. '
            'عدد عناصر التمييز المحفوظة لهذه الصفحة الآن: ${list.length}.');
        report.addRangeDetail({
          'pageNumber': range.pageNumber,
          'start': range.start,
          'end': range.end,
          'pageIsLoaded': pageIsLoaded,
          'pageWidth': pageWidth,
          'pageHeight': pageHeight,
          'textCacheHasReliableText': hasReliableText,
          'textCacheCharRectsCount': cachedText?.charRects.length,
          'computedLineRects (PDF page coords)': lineRectsLog,
          'createdModel': model.toJson(),
          'log': rangeLog,
        });
      } else if (activeTool == TextMarkupTool.underline) {
        final list = _underlines.putIfAbsent(range.pageNumber, () => []);
        final model = UnderlineModel(
          id: id,
          pageNumber: range.pageNumber,
          start: range.start,
          end: range.end,
          color: underlineColor,
        );
        list.add(model);
        await _persistUnderlines(range.pageNumber);
        anyApplied = true;
        rlog('تم إضافة UnderlineModel وحفظه محلياً. '
            'عدد عناصر التسطير المحفوظة لهذه الصفحة الآن: ${list.length}.');
        report.addRangeDetail({
          'pageNumber': range.pageNumber,
          'start': range.start,
          'end': range.end,
          'pageIsLoaded': pageIsLoaded,
          'pageWidth': pageWidth,
          'pageHeight': pageHeight,
          'textCacheHasReliableText': hasReliableText,
          'textCacheCharRectsCount': cachedText?.charRects.length,
          'computedLineRects (PDF page coords)': lineRectsLog,
          'createdModel': model.toJson(),
          'log': rangeLog,
        });
      }
    }

    report.setSummary('anyApplied', anyApplied);

    // إضافة لقطة من البيانات المخزّنة فعلياً على الجهاز لكل صفحة تمت معالجتها،
    // لتأكيد أن العنصر تم حفظه بنجاح بغض النظر عن ظهوره بصرياً أم لا.
    final affectedPages = ranges.map((r) => r.pageNumber).toSet();
    final storedDataDump = <String, dynamic>{};
    for (final p in affectedPages) {
      try {
        storedDataDump['page_$p'] = await dumpStoredDataForPage(p);
      } catch (e) {
        storedDataDump['page_$p'] = {'error': e.toString()};
      }
    }
    report.setSummary('storedDataOnDevice', storedDataDump);

    if (!anyApplied) {
      report.log('لم يتم تطبيق أي نطاق (جميعها كانت غير صالحة).');
      report.markFinished();
      return;
    }

    // نجحت العملية: الآن يمكننا مسح التحديد بأمان
    clearPendingSelection();
    await controller.textSelectionDelegate.clearTextSelection();
    report.log('تم مسح التحديد الحالي ومسح pendingSelection بنجاح.');
    report.log('استدعاء onChanged() لإعادة بناء الواجهة وإعادة الرسم.');
    report.markFinished();
    onChanged();
  }

  /// يجلب نسخة من البيانات المخزّنة محلياً (تمييز + تسطير) لصفحة معينة بصيغة
  /// JSON قابلة للعرض، لاستخدامها في حوار التشخيص. يقرأ من المخزن مباشرة
  /// (لا من القوائم المحمّلة في الذاكرة) لضمان أنه يعكس ما هو محفوظ فعلياً
  /// على الجهاز في هذه اللحظة.
  Future<Map<String, dynamic>> dumpStoredDataForPage(int pageNumber) async {
    final storedHighlights = await store.loadHighlights(pageNumber);
    final storedUnderlines = await store.loadUnderlines(pageNumber);
    return {
      'pageNumber': pageNumber,
      'inMemoryHighlightsCount': _highlights[pageNumber]?.length,
      'inMemoryUnderlinesCount': _underlines[pageNumber]?.length,
      'storedHighlights': storedHighlights.map((h) => h.toJson()).toList(),
      'storedUnderlines': storedUnderlines.map((u) => u.toJson()).toList(),
    };
  }

  /// اكتشاف اللمس على تمييز/تسطير موجود عند نقطة بالـ PDF (نظام إحداثيات الصفحة).
  ({HighlightModel? highlight, UnderlineModel? underline}) hitTest({
    required int pageNumber,
    required double pdfX,
    required double pdfY,
  }) {
    final pageText = textCache.peek(pageNumber);
    if (pageText == null) return (highlight: null, underline: null);

    final h = PdfHighlightEngine.hitTestHighlight(
      highlights: highlightsForPage(pageNumber),
      pageText: pageText,
      pdfX: pdfX,
      pdfY: pdfY,
    );
    if (h != null) return (highlight: h, underline: null);

    final u = PdfHighlightEngine.hitTestUnderline(
      underlines: underlinesForPage(pageNumber),
      pageText: pageText,
      pdfX: pdfX,
      pdfY: pdfY,
    );
    return (highlight: null, underline: u);
  }

  /// يبحث عن أي تمييز/تسطير يتقاطع مع نطاق نص محدد (selection range).
  /// يكفي أن يتداخل التحديد مع جزء صغير من التمييز/التسطير لإرجاع الكامل.
  /// يُستخدم من زر "تعديل" في قائمة السياق بدلاً من النقر على العنصر مباشرة.
  ({HighlightModel? highlight, UnderlineModel? underline}) findOverlappingMarkup({
    required int pageNumber,
    required int selectionStart,
    required int selectionEnd,
  }) {
    if (selectionEnd <= selectionStart) return (highlight: null, underline: null);

    // البحث عن تمييز يتداخل مع نطاق التحديد
    for (final h in highlightsForPage(pageNumber).reversed) {
      final overlaps = h.start < selectionEnd && h.end > selectionStart;
      if (overlaps) return (highlight: h, underline: null);
    }

    // البحث عن تسطير يتداخل مع نطاق التحديد
    for (final u in underlinesForPage(pageNumber).reversed) {
      final overlaps = u.start < selectionEnd && u.end > selectionStart;
      if (overlaps) return (highlight: null, underline: u);
    }

    return (highlight: null, underline: null);
  }

  /// يجلب نطاقات النص للتحديد الحالي (المعلّق).
  /// مفيد لزر "تعديل" لاكتشاف التمييز/التسطير المتداخل دون تطبيق جديد.
  Future<List<({int pageNumber, int start, int end})>> getPendingSelectionRanges(
    PdfViewerController controller,
  ) async {
    final selection = _pendingSelection;
    if (selection == null || !selection.hasSelectedText) return [];

    var ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) {
      const retryDelays = [50, 100, 200];
      for (final delayMs in retryDelays) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        ranges = await selection.getSelectedTextRanges();
        if (ranges.isNotEmpty) break;
      }
    }

    return ranges
        .where((r) => r.start < r.end)
        .map((r) => (pageNumber: r.pageNumber, start: r.start, end: r.end))
        .toList();
  }

  Future<void> updateHighlightColor(HighlightModel h, int color) async {
    h.color = color;
    await _persistHighlights(h.pageNumber);
    onChanged();
  }

  Future<void> updateHighlightOpacity(HighlightModel h, double opacity) async {
    h.opacity = opacity;
    await _persistHighlights(h.pageNumber);
    onChanged();
  }

  Future<void> deleteHighlight(HighlightModel h) async {
    _highlights[h.pageNumber]?.removeWhere((e) => e.id == h.id);
    await _persistHighlights(h.pageNumber);
    onChanged();
  }

  Future<void> updateUnderlineColor(UnderlineModel u, int color) async {
    u.color = color;
    await _persistUnderlines(u.pageNumber);
    onChanged();
  }

  Future<void> deleteUnderline(UnderlineModel u) async {
    _underlines[u.pageNumber]?.removeWhere((e) => e.id == u.id);
    await _persistUnderlines(u.pageNumber);
    onChanged();
  }

  /// دالة الرسم المرتبطة بـ PdfViewerParams.pagePaintCallbacks.
  /// تُستدعى بشكل متزامن لكل صفحة مرئية في كل إعادة رسم.
  void paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    // ── Fix: لا نعتمد على نتيجة فارغة محفوظة كنهائية. peek() يُرجع null إن
    // كانت النتيجة المخزّنة سابقاً فارغة (page كان لا يزال placeholder وقتها)،
    // فنُعيد المحاولة هنا. بما أن pdfrx يمرر لنا [page] حقيقياً ومحمّلاً فعلاً
    // في كل إعادة رسم لاحقة (بعد أن يستبدل pdfrx الـ placeholder)، فإن
    // loadStructuredText() سينجح في المحاولة التالية تلقائياً دون أي تدخل آخر.
    final pageText = textCache.peek(page.pageNumber);
    if (pageText == null) {
      // ── Fix: إخبار الشاشة بضرورة التحديث فوراً بعد تحميل النص ──
      // ignore: discarded_futures
      textCache.ensureLoaded(page).then((_) {
        onChanged();
      });
      return;
    }

    // toRectInDocument needs the real absolute pageRect (the page's position
    // inside the scrollable document) so it can correctly map PDF coordinates
    // to Flutter screen coordinates. The canvas is NOT pre-translated by pdfrx
    // before calling pagePaintCallbacks — it uses the global scroll coordinate
    // system. A previous attempt used localPageRect = Rect(0,0,w,h) under the
    // mistaken belief that the canvas was pre-translated; that caused:
    //   • Page 1 highlights to appear slightly above/left (small top offset lost)
    //   • Page 2+ highlights to appear on page 1's canvas (large top offset lost,
    //     coords collapse back into page 1's screen area)

    // رسم التمييز (طبقة تحت النص، شبه شفافة)
    for (final h in highlightsForPage(page.pageNumber)) {
      final lineRects = PdfHighlightEngine.lineRectsForRange(
        pageText: pageText,
        start: h.start,
        end: h.end,
      );
      if (lineRects.isEmpty) continue;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = Color(h.color).withOpacity(h.opacity);
      for (final r in lineRects) {
        // تكبير طفيف رأسياً ليغطي التمييز كامل ارتفاع السطر بشكل طبيعي
        final flutterRect =
            r.inflate(0, r.height * 0.12).toRectInDocument(page: page, pageRect: pageRect);
        canvas.drawRect(flutterRect, paint);
      }
    }

    // رسم التسطير (خط أسفل كل سطر محدد)
    for (final u in underlinesForPage(page.pageNumber)) {
      final lineRects = PdfHighlightEngine.lineRectsForRange(
        pageText: pageText,
        start: u.start,
        end: u.end,
      );
      if (lineRects.isEmpty) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u.thickness
        ..strokeCap = StrokeCap.round
        ..color = Color(u.color);
      for (final r in lineRects) {
        final flutterRect = r.toRectInDocument(page: page, pageRect: pageRect);
        canvas.drawLine(
          Offset(flutterRect.left, flutterRect.bottom),
          Offset(flutterRect.right, flutterRect.bottom),
          paint,
        );
      }
    }
  }
}
