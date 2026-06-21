import 'package:flutter/gestures.dart';

/// منطق "رفض راحة اليد" (Palm Rejection).
///
/// عند التفعيل: يُسمح فقط لإدخال القلم (stylus/invertedStylus) أو الفأرة (للاختبار على
/// الحاسوب) بتفعيل أدوات الرسم (القلم، الهايلايتر، الأشكال، إلخ)، ويتم تجاهل لمسات
/// الأصابع تماماً أثناء الرسم لمنع راحة اليد من ترك خطوط غير مقصودة.
///
/// عند التعطيل: يعمل اللمس بشكل طبيعي تماماً كما كان قبل إضافة هذه الميزة.
class PalmRejectionFilter {
  bool enabled;

  PalmRejectionFilter({this.enabled = false});

  /// هل يُسمح لهذا النوع من المؤشرات بالرسم الآن؟
  bool isAllowed(PointerDeviceKind? kind) {
    if (!enabled) return true; // الرفض غير مفعّل: كل أنواع اللمس مسموحة كالعادة
    if (kind == null) {
      // لا توجد معلومة عن نوع المؤشر؛ نتعامل معه كلمسة عادية (نرفضها لمنع الأخطاء).
      return false;
    }
    switch (kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.mouse: // يسمح بالاختبار من الحاسوب/الفأرة
        return true;
      case PointerDeviceKind.touch:
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
        return false;
    }
  }
}
