import 'dart:async' show scheduleMicrotask;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'palm_rejection_filter.dart';

typedef InkPointCallback = void Function(PointerEvent event);

/// مُتعرِّف إيماءات للحبر الحر يعمل على مستوى **المؤشر الواحد** بدل مستوى
/// "الإيماءة" كما يفعل [PanGestureRecognizer].
///
/// لماذا لا نستخدم onPanStart/onPanUpdate؟
///  1. الـ Pan لا يبدأ إلا بعد تجاوز مسافة "slop" (36px افتراضياً للقلم أيضاً)،
///     فيضيع أول جزء من كل خط ويظهر الحبر متأخراً عن رأس القلم.
///  2. الـ Pan يعامل كل الأصابع كسحبة واحدة: عند نزول إصبع/كف أثناء الكتابة
///     يستلم هو الحدث ويتوقف القلم، وعند رفعه يُوصَل آخر نقطة بنقطة القلم الجديدة
///     بخط مستقيم. كما أن onPanEnd لا يُستدعى حتى يُرفع آخر مؤشر (الكف!).
///
/// سلوك هذا المُتعرِّف:
///  • القلم/الفأرة: يفوز بالساحة فوراً عند اللمس (بدون أي slop) فيبدأ الحبر من
///    أول نقطة، ولا يستطيع عارض الـ PDF (تمرير/تكبير) انتزاع هذا المؤشر.
///  • الإصبع (عندما يكون رفض راحة اليد معطّلاً): ننتظر حركة صغيرة (≈8px) حتى لا
///    نمنع التكبير بإصبعين؛ فإن نزل إصبع ثانٍ قبل ذلك نتراجع فوراً ونترك الإيماءة
///    للعارض. أما **النقرة القصيرة بلا حركة** فتُرسَم نقطة (مثل القلم) عند رفع
///    الإصبع، لأن الرفع نفسه هو الدليل على أنها لم تكن بداية تمرير أو تكبير.
///  • مؤشر واحد فقط لكل خط: أي مؤشر آخر (إصبع أو قلم) يصل أثناء الخط يُسقَط (لا
///    يحرّك الصفحة ولا يضيف نقاطاً).
///  • بدء/نهاية/إلغاء الخط تخص **نفس المؤشر** الذي بدأه، لا آخر مؤشر على الشاشة.
class InkPointerRecognizer extends OneSequenceGestureRecognizer {
  InkPointerRecognizer({
    super.debugOwner,
    super.supportedDevices,
    this.touchClaimSlop = 8.0,
  });

  /// المسافة (بالبكسل المنطقي) التي يجب أن يتحركها الإصبع قبل أن نعتبره رسماً.
  final double touchClaimSlop;

  /// هل تُرسم نقطة عند نقرة إصبع قصيرة بلا حركة؟ (القلم/الفأرة يرسمان نقطة دائماً).
  /// لا أثر لهذا الخيار عندما يكون رفض راحة اليد مفعّلاً لأن اللمس مرفوض أصلاً.
  bool tapMakesDot = true;

  /// سياسة رفض راحة اليد: هل يُسمح لهذا النوع من المؤشرات بالرسم؟
  bool Function(PointerDeviceKind kind) allowKind = _allowAll;
  static bool _allowAll(PointerDeviceKind kind) => true;

  InkPointCallback? onStart;
  InkPointCallback? onMove;
  InkPointCallback? onEnd;

  /// إلغاء من النظام (PointerCancel) أو إزالة الودجت أثناء الخط. المالك يقرر
  /// ما يفعله بالنقاط المرسومة (نحن نثبّتها حتى لا يضيع عمل المستخدم).
  VoidCallback? onCancel;

  int? _pointer;
  bool _eager = false;
  bool _claimed = false;
  PointerDownEvent? _down;
  final List<PointerMoveEvent> _pending = <PointerMoveEvent>[];

