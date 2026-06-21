import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/pdf_tool_settings.dart';

/// يولّد دوال تخطيط الصفحات (layoutPages) المناسبة لكل وضع قراءة،
/// بالإضافة إلى إعدادات الـ Anchor والتمرير المرافقة لكل وضع.
///
/// - [PdfReadingMode.vertical]: التخطيط الافتراضي للمكتبة (null) - تمرير عمودي صفحة تلو الأخرى.
/// - [PdfReadingMode.horizontal]: كل الصفحات بجانب بعضها أفقياً، تمرير بالسحب يمين/يسار.
/// - [PdfReadingMode.twoPage]: صفحتان جنباً إلى جنب (يمين/يسار)، تمرير عمودي بين كل "فرد" من الصفحات.
class PdfLayoutEngine {
  /// يبني [PdfPageLayoutFunction]? المناسبة لوضع القراءة. إرجاع null يعني استخدام
  /// التخطيط الافتراضي للمكتبة (عمودي).
  static PdfPageLayoutFunction? layoutFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.vertical:
        return null;
      case PdfReadingMode.horizontal:
        return _horizontalLayout;
      case PdfReadingMode.twoPage:
        return _twoPageLayout;
    }
  }

  /// نقطة الالتقام (anchor) المناسبة للبداية حسب وضع القراءة.
  static PdfPageAnchor anchorStartFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.horizontal:
      case PdfReadingMode.twoPage:
        return PdfPageAnchor.left;
      case PdfReadingMode.vertical:
        return PdfPageAnchor.top;
    }
  }

  static PdfPageAnchor anchorEndFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.horizontal:
      case PdfReadingMode.twoPage:
        return PdfPageAnchor.right;
      case PdfReadingMode.vertical:
        return PdfPageAnchor.bottom;
    }
  }

  /// هل يجب أن تتم عملية التمرير بعجلة الفأرة أفقياً (لأجهزة الديسكتوب فقط؛ لا تأثير على اللمس)
  static bool scrollHorizontallyByMouseWheelFor(PdfReadingMode mode) {
    return mode == PdfReadingMode.horizontal || mode == PdfReadingMode.twoPage;
  }

  // -------------------------- التخطيط الأفقي --------------------------
  // كل الصفحات توضع بجانب بعضها في خط واحد أفقي، بمسافة [margin] بينها.
  static PdfPageLayout _horizontalLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height = pages.fold(0.0, (prev, page) => math.max(prev, page.height)) + params.margin * 2;
    final pageLayouts = <Rect>[];
    double x = params.margin;
    for (final page in pages) {
      pageLayouts.add(
        Rect.fromLTWH(
          x,
          (height - page.height) / 2, // توسيط عمودي للصفحات ذات الأبعاد المختلفة
          page.width,
          page.height,
        ),
      );
      x += page.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));
  }

  // -------------------------- التخطيط ثنائي الصفحة (جنباً إلى جنب) --------------------------
  // تُعرض الصفحات في أزواج (يسار/يمين) بترتيب من اليسار إلى اليمين،
  // مع استخدام أول صفحة كصفحة غلاف منفردة قبل بدء الأزواج (لمحاذاة الصفحات الزوجية/الفردية كما في كتاب مطبوع).
  static PdfPageLayout _twoPageLayout(List<PdfPage> pages, PdfViewerParams params) {
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }

    final width = pages.fold(0.0, (prev, page) => math.max(prev, page.width));
    final pageLayouts = <Rect>[];
    const coverOffset = 1; // الصفحة الأولى تُعرض منفردة في المنتصف كغلاف

    double y = params.margin;
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pos = i + coverOffset;
      final isLeft = (pos & 1) == 0;

      final otherSide = (pos ^ 1) - coverOffset;
      final rowHeight = (otherSide >= 0 && otherSide < pages.length)
          ? math.max(page.height, pages[otherSide].height)
          : page.height;

      double left;
      if (i == 0) {
        // صفحة الغلاف: تُوسَّط على عرض الصفحتين معاً بدلاً من الالتصاق بجانب واحد
        left = params.margin + width + params.margin / 2 - page.width / 2;
      } else {
        left = isLeft ? (params.margin + width - page.width) : (params.margin * 2 + width);
      }

      pageLayouts.add(
        Rect.fromLTWH(
          left,
          y + (rowHeight - page.height) / 2,
          page.width,
          page.height,
        ),
      );

      // الانتقال للصفّ التالي بعد إغلاق الزوج (أو بعد صفحة الغلاف المنفردة)
      if (i == 0 || pos.isOdd || i + 1 == pages.length) {
        y += rowHeight + params.margin;
      }
    }

    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size((params.margin + width) * 2 + params.margin, y),
    );
  }
}
