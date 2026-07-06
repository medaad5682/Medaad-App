import 'dart:ui';

/// خط رسم (قلم / هايلايتر قديم بالسحب / ممحاة)
/// ملاحظة: تم الإبقاء على هذا النموذج لأدوات القلم الحر والممحاة.
/// أداة الـ Highlighter الجديدة (المرتبطة بتحديد النص) تستخدم [HighlightModel] بدلاً من هذا.
class DrawingLine {
  final List<Offset> points;
  final int color;
  final double strokeWidth;
  final bool isHighlighter;
  final bool isEraser;
  final double opacity; // ✅ شفافية القلم (0.0 - 1.0)

  DrawingLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isHighlighter,
    this.isEraser = false,
    this.opacity = 1.0,
  });

  DrawingLine copyWith({
    List<Offset>? points,
    int? color,
    double? strokeWidth,
    bool? isHighlighter,
    bool? isEraser,
    double? opacity,
  }) {
    return DrawingLine(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isHighlighter: isHighlighter ?? this.isHighlighter,
      isEraser: isEraser ?? this.isEraser,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'c': color,
      'w': strokeWidth,
      'h': isHighlighter,
      'e': isEraser,
      'o': opacity,
      'p': points.map((e) => {'x': e.dx, 'y': e.dy}).toList(),
    };
  }

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    var pts = (json['p'] as List).map((e) {
      return Offset(
        (e['x'] as num).toDouble(),
        (e['y'] as num).toDouble(),
      );
    }).toList();

    return DrawingLine(
      points: pts,
      color: json['c'] as int,
      strokeWidth: (json['w'] as num).toDouble(),
      isHighlighter: json['h'] as bool? ?? false,
      isEraser: json['e'] as bool? ?? false,
      opacity: (json['o'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
