/// صورة يضيفها المستخدم من جهازه فوق صفحة الـ PDF
/// يتم حفظ الصورة كملف منفصل على التخزين المحلي ويُحفظ مسارها فقط (لتجنب تضخيم قاعدة بيانات Hive).
class ImageAnnotationModel {
  final String id;
  String path; // مسار الصورة المحفوظة محلياً
  double dx; // الزاوية العلوية اليسرى - نسبي لعرض الصفحة
  double dy; // الزاوية العلوية اليسرى - نسبي لارتفاع الصفحة
  double width; // نسبي لعرض الصفحة
  double height; // نسبي لارتفاع الصفحة

  ImageAnnotationModel({
    required this.id,
    required this.path,
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'dx': dx,
      'dy': dy,
      'w': width,
      'h': height,
    };
  }

  factory ImageAnnotationModel.fromJson(Map<String, dynamic> json) {
    return ImageAnnotationModel(
      id: json['id'] as String,
      path: json['path'] as String,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      width: (json['w'] as num).toDouble(),
      height: (json['h'] as num).toDouble(),
    );
  }
}
