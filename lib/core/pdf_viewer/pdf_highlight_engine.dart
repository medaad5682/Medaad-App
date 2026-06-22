import 'package:pdfrx/pdfrx.dart';

import '../models/highlight_model.dart';

/// محرك حساب مستطيلات التمييز/التسطير اعتماداً على نص الصفحة الحقيقي (charRects)،
/// مع تجميع الأحرف حسب السطر لإنتاج تمييز يتبع شكل السطور بدلاً من مستطيل واحد كبير
/// يغطي كل الفراغات بين السطور.
class PdfHighlightEngine {
  /// المسافة العمودية المسموح بها بين حرفين لاعتبارهما على نفس "السطر".
  /// تُحسب كنسبة من ارتفاع أول حرف في كل مجموعة لمراعاة اختلاف حجم الخط.
  static const double _lineToleranceRatio = 0.35;

  /// يحسب قائمة مستطيلات (سطر لكل عنصر) لنطاق نص [start]-[end] في صفحة معينة.
  /// يُستخدم هذا لرسم التمييز أو التسطير بدقة على كل سطر يمر به التحديد.
  static List<PdfRect> lineRectsForRange({
    required PdfPageText pageText,
    required int start,
    required int end,
  }) {
    final clampedStart = start.clamp(0, pageText.charRects.length);
    final clampedEnd = end.clamp(0, pageText.charRects.length);
    if (clampedEnd <= clampedStart) return [];

    final rects = pageText.charRects.sublist(clampedStart, clampedEnd);
    if (rects.isEmpty) return [];

    final lines = <List<PdfRect>>[];
    List<PdfRect> currentLine = [rects.first];

    for (int i = 1; i < rects.length; i++) {
      final r = rects[i];
      final prev = currentLine.last;
      // اعتبار حرفين على نفس السطر إذا تقاربت مراكزهم عمودياً
      final prevCenterY = (prev.top + prev.bottom) / 2;
      final curCenterY = (r.top + r.bottom) / 2;
      final tolerance = (prev.height.abs() + r.height.abs()) / 2 * _lineToleranceRatio;

      if ((curCenterY - prevCenterY).abs() <= tolerance) {
        currentLine.add(r);
      } else {
        lines.add(currentLine);
        currentLine = [r];
      }
    }
    lines.add(currentLine);

    // تحويل كل سطر إلى مستطيل واحد (الحد الأدنى/الأقصى لكل بُعد)
    return lines.map((line) {
      double left = double.infinity, right = double.negativeInfinity;
      double top = double.negativeInfinity, bottom = double.infinity;
      for (final r in line) {
        if (r.left < left) left = r.left;
        if (r.right > right) right = r.right;
        if (r.top > top) top = r.top;
        if (r.bottom < bottom) bottom = r.bottom;
      }
      return PdfRect(left, top, right, bottom);
    }).toList();
  }

  /// يبحث عن أي تمييز موجود يحتوي على نقطة معينة (لإظهار قائمة تعديل/حذف عند الضغط).
  static HighlightModel? hitTestHighlight({
    required List<HighlightModel> highlights,
    required PdfPageText pageText,
    required double pdfX,
    required double pdfY,
  }) {
    for (final h in highlights.reversed) {
      final lineRects = lineRectsForRange(pageText: pageText, start: h.start, end: h.end);
      for (final r in lineRects) {
        if (r.containsXy(pdfX, pdfY, margin: 2)) return h;
      }
    }
    return null;
  }

  static UnderlineModel? hitTestUnderline({
    required List<UnderlineModel> underlines,
    required PdfPageText pageText,
    required double pdfX,
    required double pdfY,
  }) {
    for (final u in underlines.reversed) {
      final lineRects = lineRectsForRange(pageText: pageText, start: u.start, end: u.end);
      for (final r in lineRects) {
        // توسيع منطقة اللمس قليلاً تحت السطر لأن خط التسطير رفيع
        final hitRect = PdfRect(r.left, r.bottom + 4, r.right, r.bottom - 4);
        if (hitRect.containsXy(pdfX, pdfY, margin: 2)) return u;
      }
    }
    return null;
  }
}
