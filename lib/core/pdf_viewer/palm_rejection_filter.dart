import 'package:flutter/gestures.dart';

/// منطق "رفض راحة اليد" (Palm Rejection).
///
/// عند التفعيل: يُسمح فقط لإدخال القلم (stylus/invertedStylus) أو الفأرة (للاختبار على
/// الحاسوب) بتفعيل أدوات الرسم (القلم، الهايلايتر، الأشكال، إلخ)، ويتم تجاهل لمسات
/// الأصابع تماماً أثناء الرسم لمنع راحة اليد من ترك خطوط غير مقصودة.
///
/// عند التعطيل: يعمل اللمس بشكل طبيعي تماماً كما كان قبل إضافة هذه الميزة.
///
/// ── إضافة (تثبيت الصفحة أثناء الكتابة) ─────────────────────────────────────
/// الفلترة وحدها (قبول/رفض داخل callbacks) لا تكفي: راحة اليد تبقى "مؤشراً"
/// حياً داخل نظام الإيماءات في Flutter، فتستطيع تحريك الصفحة أو تكبيرها حتى لو
/// لم ترسم شيئاً. لذلك يتتبّع هذا الصنف أيضاً "قرب القلم" (hover / ملامسة /
/// ثوانٍ قليلة بعد الرفع)، وطبقة [PalmGuardLayer] تستخدمه لإلغاء أي لمسة إصبع
/// تصل أثناء ذلك على مستوى المؤشر نفسه (PointerCancel) قبل أن يراها عارض
/// الـ PDF. أي أنّ اللمسة تُسقَط من الأساس بدل أن تُفلتَر لاحقاً.
class PalmRejectionFilter {
  bool enabled;

  PalmRejectionFilter({this.enabled = false});

  /// المدة التي يُعتبر فيها القلم "قريباً" بعد آخر حدث منه (hover/ملامسة/رفع).
  /// تغطي رفع القلم بين الكلمات وبقاء الكف على الشاشة. بعدها تعود لمسة
  /// الإصبع لتحريك/تكبير الصفحة بشكل طبيعي.
  static const Duration penHold = Duration(milliseconds: 900);

  /// أقصى مدة نثق فيها بأن القلم ما زال "ملامساً" دون أي حدث جديد منه
  /// (حماية من حالة عالقة إن فُقد حدث الرفع لأي سبب).
  static const Duration _maxSilentContact = Duration(seconds: 4);

  final Stopwatch _clock = Stopwatch()..start();
  int _lastPenMs = -1000000;
  final Set<int> _penPointers = <int>{};
  final Set<int> _restingTouches = <int>{};

  // ───────────────────────── تصنيف المؤشرات ─────────────────────────

  /// قلم حقيقي (طرف القلم أو الممحاة الخلفية).
  static bool isPen(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// **وضع الاختبار**: عندما يكون true تُعامَل الفأرة كقلم في "حارس راحة اليد"
  /// أيضاً: حركتها فوق الصفحة (hover) وضغطها ورفعها تُسجَّل كأحداث قلم، فتُلغى لمسات
  /// الأصابع القريبة منها وتُلغى اللمسات المستقرّة عند ضغطها، ويسري "قرب القلم"
  /// 0.9 ثانية بعد آخر حدث. هكذا يمكن اختبار سيناريوهات القلم/الكف بفأرة حقيقية
  /// موصولة بجهاز أندرويد (الفأرة = قلم، الإصبع = كف).
  /// ⚠️ اجعلها false قبل الإصدار للمستخدمين: فأرة موصولة مع لمس ستمنع لمس الأصابع
  /// لحظات بعد كل حركة للفأرة أثناء الرسم.
  static bool mouseActsAsPen = true;

  /// قلم حقيقي، أو فأرة عندما يكون [mouseActsAsPen] مفعّلاً.
  static bool isPenLike(PointerDeviceKind kind) =>
      isPen(kind) || (mouseActsAsPen && kind == PointerDeviceKind.mouse);

  /// مؤشر دقيق: قلم أو فأرة (الفأرة للاختبار على الحاسوب).
  static bool isPrecise(PointerDeviceKind kind) =>
      isPen(kind) || kind == PointerDeviceKind.mouse;

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

  // ───────────────────────── قرب القلم ─────────────────────────

  /// يُستدعى لكل حدث من القلم (hover / down / move / up / cancel).
  void notePen(PointerEvent event) {
    _lastPenMs = _clock.elapsedMilliseconds;
    if (event is PointerDownEvent) {
      _penPointers.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _penPointers.remove(event.pointer);
    }
  }

  /// هل القلم قريب من الشاشة الآن (ملامس، أو في نطاق الـ hover، أو رُفع للتو)؟
  bool get penNearby {
    final silentMs = _clock.elapsedMilliseconds - _lastPenMs;
    if (_penPointers.isNotEmpty &&
        silentMs < _maxSilentContact.inMilliseconds) {
      return true;
    }
    return silentMs < penHold.inMilliseconds;
  }

  /// هل يجب إسقاط لمسة (إصبع/كف) وصلت الآن؟
  bool shouldDropTouch(PointerDeviceKind kind) =>
      enabled && !isPrecise(kind) && penNearby;

  // ───────────────── اللمسات الجارية (لإلغاء الكف المستقرّ مسبقاً) ─────────────────

  void trackTouch(int pointer) => _restingTouches.add(pointer);

  /// ينهي تتبّع مؤشر **بالمعرّف** أياً كان نوعه. ضروري لأن حدث الإلغاء الذي
  /// يولّده `GestureBinding.cancelPointer` نوعه touch دائماً حتى لو كان المؤشر
  /// المُلغى قلماً؛ فلو اعتمدنا النوع لبقي معرّف القلم عالقاً في القائمة وطال
  /// "قرب القلم" من 0.9 ثانية إلى 4 ثوانٍ لبقية الجلسة.
  void endPointer(int pointer) {
    _penPointers.remove(pointer);
    _restingTouches.remove(pointer);
  }

  void untrack(int pointer) => _restingTouches.remove(pointer);

  /// هل توجد لمسات إصبع/كف جارية بدأت قبل أن يصبح القلم قريباً؟
  /// (اللمسات التي تصل والقلم قريب تُلغى فور وصولها ولا تُتتبَّع أصلاً، فلا يبقى
  /// في السجل إلا ما بدأ قبل ظهور القلم.)
  bool get hasRestingTouches => _restingTouches.isNotEmpty;

  /// يعيد اللمسات الموضوعة حالياً على الشاشة ويفرّغ السجل (تُلغى عند ظهور القلم:
  /// أول hover له، أو ملامسته للشاشة).
  List<int> takeRestingTouches() {
    final list = _restingTouches.toList();
    _restingTouches.clear();
    return list;
  }

  void reset() {
    _penPointers.clear();
    _restingTouches.clear();
    _lastPenMs = -1000000;
  }
}
