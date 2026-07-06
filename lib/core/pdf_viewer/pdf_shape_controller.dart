import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/shape_model.dart';
import '../services/pdf_annotation_store.dart';

/// يدير أدوات الأشكال الهندسية (سهم/دائرة/مربع/مستطيل):
/// - الرسم بالسحب (نقطة بداية إلى نقطة نهاية) بنظام إحداثيات نسبي لكل صفحة.
/// - الرسم الفعلي على الـ Canvas.
/// - تحريك وتغيير الحجم وحذف الأشكال الموجودة.
class PdfShapeController {
  PdfShapeController({
    required this.store,
    required this.onChanged,
  });

  final PdfAnnotationStore store;
  final VoidCallback onChanged;

  bool isActive = false;
  ShapeType activeType = ShapeType.rectangle;
  int borderColor = 0xFFEF4444;
  int? fillColor; // null = شفاف
  double borderWidth = 0.004;

  final Map<int, List<ShapeModel>> _shapes = {};
  ShapeModel? _drawingShape;
  int? _drawingPage;

  List<ShapeModel> shapesForPage(int page) => _shapes[page] ?? const [];

  Future<void> ensurePageLoaded(int pageNumber) async {
    if (!_shapes.containsKey(pageNumber)) {
      _shapes[pageNumber] = await store.loadShapes(pageNumber);
    }
  }

  Future<void> _persist(int pageNumber) => store.saveShapes(pageNumber, _shapes[pageNumber] ?? const []);

  void startDrawing(int pageNumber, Offset relativePoint) {
    _drawingPage = pageNumber;
    _drawingShape = ShapeModel(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      type: activeType,
      startDx: relativePoint.dx,
      startDy: relativePoint.dy,
      endDx: relativePoint.dx,
      endDy: relativePoint.dy,
      borderColor: borderColor,
      fillColor: fillColor,
      borderWidth: borderWidth,
    );
    onChanged();
  }

  void updateDrawing(Offset relativePoint) {
    if (_drawingShape == null) return;
    _drawingShape!.endDx = relativePoint.dx;
    _drawingShape!.endDy = relativePoint.dy;
    onChanged();
  }

  /// [pageSize] is required when [activeType] == [ShapeType.square] so that the
  /// equal-side constraint is resolved in **pixel space** rather than normalised
  /// coordinate space (where width ≠ height in pixels), preventing the saved
  /// shape from being smaller than what the user actually drew.
  Future<void> endDrawing({Size? pageSize}) async {
    if (_drawingShape == null || _drawingPage == null) return;
    // تجاهل الأشكال الصغيرة جداً (ضغطة بالخطأ بدون سحب فعلي)
    final dx = (_drawingShape!.endDx - _drawingShape!.startDx).abs();
    final dy = (_drawingShape!.endDy - _drawingShape!.startDy).abs();
    if (dx > 0.01 || dy > 0.01) {
      // ── تثبيت المربع: حفظ الأبعاد المتساوية في فضاء البكسل ──
      // السبب: الإحداثيات النسبية (0–1) تمثّل نسباً مختلفة من البكسلات
      // على المحورين (عرض الصفحة ≠ ارتفاعها)، لذا يجب حساب ضلع المربع
      // في فضاء البكسل ثم تحويله للإحداثيات النسبية للتخزين.
      if (_drawingShape!.type == ShapeType.square && pageSize != null && pageSize.width > 0 && pageSize.height > 0) {
        // تحويل إلى بكسل
        final pxStartX = _drawingShape!.startDx * pageSize.width;
        final pxStartY = _drawingShape!.startDy * pageSize.height;
        final pxEndX   = _drawingShape!.endDx   * pageSize.width;
        final pxEndY   = _drawingShape!.endDy   * pageSize.height;

        final pdx = pxEndX - pxStartX;
        final pdy = pxEndY - pxStartY;

        // اختيار أكبر امتداد (وليس أصغره) حفاظاً على الحجم الذي رسمه المستخدم
        final side = math.max(pdx.abs(), pdy.abs());

        // حفظ اتجاه السحب على كل محور
        final pxNewEndX = pxStartX + (pdx < 0 ? -side : side);
        final pxNewEndY = pxStartY + (pdy < 0 ? -side : side);

        // تحويل مرة أخرى للإحداثيات النسبية
        _drawingShape!.endDx = pxNewEndX / pageSize.width;
        _drawingShape!.endDy = pxNewEndY / pageSize.height;
      } else if (_drawingShape!.type == ShapeType.square) {
        // احتياطي: إذا لم تتوفر pageSize، استخدم أكبر امتداد نسبي
        final sdx = _drawingShape!.endDx - _drawingShape!.startDx;
        final sdy = _drawingShape!.endDy - _drawingShape!.startDy;
        final side = math.max(sdx.abs(), sdy.abs());
        _drawingShape!.endDx = _drawingShape!.startDx + (sdx < 0 ? -side : side);
        _drawingShape!.endDy = _drawingShape!.startDy + (sdy < 0 ? -side : side);
      }
      _shapes.putIfAbsent(_drawingPage!, () => []).add(_drawingShape!);
      await _persist(_drawingPage!);
    }
    _drawingShape = null;
    _drawingPage = null;
    onChanged();
  }

