class CommentModel {
  final String id;
  String text;
  double dx;
  double dy;
  int color;
  double scale;

  CommentModel({
    required this.id,
    required this.text,
    required this.dx,
    required this.dy,
    required this.color,
    this.scale = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'dx': dx,
      'dy': dy,
      'c': color,
      's': scale,
    };
  }

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as String,
      text: json['text'] as String,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      color: json['c'] as int,
      scale: (json['s'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// إعدادات افتراضية لأداة الملاحظات (Notes) يتم حفظها بين الجلسات
/// بحيث لا يحتاج المستخدم لإعادة ضبط اللون/الحجم كل مرة يضيف ملاحظة جديدة.
class CommentDefaults {
  int color;
  double scale;

  CommentDefaults({
    this.color = 0xFFFFC107, // أصفر افتراضي
    this.scale = 1.0,
  });

  Map<String, dynamic> toJson() => {'c': color, 's': scale};

  factory CommentDefaults.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CommentDefaults();
    return CommentDefaults(
      color: json['c'] as int? ?? 0xFFFFC107,
      scale: (json['s'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
