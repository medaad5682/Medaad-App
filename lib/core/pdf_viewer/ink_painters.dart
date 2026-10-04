import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/drawing_model.dart';
import '../models/shape_model.dart';
import 'pdf_shape_controller.dart';

/// حالة الحبر الحيّة لصفحة واحدة.
///
/// بدل إعادة بناء شجرة الودجت (ValueListenableBuilder + painter جديد + نسخ
/// قائمة كل الخطوط) عند كل حدث لمس، نُحدِّث عدّادات صغيرة يستمع لها
/// [CustomPainter.repaint] مباشرة، فيُعاد **الرسم فقط** (markNeedsPaint) بلا أي
/// build/layout.
class PageInkState {
  /// يزداد عند تغيّر الخطوط المثبّتة (إضافة/تراجع/تثبيت خط) → إعادة رسم الطبقة السفلية.
  final ValueNotifier<int> committed = ValueNotifier<int>(0);

  /// يزداد مع كل نقطة جديدة في خط القلم الحي → إعادة رسم طبقة الخط الحي فقط.
  final ValueNotifier<int> livePen = ValueNotifier<int>(0);

  /// يزداد مع كل نقطة في خط ممحاة/هايلايتر حي. هذان يحتاجان إلى المزج مع بقية
  /// الحبر (clear / multiply) فيُرسمان داخل الطبقة السفلية نفسها.
  final ValueNotifier<int> liveBlend = ValueNotifier<int>(0);

  late final Listenable committedOrBlend =
      Listenable.merge(<Listenable>[committed, liveBlend]);

  /// الخط الجاري رسمه (null إن لم يكن هناك خط).
  DrawingLine? live;
  Offset? _lastLocal;

  /// أدنى مسافة (بالبكسل المنطقي) بين نقطتين مقبولتين. بالبكسل لا بالنسبة
  /// المئوية للصفحة، فلا تتخشّن الخطوط عند التكبير.
  static const double _minDistSq = 0.5625; // 0.75px²

  /// نفس العتبة للاستخدام الخارجي (الخط الممتد على عدة صفحات يُفلتر بإحداثيات
  /// المستند × التكبير بدل إحداثيات صفحة واحدة).
  static const double minDistanceSq = _minDistSq;

  /// هل يُرسم هذا الخط (وهو حيّ) داخل الطبقة السفلية مع بقية الحبر بدل طبقة
  /// الخط الحي؟ الممحاة والهايلايتر يحتاجان المزج مع الحبر؛ والقلم الشفاف يحتاج
  /// أن يرى الخطوط الشفافة الأخرى كي لا يزداد قتامة عند التقاطع.
  static bool needsBlend(DrawingLine line) =>
      line.isEraser ||
      line.isHighlighter ||
      InkGeometry.isTranslucentPen(line);

  void begin(DrawingLine line, Offset local) {
    live = line;
    _lastLocal = local;
    notifyLive();
  }

  /// هل نقبل هذه النقطة؟ (يتخلّص من العينات المكررة دون فقدان تفاصيل).
  bool shouldAdd(Offset local) {
    final last = _lastLocal;
    if (last != null && (local - last).distanceSquared < _minDistSq) {
      return false;
    }
    _lastLocal = local;
    return true;
  }

  void notifyLive() {
    final line = live;
    if (line != null && needsBlend(line)) {
      liveBlend.value++;
    } else {
      livePen.value++;
    }
  }

  DrawingLine? end() {
    final line = live;
    live = null;
    _lastLocal = null;
    return line;
  }

  /// إعادة رسم كل الطبقات معاً (بعد تثبيت خط أو تراجع).
  void repaintAll() {
    committed.value++;
    livePen.value++;
    liveBlend.value++;
  }

  void dispose() {
    committed.dispose();
    livePen.dispose();
    liveBlend.dispose();
  }
}

class _CachedStrokePath {
  _CachedStrokePath(this.count, this.aspect, this.path);
  final int count;
  final double aspect;
  final Path path;
}

/// هندسة الخطوط: بناء المسار مرة واحدة وإعادة استخدامه.
///
/// المسار يُبنى في إحداثيات "نسبة إلى عرض الصفحة" (x = dx، y = dy × h/w) ثم
/// يُرسم بعد `canvas.scale(width)` منتظم؛ فلا يُعاد بناؤه عند التكبير/التصغير
/// ولا عند كل إطار، بل فقط عندما تتغيّر نقاط الخط نفسه (الخط الحي).
class InkGeometry {
  InkGeometry._();

  static final Expando<_CachedStrokePath> _cache =
      Expando<_CachedStrokePath>('inkStrokePath');

  static Path pathFor(DrawingLine line, double aspect) {
    final pts = line.points;
    final cached = _cache[line];
    if (cached != null &&
        cached.count == pts.length &&
        (cached.aspect - aspect).abs() < 1e-3) {
      return cached.path;
    }
    final path = _catmullRom(pts, aspect);
    _cache[line] = _CachedStrokePath(pts.length, aspect, path);
    return path;
  }

