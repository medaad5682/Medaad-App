import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// يوفر إعدادات تخطيط الصفحات (تمرير عمودي دائماً).
///
/// ── Fix: صفحة أعرض من البقية (مثلاً صفحة رقم 50) كانت تتسبب في أن
/// `pdfrx` يبني قماش (canvas) مشترك للمستند بعرض أوسع صفحة فيه، فتظهر
/// الصفحة الأولى (والصفحات العادية) مُصغّرة جداً مع حواف سوداء، ويصبح
/// التكبير/التصغير غير مستقر (تتحرك الصفحة يميناً ويساراً عند الزوم).
///
/// الحل: أي صفحة أعرض بشكل ملحوظ (>15%) من "العرض النموذجي" للمستند
/// (median لعرض كل الصفحات) تُصغَّر فقط لأغراض التخطيط (layout) مع
/// الحفاظ التام على نسبة العرض إلى الارتفاع (aspect ratio) — أي لا
/// يوجد أي قص (cropping) أو تشويه، فقط عرض الصفحة بحجم أصغر ضمن نفس
/// عمود الصفحات، ويمكن للمستخدم تكبيرها يدوياً لرؤية التفاصيل الكاملة
/// بدقة أعلى (pdfrx يعيد رسمها (re-rasterize) بدقة كاملة عند التكبير).
class PdfLayoutEngine {
  /// نسبة اعتبار الصفحة "أوسع من العادي" (outlier) مقارنة بالعرض
  /// النموذجي للمستند. 1.15 تعني: أوسع بأكثر من 15%.
  static const double _outlierFactor = 1.15;

  static PdfPageLayoutFunction? get layout => (pages, params) {
        if (pages.isEmpty) {
          return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
        }

        // العرض "النموذجي" = median لعرض كل الصفحات، بدل استخدام أوسع
        // صفحة مباشرة (وهو ما يفعله pdfrx افتراضياً ويسبب المشكلة).
        final widths = pages.map((p) => p.width).toList()..sort();
        final typicalWidth = widths[widths.length ~/ 2];

        final rects = <Rect>[];
        double y = params.margin;
        double maxW = 0;

        for (final page in pages) {
          var w = page.width;
          var h = page.height;

          if (w > typicalWidth * _outlierFactor) {
            // تصغير للتخطيط فقط، مع الحفاظ على نسبة الأبعاد كاملة
            // (لا قص ولا تشويه — فقط عرض أصغر للصفحة كلها).
            final scale = typicalWidth / w;
            w = typicalWidth;
            h = h * scale;
          }

          if (w > maxW) maxW = w;
          rects.add(Rect.fromLTWH(0, y, w, h));
          y += h + params.margin;
        }

        // توسيط كل صفحة أفقياً ضمن عرض المستند النهائي (الذي أصبح الآن
        // مبنياً على العرض النموذجي وليس أوسع صفحة استثنائية).
        final documentWidth = maxW + params.margin * 2;
        for (var i = 0; i < rects.length; i++) {
          final r = rects[i];
          rects[i] = Rect.fromLTWH(
            (documentWidth - r.width) / 2,
            r.top,
            r.width,
            r.height,
          );
        }

        return PdfPageLayout(
          pageLayouts: rects,
          documentSize: Size(documentWidth, y),
        );
      };

  static PdfPageAnchor get anchorStart => PdfPageAnchor.top;

  static PdfPageAnchor get anchorEnd => PdfPageAnchor.bottom;

  static bool get scrollHorizontallyByMouseWheel => false;

  static ScrollPhysics get scrollPhysics => const BouncingScrollPhysics();
}
