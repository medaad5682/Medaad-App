/// تمييز نص حقيقي (Highlight) - يعتمد على فهرس بداية/نهاية النص الفعلي في الصفحة
/// بدلاً من رسم حر، مما يسمح بتمييز دقيق يتبع شكل السطور، وتغيير لونه أو حذفه لاحقاً.
class HighlightModel {
  final String id;
  final int pageNumber;
  final int start; // فهرس بداية النص المحدد في PdfPageText.fullText
  final int end; // فهرس نهاية النص المحدد (غير شامل)
  int color;
  double opacity;

  HighlightModel({
    required this.id,
    required this.pageNumber,
    required this.start,
    required this.end,
    required this.color,
    this.opacity = 0.4,
  });

  HighlightModel copyWith({int? color, double? opacity}) {
    return HighlightModel(
      id: id,
      pageNumber: pageNumber,
      start: start,
      end: end,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'page': pageNumber,
      's': start,
      'e': end,
      'c': color,
      'o': opacity,
    };
  }

  factory HighlightModel.fromJson(Map<String, dynamic> json) {
    return HighlightModel(
      id: json['id'] as String,
      pageNumber: json['page'] as int,
      start: json['s'] as int,
      end: json['e'] as int,
      color: json['c'] as int,
      opacity: (json['o'] as num?)?.toDouble() ?? 0.4,
    );
  }
}

/// تسطير نص (Underline) - نفس منطق الـ Highlight لكن يُرسم كخط تحت السطر فقط
class UnderlineModel {
  final String id;
  final int pageNumber;
  final int start;
  final int end;
  int color;
  double thickness;

  UnderlineModel({
    required this.id,
    required this.pageNumber,
    required this.start,
    required this.end,
    required this.color,
    this.thickness = 2.0,
  });

  UnderlineModel copyWith({int? color, double? thickness}) {
    return UnderlineModel(
      id: id,
      pageNumber: pageNumber,
      start: start,
      end: end,
      color: color ?? this.color,
      thickness: thickness ?? this.thickness,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'page': pageNumber,
      's': start,
      'e': end,
      'c': color,
      't': thickness,
    };
  }

  factory UnderlineModel.fromJson(Map<String, dynamic> json) {
    return UnderlineModel(
      id: json['id'] as String,
      pageNumber: json['page'] as int,
      start: json['s'] as int,
      end: json['e'] as int,
      color: json['c'] as int,
      thickness: (json['t'] as num?)?.toDouble() ?? 2.0,
    );
  }
}