  @override
  void addPointer(PointerDownEvent event) {
    // قلم/فأرة يصل بينما إصبع ما زال "مرشّحاً" (لمس لم يتحرك بعد ليصبح رسماً، مثل
    // يد مستريحة): القلم أولى. كنا نبقى "مشغولين" بالإصبع فلا نحسم القلم، فيتسرب
    // إلى عارض الـ PDF ويحرّك الصفحة بدل أن يكتب. نتخلى عن مرشّح الإصبع ونُسقطه
    // (حتى لا يحرّك الصفحة هو الآخر) ثم نأخذ القلم. أما لو كان الإصبع قد بدأ خطاً
    // فعلاً فلا نقاطعه (راجع handleNonAllowedPointer).
    final pending = _pointer;
    if (pending != null &&
        !_claimed &&
        PalmRejectionFilter.isPrecise(event.kind)) {
      resolvePointer(pending, GestureDisposition.rejected);
      GestureBinding.instance.cancelPointer(pending);
    }
    super.addPointer(event);
  }

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_pointer != null) return false; // خط واحد في المرة
    if (!allowKind(event.kind)) return false; // رفض راحة اليد
    return super.isPointerAllowed(event);
  }

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    final current = _pointer;
    if (current == null) return; // مؤشر مرفوض بسياسة الكف: ليس شأننا
    if (_claimed) {
      // خط جارٍ: أي مؤشر آخر يُسقَط تماماً فلا يحرّك الصفحة ولا يعبث بالخط.
      // (كان القلم يُستثنى سابقاً فيتسرّب إلى عارض الـ PDF ويحرّك الصفحة.)
      GestureBinding.instance.cancelPointer(event.pointer);
    } else {
      // إصبع ثانٍ نزل قبل أن نحسم: المستخدم يقرص للتكبير/يتنقل، لا يرسم.
      resolvePointer(current, GestureDisposition.rejected);
    }
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointer = event.pointer;
    _down = event;
    _claimed = false;
    _pending.clear();
    _eager = PalmRejectionFilter.isPrecise(event.kind);
    if (_eager) {
      // القلم/الفأرة: نفوز بالساحة فوراً (قبل إغلاقها) → لا slop ولا منافسة.
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _pointer) _claim();
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    final wasClaimed = _claimed;
    _end();
    if (wasClaimed) onCancel?.call();
  }

  void _claim() {
    if (_claimed || _down == null) return;
    _claimed = true;
    onStart?.call(_down!);
    // أحداث وصلت قبل أن تُحسم الساحة (نفس حزمة الأحداث) نُمرّرها بالترتيب.
    final pending = List<PointerMoveEvent>.of(_pending);
    _pending.clear();
    for (final move in pending) {
      onMove?.call(move);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      if (_claimed) {
        onMove?.call(event);
        return;
      }
      _pending.add(event);
      final down = _down;
      if (!_eager &&
          down != null &&
          (event.position - down.position).distance > touchClaimSlop) {
        resolvePointer(event.pointer, GestureDisposition.accepted);
      }
    } else if (event is PointerUpEvent) {
      if (!_claimed) {
        if (_eager) {
          _claim(); // نقرة قلم سريعة = نقطة
        } else if (tapMakesDot && onStart != null) {
          // نقرة إصبع قصيرة (لم تتجاوز مسافة الـ slop): نقطة. نحسم الساحة لصالحنا
          // الآن، قبل أن يُحسم الـ sweep لصالح أي Tap آخر. نُسقط الحركات الدقيقة
          // المخزّنة كي تكون النتيجة نقطة نظيفة لا خطاً صغيراً.
          _pending.clear();
          resolvePointer(event.pointer, GestureDisposition.accepted);
        }
      }
      final claimed = _claimed;
      if (claimed) onEnd?.call(event);
      _end(resolveRejected: !claimed);
    } else if (event is PointerCancelEvent) {
      final claimed = _claimed;
      _end(resolveRejected: !claimed);
      if (claimed) onCancel?.call();
    }
  }

  void _end({bool resolveRejected = false}) {
    final pointer = _pointer;
    _pointer = null;
    _down = null;
    _claimed = false;
    _eager = false;
    _pending.clear();
    if (pointer == null) return;
    stopTrackingPointer(pointer);
    if (resolveRejected) resolvePointer(pointer, GestureDisposition.rejected);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    final wasClaimed = _claimed;
    _pointer = null;
    _down = null;
    _claimed = false;
    _pending.clear();
    super.dispose();
    // أُزيلت الطبقة أثناء الخط (مثلاً خرجت الصفحة من الشاشة): ثبّت ما رُسم.
    if (wasClaimed) onCancel?.call();
  }

  @override
  String get debugDescription => 'ink';
}

