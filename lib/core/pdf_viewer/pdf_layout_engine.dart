import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/pdf_tool_settings.dart';

/// يولّد دوال تخطيط الصفحات (layoutPages) المناسبة لكل وضع قراءة.
///
/// - [PdfReadingMode.vertical]   : تمرير عمودي متصل (افتراضي المكتبة).
/// - [PdfReadingMode.horizontal] : صفحة واحدة بالضبط في كل مرة، التمرير يساراً/يميناً،
///                                 مع توقف تلقائي عند مركز الشاشة (page snapping).
///                                 الحركة العمودية مُعطَّلة كلياً.
class PdfLayoutEngine {
  /// يبني [PdfPageLayoutFunction]? المناسبة لوضع القراءة.
  static PdfPageLayoutFunction? layoutFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.vertical:
        return null;
      case PdfReadingMode.horizontal:
        return _horizontalLayout;
    }
  }

  static PdfPageAnchor anchorStartFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.horizontal:
        return PdfPageAnchor.left;
      case PdfReadingMode.vertical:
        return PdfPageAnchor.top;
    }
  }

  static PdfPageAnchor anchorEndFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.horizontal:
        return PdfPageAnchor.right;
      case PdfReadingMode.vertical:
        return PdfPageAnchor.bottom;
    }
  }

  static bool scrollHorizontallyByMouseWheelFor(PdfReadingMode mode) {
    return mode == PdfReadingMode.horizontal;
  }

  /// ScrollPhysics مناسبة لكل وضع.
  /// - عمودي: Bouncing عادي.
  /// - أفقي: PageScrollPhysics لضمان التوقف عند حدود كل صفحة.
  static ScrollPhysics scrollPhysicsFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.vertical:
        return const BouncingScrollPhysics();
      case PdfReadingMode.horizontal:
        return const PageScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // الوضع الأفقي: كل صفحة تشغل عرض الـ Viewport بالكامل تماماً (page-snapping).
  // الارتفاع يُحدَّد بدقة لمنع التمرير العمودي كلياً: documentSize.height == viewport height.
  // نستخدم PdfPage.height/width ratio لتحديد أنسب ارتفاع للمستند.
  // ──────────────────────────────────────────────────────────────────────────
  static PdfPageLayout _horizontalLayout(
      List<PdfPage> pages, PdfViewerParams params) {
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }

    // نحسب أقصى ارتفاع طبيعي وأقصى عرض طبيعي لصفحات المستند
    final maxPageH = pages.fold(0.0, (prev, p) => math.max(prev, p.height));
    final maxPageW = pages.fold(0.0, (prev, p) => math.max(prev, p.width));

    // ارتفاع المستند = ارتفاع أكبر صفحة + هامش من كلا الجانبين
    // هذا يجعل documentSize.height مساوياً لحجم الـ viewport تقريباً مما يمنع التمرير العمودي
    final docHeight = maxPageH + params.margin * 2;

    final pageLayouts = <Rect>[];
    double x = 0;

    for (final page in pages) {
      // كل صفحة تُوسَّط داخل مساحة maxPageW × docHeight
      pageLayouts.add(
        Rect.fromLTWH(
          x + (maxPageW - page.width) / 2, // توسيط أفقي داخل الوحدة
          (docHeight - page.height) / 2,   // توسيط عمودي
          page.width,
          page.height,
        ),
      );
      x += maxPageW; // كل صفحة تحتل maxPageW بالضبط → PageScrollPhysics تعمل بشكل صحيح
    }

    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(x, docHeight),
    );
  }
}