  // Catmull-Rom (tension 0.5) → Bézier مكعّب. نفس الصيغة السابقة تماماً.
  static Path _catmullRom(List<Offset> pts, double aspect) {
    final path = Path();
    final n = pts.length;
    if (n == 0) return path;

    Offset pt(int i) => Offset(pts[i].dx, pts[i].dy * aspect);

    final first = pt(0);
    path.moveTo(first.dx, first.dy);
    if (n == 1) return path;
    if (n == 2) {
      final b = pt(1);
      path.lineTo(b.dx, b.dy);
      return path;
    }

    const k = 0.5 / 3;
    var p0 = first;
    var p1 = first;
    var p2 = pt(1);
    for (int i = 0; i < n - 1; i++) {
      final p3 = i + 2 < n ? pt(i + 2) : pt(n - 1);
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) * k,
        p1.dy + (p2.dy - p0.dy) * k,
        p2.dx - (p3.dx - p1.dx) * k,
        p2.dy - (p3.dy - p1.dy) * k,
        p2.dx,
        p2.dy,
      );
      p0 = p1;
      p1 = p2;
      p2 = p3;
    }
    return path;
  }

  /// قلم بشفافية (أقل من 100%): ليس ممحاة ولا هايلايتر.
  static bool isTranslucentPen(DrawingLine line) =>
      !line.isEraser && !line.isHighlighter && line.opacity < 0.999;

  /// أي خط شفاف (قلم شفاف أو هايلايتر حر). الخطوط الشفافة المتتالية من نفس
  /// النوع تُرسم كمجموعة لا يغمّق فيها التقاطع.
  static bool isTranslucentStroke(DrawingLine line) =>
      !line.isEraser && line.opacity < 0.999;

  /// هل يمكن رسم [a] و[b] في مجموعة واحدة؟ (شفافان ومن نفس النوع).
  static bool sameTranslucentGroup(DrawingLine a, DrawingLine b) =>
      isTranslucentStroke(a) &&
      isTranslucentStroke(b) &&
      a.isHighlighter == b.isHighlighter;

  /// يرسم خطاً واحداً. يفترض أن الـ canvas مُكبَّر مسبقاً بعرض الصفحة
  /// (`canvas.scale(width)`) فسماكة الخط (نسبة من العرض) تُستخدم كما هي.
  ///
  /// [replace]: للخطوط الشفافة داخل مجموعتها (saveLayer مستقلة). نستخدم
  /// `BlendMode.src` فيحلّ الخط اللاحق محلّ السابق عند التقاطع بدل أن يتراكب
  /// معه (src-over) أو يتضاعف (multiply)، فلا تزداد المنطقة المتقاطعة قتامة.
  /// (الخط الواحد المتقاطع مع نفسه لا يتراكب أصلاً لأنه مسار واحد.)
  static void paintLine(Canvas canvas, DrawingLine line, double aspect,
      {bool replace = false}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = line.strokeWidth;

    if (line.isEraser) {
      paint.blendMode = BlendMode.clear;
      paint.color = Colors.transparent;
    } else if (line.isHighlighter) {
      // هايلايتر حر: multiply مع بقية الحبر (داخل saveLayer الطبقة)، أما داخل
      // مجموعة هايلايتر متتالية فيحلّ الخط محلّ السابق (replace) فلا يغمّق.
      paint.blendMode = replace ? BlendMode.src : BlendMode.multiply;
      paint.color = Color(line.color).withOpacity(line.opacity);
      paint.strokeCap = StrokeCap.square;
    } else {
      paint.color = Color(line.color).withOpacity(line.opacity);
      if (replace) paint.blendMode = BlendMode.src;
    }

    final pts = line.points;
    if (pts.length > 1) {
      canvas.drawPath(pathFor(line, aspect), paint);
    } else if (pts.isNotEmpty) {
      // نقطة واحدة (نقرة قلم) → نرسم نقطة.
      canvas.drawPoints(
        PointMode.points,
        <Offset>[Offset(pts[0].dx, pts[0].dy * aspect)],
        paint,
      );
    }
  }
}

