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
///    للعارض.
///  • مؤشر واحد فقط لكل خط: أي مؤشر آخر يصل أثناء الخط يُسقَط (لا يحرّك الصفحة
///    ولا يضيف نقاطاً).
///  • بدء/نهاية/إلغاء الخط تخص **نفس المؤشر** الذي بدأه، لا آخر مؤشر على الشاشة.
class InkPointerRecognizer extends OneSequenceGestureRecognizer {
  InkPointerRecognizer({
    super.debugOwner,
    super.supportedDevices,
    this.touchClaimSlop = 8.0,
  });

  /// المسافة (بالبكسل المنطقي) التي يجب أن يتحركها الإصبع قبل أن نعتبره رسماً.
  final double touchClaimSlop;

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
      // خط جارٍ: لا شيء آخر يحرّك الصفحة أو يعبث بالخط (باستثناء قلم آخر).
      if (!PalmRejectionFilter.isPen(event.kind)) {
        GestureBinding.instance.cancelPointer(event.pointer);
      }
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
      if (!_claimed && _eager) _claim(); // نقرة قلم سريعة = نقطة
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
///  • وعند ملامسة القلم للشاشة تُلغى أيضاً اللمسات الموجودة مسبقاً (كف استقرّ
///    قبل القلم) كي لا تحرّك الصفحة وهي ما زالت على الشاشة.
///
/// الطبقة لا تشارك في ساحة الإيماءات ولا تستهلك أي حدث (translucent)، فلا
/// تتعارض مع شريط الأدوات (الذي يقع خارجها) ولا مع بقية الإيماءات.
class PalmGuardLayer extends StatelessWidget {
  const PalmGuardLayer({
    super.key,
    required this.filter,
    required this.isActive,
    required this.child,
  });

  final PalmRejectionFilter filter;

  /// هل أداة رسم تستخدم القلم نشطة الآن (وضع الرسم مفعّل + أداة قلم/ممحاة/...)؟
  final bool Function() isActive;
  final Widget child;

  void _onHover(PointerHoverEvent event) {
    if (PalmRejectionFilter.isPen(event.kind)) filter.notePen(event);
  }

  void _onDown(PointerDownEvent event) {
    if (PalmRejectionFilter.isPen(event.kind)) {
      filter.notePen(event);
      if (filter.enabled && isActive()) {
        for (final pointer in filter.takeRestingTouches()) {
          GestureBinding.instance.cancelPointer(pointer);
        }
      }
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
    if (PalmRejectionFilter.isPen(event.kind)) {
      filter.notePen(event);
    } else {
      filter.untrack(event.pointer);
    }
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
