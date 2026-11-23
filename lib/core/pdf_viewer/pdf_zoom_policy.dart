import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:pdfrx/pdfrx.dart';

/// سياسة التكبير/التصغير لعارض الـ PDF: **حدّ التصغير نسبي لعرض الصفحة**
/// (coverScale) بدل رقم مطلق ثابت.
///
/// ── المشكلة التي يحلّها ──────────────────────────────────────────────────
/// كان `minScale = 0.25` مطلقاً (بوحدات نقاط الـ PDF). العارض يفتح على "عرض
/// الصفحة" (coverScale = عرض الشاشة ÷ عرض المستند بالنقاط). في الملفات ذات
/// الصفحات الكبيرة بالنقاط (سكان، مقاسات كبيرة، ...) يكون coverScale أقل من
/// 0.25؛ فيفتح العارض صحيحاً ثم، عند رفع الأصابع بعد أي قرص (pinch)، يقصّ pdfrx
/// الزوم إلى الحدّ الأدنى 0.25 — أي إلى زوم أكبر من زوم الفتح — فتبدو الصفحة
/// مكبّرة وتعود غصباً إلى "وضع ثابت" ولا يمكن تصغيرها. الملفات العادية
/// (coverScale > 0.25) لا تتأثر، ولذلك كانت المشكلة تظهر في ملفات دون غيرها.
///
/// ── الحل ─────────────────────────────────────────────────────────────────
/// `minScale = coverScale × minScaleFactor`. أي أن لكل ملف حدّ تصغير يتناسب مع
/// حجم صفحاته، فيبقى التصغير أكثر من عرض الصفحة ممكناً (الميزة المقصودة) في كل
/// الملفات، ولا يتجاوز حدّ التصغير زوم الفتح أبداً.
///
/// الباقي (الزوم الابتدائي، الحفاظ على الموضع عند تغيّر الحجم/الدوران، عتبة
/// الرسم...) يُفوَّض كما هو إلى [PdfViewerSizeDelegateLegacy].
///
/// ⚠️ لا يمكن استخدام `PdfViewerParams.minScale/maxScale/
/// useAlternativeFitScaleAsMinScale` مع `sizeDelegateProvider` (assert في pdfrx)،
/// لذلك يُضبط `maxScale` هنا.
class RelativeMinScaleSizeDelegateProvider
    extends PdfViewerSizeDelegateProvider {
  const RelativeMinScaleSizeDelegateProvider({
    this.maxScale = 8.0,
    this.minScaleFactor = 0.35,
  }) : assert(minScaleFactor > 0 && minScaleFactor <= 1);

  /// أقصى تكبير مسموح.
  final double maxScale;

  /// حدّ التصغير كنسبة من زوم الفتح (عرض الصفحة). 1.0 = لا تصغير أقل من عرض
  /// الصفحة. 0.35 ≈ السلوك السابق على الهاتف (0.25 ÷ ~0.67)، لكن نسبي لكل ملف.
  /// صغّره للسماح بتصغير أكثر، كبّره للسماح بتصغير أقل.
  final double minScaleFactor;

  @override
  PdfViewerSizeDelegate create() => _RelativeMinScaleSizeDelegate(
        PdfViewerSizeDelegateProviderLegacy(
          maxScale: maxScale,
          // لن يُستخدم: نستبدل minScale في calculateMetrics أدناه.
          useAlternativeFitScaleAsMinScale: false,
        ).create(),
        minScaleFactor,
      );

  // مهم: pdfrx يقارن المزوّد بين إعادة بناء وأخرى؛ بدون == صحيح يُعاد إنشاء
  // الـ delegate (وتُفقَد حالته) مع كل setState في الشاشة.
  @override
  bool operator ==(Object other) =>
      other is RelativeMinScaleSizeDelegateProvider &&
      other.maxScale == maxScale &&
      other.minScaleFactor == minScaleFactor;

  @override
  int get hashCode =>
      Object.hash(RelativeMinScaleSizeDelegateProvider, maxScale, minScaleFactor);
}

class _RelativeMinScaleSizeDelegate implements PdfViewerSizeDelegate {
  _RelativeMinScaleSizeDelegate(this._inner, this._minScaleFactor);

  final PdfViewerSizeDelegate _inner;
  final double _minScaleFactor;

  @override
  void init(PdfViewerController controller) => _inner.init(controller);

  @override
  void dispose() => _inner.dispose();

  @override
  double get onePassRenderingScaleThreshold =>
      _inner.onePassRenderingScaleThreshold;

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    final m = _inner.calculateMetrics(
      viewSize: viewSize,
      layout: layout,
      pageNumber: pageNumber,
      pageMargin: pageMargin,
      boundaryMargin: boundaryMargin,
    );
    return PdfViewerLayoutMetrics(
      // نسبي لزوم الفتح، ولا يتجاوز maxScale أبداً (pdfrx يفترض min <= max).
      minScale: math.min(m.coverScale * _minScaleFactor, m.maxScale),
      maxScale: m.maxScale,
      coverScale: m.coverScale,
      alternativeFitScale: m.alternativeFitScale,
    );
  }

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) =>
      _inner.onLayoutInitialized(
        state: state,
        initialPageNumber: initialPageNumber,
        coverScale: coverScale,
        alternativeFitScale: alternativeFitScale,
        layout: layout,
        document: document,
      );

  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) =>
      _inner.onLayoutUpdate(
        oldState: oldState,
        newState: newState,
        currentZoom: currentZoom,
        oldVisibleRect: oldVisibleRect,
        anchorPageNumber: anchorPageNumber,
        isLayoutChanged: isLayoutChanged,
        isViewSizeChanged: isViewSizeChanged,
      );
}
