import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/highlight_model.dart';
import '../services/pdf_annotation_store.dart';
import 'pdf_highlight_engine.dart';
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
    if (activeTool == TextMarkupTool.none) return;
    if (!selection.hasSelectedText) return;

    // ── Fix: robust retry for getSelectedTextRanges on decrypted/heavy pages ──
    // الإصلاح الجذري: نقوم بتسخين ذاكرة التخزين المؤقت للنص أولاً لجميع الصفحات
    // المرئية قبل استدعاء getSelectedTextRanges لتجنب حالة السباق التي تسبب
    // فشل التمييز/التسطير على بعض الصفحات دون غيرها.
    //
    // الخطوة 1: محاولة أولى للحصول على النطاقات
    var ranges = await selection.getSelectedTextRanges();

    // الخطوة 2: إذا كانت فارغة، نقوم بتسخين الصفحات المجاورة ثم نعيد المحاولة
    if (ranges.isEmpty) {
      // تسخين الصفحات المجاورة للصفحة النشطة
      try {
        final doc = controller.document;
        if (doc != null) {
          final activePage = controller.pageNumber ?? 1;
          for (int p = (activePage - 1).clamp(1, doc.pages.length);
              p <= (activePage + 1).clamp(1, doc.pages.length);
              p++) {
            await textCache.ensureLoadedByPageNumber(p, controller);
          }
        }
      } catch (_) {}

      const retryDelays = [50, 100, 200, 400, 600, 1000];
      for (final delayMs in retryDelays) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        ranges = await selection.getSelectedTextRanges();
        if (ranges.isNotEmpty) break;
      }
    }
    if (ranges.isEmpty) return;

    bool anyApplied = false;
    for (final range in ranges) {
      if (range.start >= range.end) continue;

      // ── Fix: ensure page text is fully loaded before persisting ──
      await ensurePageLoaded(range.pageNumber);

      // ── Extra fix: pre-warm the text cache for this page ──
      await textCache.ensureLoadedByPageNumber(range.pageNumber, controller);

      final id = '${DateTime.now().microsecondsSinceEpoch}_${range.pageNumber}_${range.start}';

      if (activeTool == TextMarkupTool.highlight) {
        final list = _highlights.putIfAbsent(range.pageNumber, () => []);
        list.add(HighlightModel(
          id: id,
          pageNumber: range.pageNumber,
          start: range.start,
          end: range.end,
          color: highlightColor,
          opacity: highlightOpacity,
        ));
        await _persistHighlights(range.pageNumber);
        anyApplied = true;
      } else if (activeTool == TextMarkupTool.underline) {
        final list = _underlines.putIfAbsent(range.pageNumber, () => []);
        list.add(UnderlineModel(
          id: id,
          pageNumber: range.pageNumber,
          start: range.start,
          end: range.end,
          color: underlineColor,
        ));
        await _persistUnderlines(range.pageNumber);
        anyApplied = true;
      }
    }

    if (!anyApplied) return;

    // نجحت العملية: الآن يمكننا مسح التحديد بأمان
    clearPendingSelection();
    await controller.textSelectionDelegate.clearTextSelection();
    onChanged();
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
    final pageText = textCache.peek(page.pageNumber);
    if (pageText == null) {
      // ── Fix: إخبار الشاشة بضرورة التحديث فوراً بعد تحميل النص ──
      // ignore: discarded_futures
      textCache.ensureLoaded(page).then((_) {
        onChanged();
      });
      return;
    }

    // رسم التمييز (طبقة تحت النص، شبه شفافة)
    for (final h in highlightsForPage(page.pageNumber)) {
      final lineRects = PdfHighlightEngine.lineRectsForRange(
        pageText: pageText,
        start: h.start,
        end: h.end,
      );
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
