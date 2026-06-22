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
  ///
  /// Fix: we only UPDATE the pending selection when it actually has selected
  /// text. We never clear it here, because on some PDF pages the selection
  /// object fires a transient "no selection" event mid-gesture (while the user
  /// is still adjusting handles), which was silently nulling out a valid
  /// selection and making Highlight/Underline appear to do nothing.
  /// The selection is cleared explicitly in [applyPendingSelection] after it
  /// has been committed.
  PdfTextSelection? _pendingSelection;

  void updatePendingSelection(PdfTextSelection selection) {
    if (selection.hasSelectedText) {
      _pendingSelection = selection;
    }
    // ── intentionally NOT clearing _pendingSelection when empty ──
  }

  /// Clears any pending selection (call after committing or cancelling).
  void clearPendingSelection() {
    _pendingSelection = null;
  }

  /// يُستدعى من زر قائمة السياق بعد أن يُثبّت المستخدم تحديده.
  Future<void> applyPendingSelection(PdfViewerController controller) async {
    final selection = _pendingSelection;
    // Clear first so a re-tap doesn't apply the same selection twice.
    clearPendingSelection();
    if (selection == null) return;
    await handleTextSelectionChange(selection, controller);
  }
  Future<void> handleTextSelectionChange(
    PdfTextSelection selection,
    PdfViewerController controller,
  ) async {
    if (activeTool == TextMarkupTool.none) return;
    if (!selection.hasSelectedText) return;

    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) return;

    for (final range in ranges) {
      if (range.start >= range.end) continue;

      // ── Fix: ensure page data is loaded before persisting ──
      // On some pages the highlights/underlines map may not be initialized yet
      // (the page was never scrolled into view), so we load it first.
      await ensurePageLoaded(range.pageNumber);

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
      }
    }

    // إلغاء التحديد فوراً بعد تحويله إلى تمييز/تسطير دائم، بدلاً من تركه قابلاً للنسخ.
    await controller.textSelectionDelegate.clearTextSelection();
    onChanged();
  }

  /// اكتشاف اللمس على تمييز/تسطير موجود عند نقطة بالـ PDF (نظام إحداثيات الصفحة).
  /// يُستخدم عندما لا تكون أدوات التحديد نشطة (أي وضع تصفح عادي) للنقر على عنصر لتعديله.
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
      // النص لم يُحمَّل بعد لهذه الصفحة؛ نطلب تحميله الآن (سيُستخدم في الإطار التالي)
      // ignore: discarded_futures
      textCache.ensureLoaded(page);
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