/// طبقة تراقب مؤشرات العارض كله وتطبّق "حارس راحة اليد":
///
///  • تتتبع حضور القلم (hover/ملامسة/ثوانٍ بعد الرفع) عبر [PalmRejectionFilter].
///  • عندما يكون رفض راحة اليد مفعّلاً وأداة رسم نشطة ([isActive]) فإن أي لمسة
///    إصبع/كف تصل والقلم قريب تُلغى فوراً بـ `GestureBinding.cancelPointer`
///    فلا يراها عارض الـ PDF أبداً (لا تمرير ولا تكبير ولا سحب).
///  • وعند ظهور القلم (أول hover له، أو ملامسته للشاشة) تُلغى أيضاً اللمسات
///    الموجودة مسبقاً (كف استقرّ قبل القلم، أو إصبع يحرّك الصفحة/يكبّرها) كي لا
///    تستمر في تحريك الصفحة وهي ما زالت على الشاشة.
///  • **وتُوقَف حركة الصفحة نفسها** ([onHaltPageMotion]): إلغاء المؤشر وحده لا
///    يكفي، لأن عارض الـ PDF يعامل الإلغاء كرفع إصبع فيُطلق "قذفة" (fling) أو
///    قصور تكبير بسرعة آخر لحظة فتواصل الصفحة الانزلاق بعد اختفاء الإصبع.
///
/// الطبقة لا تشارك في ساحة الإيماءات ولا تستهلك أي حدث (translucent)، فلا
/// تتعارض مع شريط الأدوات (الذي يقع خارجها) ولا مع بقية الإيماءات.
class PalmGuardLayer extends StatelessWidget {
  const PalmGuardLayer({
    super.key,
    required this.filter,
    required this.isActive,
    required this.child,
    this.onHaltPageMotion,
  });

  final PalmRejectionFilter filter;

  /// هل أداة رسم تستخدم القلم نشطة الآن (وضع الرسم مفعّل + أداة قلم/ممحاة/...)؟
  final bool Function() isActive;
  final Widget child;

  /// يُستدعى لإيقاف أي حركة جارية للصفحة (قذفة تمرير، قصور تكبير، ارتداد) عند
  /// ظهور القلم. يجب أن يكون آمناً ومتكرِّر الاستدعاء (idempotent) وألا يفعل
  /// شيئاً إن لم تكن هناك حركة.
  final VoidCallback? onHaltPageMotion;

  /// ظهور القلم: أول حدث منه (hover أو ملامسة) بعد غياب أطول من
  /// [PalmRejectionFilter.penHold].
  ///
  /// 1) يلغي كل إصبع/كف بدأ **قبل** ظهور القلم (مستقرّاً أو يحرّك الصفحة أو
  ///    يكبّرها).
  /// 2) يوقف حركة الصفحة. ⚠️ الترتيب مهم: `GestureBinding.cancelPointer` **لا**
  ///    يُرسل الإلغاء داخل الاستدعاء نفسه بل يضعه في الطابور ويُنفَّذ بعد عودتنا
  ///    (قبل نهاية الـ microtask). والقذفة تنطلق لحظة وصول حدث الإلغاء إلى
  ///    عارض الـ PDF، أي **بعد** أي إيقاف نطلبه هنا مباشرة. لذلك:
  ///     • أُلغيت لمسات: نُجدوِل الإيقاف في microtask بعد `cancelPointer`، فيعمل
  ///       بعد وصول الإلغاء مباشرةً وقبل أول إطار، فلا تتحرك الصفحة ولا بكسل.
  ///     • لا لمسات (قذفة إصبع رُفع سابقاً ما زالت تنزلق): نوقفها الآن مباشرة.
  ///    (لا حاجة للإيقاف الفوري مع وجود لمسة: العارض نفسه يوقف أي قذفة قديمة
  ///    عند نزول الإصبع.)
  void _onPenEvent(PointerEvent event) {
    final appeared = !filter.penNearby; // قبل تسجيل هذا الحدث
    filter.notePen(event);
    if (!filter.enabled || !isActive()) return;

    final touches = filter.takeRestingTouches();
    for (final pointer in touches) {
      GestureBinding.instance.cancelPointer(pointer);
    }
    if (touches.isEmpty && !appeared) return; // القلم حاضر أصلاً ولا جديد

    if (touches.isEmpty) {
      onHaltPageMotion?.call();
    } else {
      scheduleMicrotask(() => onHaltPageMotion?.call());
    }
  }

  void _onHover(PointerHoverEvent event) {
    if (!PalmRejectionFilter.isPen(event.kind)) return;
    _onPenEvent(event);
  }

  void _onDown(PointerDownEvent event) {
    if (PalmRejectionFilter.isPen(event.kind)) {
      _onPenEvent(event);
      return;
    }
    if (PalmRejectionFilter.isPrecise(event.kind)) return; // فأرة
    if (filter.enabled && isActive() && filter.penNearby) {
      GestureBinding.instance.cancelPointer(event.pointer);
      return;
    }
    filter.trackTouch(event.pointer);
  }

  void _onMove(PointerMoveEvent event) {
    if (PalmRejectionFilter.isPen(event.kind)) filter.notePen(event);
  }

  void _onEnd(PointerEvent event) {
    // بالمعرّف لا بالنوع: حدث إلغاء مولَّد (cancelPointer) نوعه touch حتى لقلم.
    filter.endPointer(event.pointer);
    if (PalmRejectionFilter.isPen(event.kind)) filter.notePen(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _onHover,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      child: child,
    );
  }
}
