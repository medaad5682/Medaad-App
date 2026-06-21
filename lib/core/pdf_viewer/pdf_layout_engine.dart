import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/pdf_tool_settings.dart';

/// يولّد دوال تخطيط الصفحات (layoutPages) المناسبة لكل وضع قراءة.
///
/// - [PdfReadingMode.vertical]   : تمرير عمودي متصل (افتراضي المكتبة).
/// - [PdfReadingMode.horizontal] : صفحة واحدة بالضبط في كل مرة، التمرير يساراً/يميناً،
///                                 بدون توسيط تلقائي للصفحة التالية.
/// - [PdfReadingMode.twoPage]    : صفحتان جنباً إلى جنب مرئيتان فقط في كل مرة؛
///                                 الصفحات الأخرى خارج نطاق العرض.
class PdfLayoutEngine {
  /// يبني [PdfPageLayoutFunction]? المناسبة لوضع القراءة.
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

  static bool scrollHorizontallyByMouseWheelFor(PdfReadingMode mode) {
    return mode == PdfReadingMode.horizontal || mode == PdfReadingMode.twoPage;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // الوضع الأفقي: كل صفحة تشغل عرض الـ Viewport بالكامل.
  // الصفحات تُوضع بجانب بعضها بدون فجوة بينها (margin = 0)
  // حتى يكون التمرير بالضبط من صفحة لصفحة بدون توسيط تلقائي.
  // ──────────────────────────────────────────────────────────────────────────
  static PdfPageLayout _horizontalLayout(
      List<PdfPage> pages, PdfViewerParams params) {
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }

    // نستخدم أقصى ارتفاع صفحة لتحديد ارتفاع المستند (مع هامش رأسي بسيط)
    final maxHeight =
        pages.fold(0.0, (prev, p) => math.max(prev, p.height)) +
            params.margin * 2;

    final pageLayouts = <Rect>[];
    double x = 0; // لا هامش أفقي بين الصفحات

    for (final page in pages) {
      pageLayouts.add(
        Rect.fromLTWH(
          x,
          (maxHeight - page.height) / 2, // توسيط عمودي فقط
          page.width,
          page.height,
        ),
      );
      x += page.width; // الصفحة التالية تبدأ مباشرة بعد الحالية
    }

    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(x, maxHeight),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // وضع الصفحتين: صفحتان مرئيتان فقط في كل وقت، التمرير يُخفي الصفحات الأخرى.
  // كل زوج يأخذ الـ Viewport عرضاً وارتفاعاً، فلا تظهر صفحات قبل/بعد الزوج
  // الحالي حتى يتمرر المستخدم يساراً أو يميناً.
  // ──────────────────────────────────────────────────────────────────────────
  static PdfPageLayout _twoPageLayout(
      List<PdfPage> pages, PdfViewerParams params) {
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }

    // أقصى عرض وارتفاع لصفحة واحدة (نفترض صفحات A4 موحدة نسبياً)
    final maxW = pages.fold(0.0, (prev, p) => math.max(prev, p.width));
    final maxH = pages.fold(0.0, (prev, p) => math.max(prev, p.height));

    // عرض "الشاشة الافتراضية" = صفحتان جنباً إلى جنب
    final screenW = maxW * 2;
    final screenH = maxH + params.margin * 2;

    final pageLayouts = <Rect>[];
    // الصفحة الأولى تُعرض كغلاف منفرد في المنتصف
    // بقية الصفحات في أزواج (يسار / يمين)
    const coverOffset = 1;
    // كل "شاشة" تبدأ عند مضاعف screenW
    // صفحة الغلاف: screen index 0
    // الزوج الأول (ص2+ص3): screen index 1
    // الزوج الثاني (ص4+ص5): screen index 2  ...

    // -- صفحة الغلاف --
    final coverPage = pages[0];
    pageLayouts.add(
      Rect.fromLTWH(
        (screenW - coverPage.width) / 2,           // وسط الشاشة
        (screenH - coverPage.height) / 2,
        coverPage.width,
        coverPage.height,
      ),
    );

    // -- الأزواج --
    for (int i = 1; i < pages.length; i += 2) {
      final pos = i + coverOffset; // مؤشر الشاشة
      final screenIndex = (pos / 2).ceil(); // 1-based screen index
      final screenX = screenIndex * screenW;

      final leftPage = pages[i];
      pageLayouts.add(
        Rect.fromLTWH(
          screenX + (maxW - leftPage.width),        // محاذاة يمين المساحة اليسرى
          (screenH - leftPage.height) / 2,
          leftPage.width,
          leftPage.height,
        ),
      );

      if (i + 1 < pages.length) {
        final rightPage = pages[i + 1];
        pageLayouts.add(
          Rect.fromLTWH(
            screenX + maxW,                          // بداية المساحة اليمنى
            (screenH - rightPage.height) / 2,
            rightPage.width,
            rightPage.height,
          ),
        );
      }
    }

    // عدد "الشاشات" = 1 (غلاف) + (pages.length - 1 / 2) أزواج
    final totalScreens = 1 + ((pages.length - 1) / 2).ceil();
    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(totalScreens * screenW, screenH),
    );
  }
}