  /// الشكل الجاري رسمه حالياً (لإظهار معاينة فورية أثناء السحب) لصفحة معينة.
  ShapeModel? drawingShapeForPage(int pageNumber) => _drawingPage == pageNumber ? _drawingShape : null;

  Future<void> moveShape(ShapeModel shape, int pageNumber, Offset deltaRelative) async {
    shape.startDx += deltaRelative.dx;
    shape.startDy += deltaRelative.dy;
    shape.endDx += deltaRelative.dx;
    shape.endDy += deltaRelative.dy;
    await _persist(pageNumber);
    onChanged();
  }

  /// تغيير حجم الشكل بعامل تكبير/تصغير (0.5 = نصف الحجم، 2.0 = ضعف الحجم).
  /// يتمحور التغيير حول مركز الشكل الحالي.
  Future<void> resizeShape(ShapeModel shape, int pageNumber, double scaleFactor) async {
    final cx = (shape.startDx + shape.endDx) / 2;
    final cy = (shape.startDy + shape.endDy) / 2;
    final halfW = ((shape.endDx - shape.startDx).abs() / 2) * scaleFactor;
    final halfH = ((shape.endDy - shape.startDy).abs() / 2) * scaleFactor;
    final signX = shape.endDx >= shape.startDx ? 1.0 : -1.0;
    final signY = shape.endDy >= shape.startDy ? 1.0 : -1.0;
    shape.startDx = cx - halfW * signX;
    shape.startDy = cy - halfH * signY;
    shape.endDx = cx + halfW * signX;
    shape.endDy = cy + halfH * signY;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateBorderColor(ShapeModel shape, int pageNumber, int color) async {
    shape.borderColor = color;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateFillColor(ShapeModel shape, int pageNumber, int? color) async {
    shape.fillColor = color;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateBorderWidth(ShapeModel shape, int pageNumber, double width) async {
    shape.borderWidth = width;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> deleteShape(ShapeModel shape, int pageNumber) async {
    _shapes[pageNumber]?.removeWhere((s) => s.id == shape.id);
    await _persist(pageNumber);
    onChanged();
  }

  /// اكتشاف الشكل الموجود عند نقطة نسبية معينة (للنقر عليه لتحريكه/حذفه).
  ShapeModel? hitTest(int pageNumber, Offset relativePoint, {double margin = 0.015}) {
    for (final s in shapesForPage(pageNumber).reversed) {
      final rect = Rect.fromLTRB(
        math.min(s.startDx, s.endDx) - margin,
        math.min(s.startDy, s.endDy) - margin,
        math.max(s.startDx, s.endDx) + margin,
        math.max(s.startDy, s.endDy) + margin,
      );
      if (rect.contains(relativePoint)) return s;
    }
    return null;
  }

  /// يرسم كل أشكال صفحة معينة (بما فيها الشكل الجاري رسمه إن وُجد) على Canvas.
  void paintShapes(Canvas canvas, Size pageSize, List<ShapeModel> shapes, {ShapeModel? preview}) {
    final all = [...shapes];
    if (preview != null) all.add(preview);
    for (final s in all) {
      _paintOne(canvas, pageSize, s);
    }
  }

  void _paintOne(Canvas canvas, Size pageSize, ShapeModel s) {
    double startX = s.startDx;
    double startY = s.startDy;
    double endX = s.endDx;
    double endY = s.endDy;

    // ── Square Fix ──
    // The shape is stored in normalised coords (0–1 relative to page size).
    // Because page width ≠ page height, normalising dx and dy independently
    // means the same numeric delta represents a different number of pixels on
    // each axis.  We must work in pixel space to get visually equal sides.
    if (s.type == ShapeType.square) {
      // Convert to pixels
      final pxStartX = startX * pageSize.width;
      final pxStartY = startY * pageSize.height;
      final pxEndX   = endX   * pageSize.width;
      final pxEndY   = endY   * pageSize.height;

      final pdx = pxEndX - pxStartX;
      final pdy = pxEndY - pxStartY;

      // Pick the larger pixel extent as the side length (matches endDrawing)
      final side = math.max(pdx.abs(), pdy.abs());

      // Preserve the drag direction on each axis
      final pxNewEndX = pxStartX + (pdx < 0 ? -side : side);
      final pxNewEndY = pxStartY + (pdy < 0 ? -side : side);

      // Convert back to normalised coords for the rect calculation
      endX = pxNewEndX / pageSize.width;
      endY = pxNewEndY / pageSize.height;
    }

    final rect = Rect.fromLTRB(
      math.min(startX, endX) * pageSize.width,
      math.min(startY, endY) * pageSize.height,
      math.max(startX, endX) * pageSize.width,
      math.max(startY, endY) * pageSize.height,
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.borderWidth * pageSize.width
      ..color = Color(s.borderColor);
    // السهم لا يحتوي على تعبئة أبداً
    final fillPaint = (s.fillColor != null && s.type != ShapeType.arrow)
        ? (Paint()
          ..style = PaintingStyle.fill
          ..color = Color(s.fillColor!))
        : null;

    switch (s.type) {
      case ShapeType.rectangle:
      case ShapeType.square:
        if (fillPaint != null) canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
        break;
      case ShapeType.circle:
        if (fillPaint != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, borderPaint);
        break;
      case ShapeType.arrow:
        _paintArrow(
          canvas,
          Offset(s.startDx * pageSize.width, s.startDy * pageSize.height),
          Offset(s.endDx * pageSize.width, s.endDy * pageSize.height),
          borderPaint,
        );
        break;
    }
  }

  /// يرسم سهماً من [start] إلى [end].
  /// الخط يمتد من البداية حتى **قاعدة رأس السهم** حيث تلتقي قاعدة المثلث بالخط
  /// بدون أن يخترق الخط رأس السهم أو يتجاوزه. نقطة الرأس الحقيقية تُحرَّك
  /// قليلاً نحو المنتصف حتى تبدو القاعدة والخط متصلَين بصرياً.
  void _paintArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    final direction = end - start;
    final length = direction.distance;
    if (length < 1) return;

    final unit = direction / length;
    final arrowSize = math.max(18.0, paint.strokeWidth * 5);
    const halfAngle = 0.40; // ~23 درجة

    // ── نحرّك نقطة الرأس قليلاً داخلياً (20%) لتبدو القاعدة وكأنها تلتصق بالخط ──
    final tipInset = arrowSize * 0.20;
    final visualTip = Offset(
      end.dx - tipInset * unit.dx,
      end.dy - tipInset * unit.dy,
    );

    // قاعدة المثلث: على مسافة arrowSize من النقطة الأصلية end
    final arrowBase = Offset(
      end.dx - arrowSize * unit.dx,
      end.dy - arrowSize * unit.dy,
    );

    final cos = math.cos(halfAngle);
    final sin = math.sin(halfAngle);

    // نقطتا الجانبين (تُحسب من النقطة الأصلية end لتحافظ على الزاوية الصحيحة)
    final p1 = Offset(
      end.dx - arrowSize * (unit.dx * cos - unit.dy * sin),
      end.dy - arrowSize * (unit.dy * cos + unit.dx * sin),
    );
    final p2 = Offset(
      end.dx - arrowSize * (unit.dx * cos + unit.dy * sin),
      end.dy - arrowSize * (unit.dy * cos - unit.dx * sin),
    );

    // ── الخط: من البداية حتى قاعدة رأس السهم (لا يتجاوزه) ──
    canvas.drawLine(start, arrowBase, paint..strokeCap = StrokeCap.round);

    // ── رأس السهم (مثلث مملوء): رأسه عند visualTip لاتصال بصري مع الخط ──
    final headPath = Path()
      ..moveTo(visualTip.dx, visualTip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(
      headPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = paint.color,
    );
  }
}
