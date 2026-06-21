import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/shape_model.dart';
import '../services/pdf_annotation_store.dart';

/// يدير أدوات الأشكال الهندسية (سهم/دائرة/مربع/مستطيل):
/// - الرسم بالسحب (نقطة بداية إلى نقطة نهاية) بنظام إحداثيات نسبي لكل صفحة.
/// - الرسم الفعلي على الـ Canvas.
/// - تحريك وحذف الأشكال الموجودة.
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

  Future<void> endDrawing() async {
    if (_drawingShape == null || _drawingPage == null) return;
    // تجاهل الأشكال الصغيرة جداً (ضغطة بالخطأ بدون سحب فعلي)
    final dx = (_drawingShape!.endDx - _drawingShape!.startDx).abs();
    final dy = (_drawingShape!.endDy - _drawingShape!.startDy).abs();
    if (dx > 0.01 || dy > 0.01) {
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

  /// يرسم كل أشكال صفحة معينة (بما فيها الشكل الجاري رسمه إن وُجد) على Canvas
  /// بأبعاد [pageSize] (نظام رسم نسبي يتطابق مع بقية الأدوات في هذا الملف).
  void paintShapes(Canvas canvas, Size pageSize, List<ShapeModel> shapes, {ShapeModel? preview}) {
    final all = [...shapes];
    if (preview != null) all.add(preview);
    for (final s in all) {
      _paintOne(canvas, pageSize, s);
    }
  }

  void _paintOne(Canvas canvas, Size pageSize, ShapeModel s) {
    final rect = Rect.fromLTRB(
      math.min(s.startDx, s.endDx) * pageSize.width,
      math.min(s.startDy, s.endDy) * pageSize.height,
      math.max(s.startDx, s.endDx) * pageSize.width,
      math.max(s.startDy, s.endDy) * pageSize.height,
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.borderWidth * pageSize.width
      ..color = Color(s.borderColor);
    final fillPaint = s.fillColor != null
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

  void _paintArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint..strokeCap = StrokeCap.round);

    final direction = end - start;
    final length = direction.distance;
    if (length < 1) return;
    final unit = direction / length;
    final arrowSize = math.max(10.0, paint.strokeWidth * 4);

    // زاوية رأس السهم (حوالي 28 درجة عن خط الاتجاه)
    const angle = 0.49; // راديان
    final normal = Offset(-unit.dy, unit.dx);

    final p1 = end - unit * arrowSize + normal * arrowSize * math.sin(angle);
    final p2 = end - unit * arrowSize - normal * arrowSize * math.sin(angle);

    final headPath = Path()
      ..moveTo(end.dx, end.dy)
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
