import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/pdf_tool_settings.dart';

/// يولّد دوال تخطيط الصفحات (layoutPages) المناسبة لكل وضع قراءة.
///
/// - [PdfReadingMode.vertical]   : تمرير عمودي متصل (افتراضي المكتبة).
/// - [PdfReadingMode.horizontal] : صفحة واحدة بالضبط في كل مرة، التمرير يساراً/يميناً،
///                                 مع توقف تلقائي عند مركز الشاشة (page snapping).
/// - [PdfReadingMode.twoPage]    : صفحتان جنباً إلى جنب مرئيتان فقط في كل مرة؛
///                                 مع توقف تلقائي عند كل زوج (page snapping).
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

  /// ScrollPhysics مناسبة لكل وضع.
  /// - عمودي: Bouncing عادي.
  /// - أفقي/صفحتان: PageScrollPhysics لضمان التوقف عند حدود كل صفحة/زوج.
  static ScrollPhysics scrollPhysicsFor(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.vertical:
        return const BouncingScrollPhysics();
      case PdfReadingMode.horizontal:
      case PdfReadingMode.twoPage:
        // PageScrollPhysics تضمن التوقف بدقة عند كل "صفحة" في ScrollView.
        // نجمعها مع AlwaysScrollableScrollPhysics حتى تعمل حتى لو المحتوى أقل من viewport.
        return const PageScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // الوضع الأفقي: كل صفحة تشغل عرض الـ Viewport بالكامل تماماً (page-snapping).
  // نجعل عرض كل صفحة = نفس العرض حتى تعمل PageScrollPhysics بشكل مثالي.
  // ──────────────────────────────────────────────────────────────────────────
  static PdfPageLayout _horizontalLayout(
      List<PdfPage> pages, PdfViewerParams params) {
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }

    // أقصى ارتفاع لتحديد ارتفاع المستند
    final maxHeight =
        pages.fold(0.0, (prev, p) => math.max(prev, p.height)) +
            params.margin * 2;

    // نستخدم أقصى عرض صفحة كـ "عرض الوحدة" حتى تتوقف PageScrollPhysics بالضبط
    final maxWidth = pages.fold(0.0, (prev, p) => math.max(prev, p.width));

    final pageLayouts = <Rect>[];
    double x = 0;

    for (final page in pages) {
      // كل صفحة تُوسَّط داخل مساحة maxWidth × maxHeight
      pageLayouts.add(
        Rect.fromLTWH(
          x + (maxWidth - page.width) / 2, // توسيط أفقي داخل الوحدة
          (maxHeight - page.height) / 2,   // توسيط عمودي
          page.width,
          page.height,
        ),
      );
      x += maxWidth; // كل صفحة تحتل maxWidth بالضبط → PageScrollPhysics تعمل بشكل صحيح
    }

    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(x, maxHeight),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // وضع الصفحتين: صفحتان جنباً إلى جنب في كل وقت (page-snapping لكل زوج).
  // كل زوج يأخذ عرض الـ Viewport بالكامل (= maxW * 2) حتى تعمل PageScrollPhysics.
  // ──────────────────────────────────────────────────────────────────────────
  static PdfPageLayout _twoPageLayout(
      List<PdfPage> pages, PdfViewerParams params) {
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }

    final maxW = pages.fold(0.0, (prev, p) => math.max(prev, p.width));
    final maxH = pages.fold(0.0, (prev, p) => math.max(prev, p.height));

    // عرض "الشاشة الافتراضية" = صفحتان جنباً إلى جنب
    final screenW = maxW * 2;
    final screenH = maxH + params.margin * 2;

    final pageLayouts = <Rect>[];

    // ── صفحة الغلاف (الصفحة الأولى منفردة) ──
    final coverPage = pages[0];
    pageLayouts.add(
      Rect.fromLTWH(
        (screenW - coverPage.width) / 2, // وسط الشاشة
        (screenH - coverPage.height) / 2,
        coverPage.width,
        coverPage.height,
      ),
    );

    // ── الأزواج: كل زوج في "شاشة" screenW × screenH ──
    int screenIndex = 1; // بدءاً من الشاشة رقم 1 (بعد الغلاف)
    for (int i = 1; i < pages.length; i += 2) {
      final screenX = screenIndex * screenW;

      final leftPage = pages[i];
      // الصفحة اليسرى تُوضع في النصف الأيسر محاذاة يميناً
      pageLayouts.add(
        Rect.fromLTWH(
          screenX + (maxW - leftPage.width), // محاذاة يمين النصف الأيسر
          (screenH - leftPage.height) / 2,
          leftPage.width,
          leftPage.height,
        ),
      );

      if (i + 1 < pages.length) {
        final rightPage = pages[i + 1];
        // الصفحة اليمنى تُوضع في النصف الأيمن محاذاة يساراً
        pageLayouts.add(
          Rect.fromLTWH(
            screenX + maxW, // بداية النصف الأيمن
            (screenH - rightPage.height) / 2,
            rightPage.width,
            rightPage.height,
          ),
        );
      }

      screenIndex++;
    }

    final totalScreens = 1 + ((pages.length - 1) / 2).ceil();
    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(totalScreens * screenW, screenH),
    );
  }
}
