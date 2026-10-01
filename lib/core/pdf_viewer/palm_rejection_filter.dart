import 'package:flutter/gestures.dart';

/// منطق "رفض راحة اليد" (Palm Rejection).
///
/// عند التفعيل: يُسمح فقط لإدخال القلم (stylus/invertedStylus) أو الفأرة (للاختبار على
/// الحاسوب) بالتعامل مع أدوات الرسم والعناصر المُضافة (قلم، أشكال، صور، ملاحظات...)،
/// أما لمسات الإصبع/راحة اليد فلا تدخل هذه الإيماءات أصلاً، وتمرّ للـ PDF الذي تحتها
/// فيستمر الإصبع في التمرير والتكبير بشكل طبيعي.
///
/// عند التعطيل: يعمل اللمس بشكل طبيعي تماماً كما كان قبل إضافة هذه الميزة.
///
/// ── الفكرة الجوهرية للإصلاح ──
/// سابقاً كان الفحص يتم داخل دوال onPanStart/onPanUpdate، أي *بعد* أن يكون Flutter قد
/// منح الإيماءة للطبقة. الآن نمرّر [supportedDevices] مباشرة إلى GestureDetector، فلا
/// يقبل الـ recognizer لمسة الإصبع من الأساس ولا يدخل بها "سباق الإيماءات".
class PalmRejectionFilter {
  bool enabled;

  PalmRejectionFilter({this.enabled = false});

  /// أنواع المؤشرات المسموح لها عند تفعيل الرفض.
  static const Set<PointerDeviceKind> _penKinds = {
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.mouse, // يسمح بالاختبار من الحاسوب/الفأرة
  };

  /// تُمرَّر مباشرة إلى `GestureDetector(supportedDevices: ...)`.
  /// - الرفض معطّل  → null (كل الأنواع مسموحة، سلوك Flutter الافتراضي).
  /// - الرفض مفعّل  → قلم/ممحاة القلم/فأرة فقط، ولا تصل لمسة الإصبع للـ recognizer.
  Set<PointerDeviceKind>? get supportedDevices => enabled ? _penKinds : null;

  /// هل هذا النوع قلم فعلي (Apple Pencil / S Pen ...)؟
  static bool isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// هل يُسمح لهذا النوع من المؤشرات بالتفاعل الآن؟
  bool isAllowed(PointerDeviceKind? kind) {
    if (!enabled) return true; // الرفض غير مفعّل: كل أنواع اللمس مسموحة كالعادة
    if (kind == null) {
      // لا توجد معلومة عن نوع المؤشر؛ نتعامل معه كلمسة عادية (نرفضها لمنع الأخطاء).
      return false;
    }
    return _penKinds.contains(kind);
  }
}
