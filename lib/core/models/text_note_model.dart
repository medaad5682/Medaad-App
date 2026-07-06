/// نص مكتوب يوضع مباشرة على الصفحة (أداة "النص")
/// يمكن تحريكه، تعديل نصه، تغيير لونه وحجمه، أو حذفه.
class TextNoteModel {
  final String id;
  String text;
  double dx; // موضع نسبي (0-1) من عرض الصفحة
  double dy; // موضع نسبي (0-1) من ارتفاع الصفحة
  int color;
  double fontSize; // بالنقاط النسبية لعرض الصفحة (يُحسب كـ fontSize * pageWidth)
  bool bold;
  bool underline;

  TextNoteModel({
    required this.id,
    required this.text,
    required this.dx,
    required this.dy,
    required this.color,
    this.fontSize = 0.022,
    this.bold = false,
    this.underline = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'dx': dx,
      'dy': dy,
      'c': color,
      'fs': fontSize,
      'b': bold,
      'u': underline,
    };
  }

  factory TextNoteModel.fromJson(Map<String, dynamic> json) {
    return TextNoteModel(
      id: json['id'] as String,
      text: json['text'] as String,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      color: json['c'] as int,
      fontSize: (json['fs'] as num?)?.toDouble() ?? 0.022,
      bold: json['b'] as bool? ?? false,
      underline: json['u'] as bool? ?? false,
    );
  }
}