/// الطبقة السفلية: كل الخطوط المثبّتة (+ الممحاة/الهايلايتر الحيّان).
///
/// توضع داخل RepaintBoundary وتُعاد رسمها **فقط** عند تثبيت خط/تراجع/تغيّر حجم
/// الصفحة؛ أثناء الكتابة بالقلم لا تُلمس إطلاقاً.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.drawings,
    required this.pageNumber,
    required this.pageSize,
    required this.ink,
  }) : super(repaint: ink.committedOrBlend);

  final Map<int, List<DrawingLine>> drawings;
  final int pageNumber;
  final Size pageSize;
  final PageInkState ink;

  @override
  void paint(Canvas canvas, Size size) {
    final List<DrawingLine> lines =
        drawings[pageNumber] ?? const <DrawingLine>[];
    final live = ink.live;
    final DrawingLine? blendLive =
        (live != null && PageInkState.needsBlend(live)) ? live : null;
    final hasLines = lines.isNotEmpty;
    if (!hasLines && blendLive == null) return;

    final w = pageSize.width;
    if (w <= 0) return;
    final aspect = pageSize.height / w;

    // saveLayer للصفحة مطلوب فقط عند وجود خطوط تعتمد على المزج مع بقية الحبر
    // (ممحاة/هايلايتر)، فيبقى المزج داخل طبقة الحبر ولا يمسّ محتوى الـ PDF.
    bool pageLayer(DrawingLine l) => l.isEraser || l.isHighlighter;
    var needsLayer = blendLive != null && pageLayer(blendLive);
    if (!needsLayer) {
      for (final l in lines) {
        if (pageLayer(l)) {
          needsLayer = true;
          break;
        }
      }
    }

    // ── قصّ الرسم على حدود الصفحة: كل صفحة ترسم الجزء الذي يخصّها فقط، فلا
    //    يظهر الخط الممتد بين صفحتين بشكل مختلف حسب وجود ممحاة/هايلايتر.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (needsLayer) canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    canvas.scale(w);

    final int committedCount = lines.length;
    final int total = committedCount + (blendLive != null ? 1 : 0);
    DrawingLine lineAt(int i) => i < committedCount ? lines[i] : blendLive!;

    // حدود طبقة المجموعة بعد التكبير: الصفحة = [0..1] × [0..aspect].
    final groupBounds = Rect.fromLTWH(0, 0, 1, aspect);
    var i = 0;
    while (i < total) {
      final l = lineAt(i);
      if (InkGeometry.isTranslucentStroke(l)) {
        // مجموعة خطوط شفافة متتالية من نفس النوع (أقلام شفافة، أو هايلايتر حر):
        // تُرسم في طبقة مستقلة بحيث يحلّ كل خط محلّ السابق عند التقاطع (لا يزداد
        // غمقاً)، ثم تُركَّب على بقية الحبر (بالمضاعفة للهايلايتر كما كان).
        var j = i + 1;
        while (j < total && InkGeometry.sameTranslucentGroup(l, lineAt(j))) {
          j++;
        }
        if (j - i == 1) {
          InkGeometry.paintLine(canvas, l, aspect);
        } else {
          final groupPaint = Paint();
          if (l.isHighlighter) groupPaint.blendMode = BlendMode.multiply;
          canvas.saveLayer(groupBounds, groupPaint);
          for (var k = i; k < j; k++) {
            InkGeometry.paintLine(canvas, lineAt(k), aspect, replace: true);
          }
          canvas.restore();
        }
        i = j;
      } else {
        InkGeometry.paintLine(canvas, l, aspect);
        i++;
      }
    }

    canvas.restore(); // scale
    if (needsLayer) canvas.restore(); // saveLayer
    canvas.restore(); // clip
  }

  @override
  bool shouldRepaint(covariant CommittedInkPainter old) =>
      old.pageSize != pageSize ||
      old.pageNumber != pageNumber ||
      !identical(old.drawings, drawings) ||
      !identical(old.ink, ink);

  // الطبقة مرئية فقط: لا تلتقط اللمس (الإدخال في طبقة منفصلة).
  @override
  bool? hitTest(Offset position) => false;
}

/// طبقة الخط الحي (القلم): ترسم الخط الجاري فقط. تكلفتها مستقلة تماماً عن عدد
/// الخطوط المرسومة سابقاً في الصفحة.
class LiveInkPainter extends CustomPainter {
  LiveInkPainter({required this.ink, required this.pageSize})
      : super(repaint: ink.livePen);

  final PageInkState ink;
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final live = ink.live;
    if (live == null || PageInkState.needsBlend(live)) return;
    final w = pageSize.width;
    if (w <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(w);
    InkGeometry.paintLine(canvas, live, pageSize.height / w);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiveInkPainter old) =>
      old.pageSize != pageSize || !identical(old.ink, ink);

  @override
  bool? hitTest(Offset position) => false;
}

/// طبقة الأشكال (نفس منطق الرسم السابق عبر PdfShapeController).
class ShapesLayerPainter extends CustomPainter {
  ShapesLayerPainter({
    required this.shapes,
    required this.preview,
    required this.pageSize,
    required this.controller,
  });

  final List<ShapeModel> shapes;
  final ShapeModel? preview;
  final Size pageSize;
  final PdfShapeController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (shapes.isEmpty && preview == null) return;
    // كل صفحة ترسم الجزء الذي يخصّها فقط: الشكل الممتد على صفحتين يُقصّ عند حدود
    // كل صفحة (كالخط الحر)، فلا يختلف ظهوره بحسب أيّ صفحة بدأ منها.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    controller.paintShapes(canvas, pageSize, shapes, preview: preview);
    canvas.restore();
  }

  // الأشكال تُعدَّل في مكانها (نقل/تعديل) فنعيد الرسم دائماً؛ عددها قليل.
  @override
  bool shouldRepaint(covariant ShapesLayerPainter old) => true;

  @override
  bool? hitTest(Offset position) => false;
}
