enum ShapeType { arrow, circle, square, rectangle }

/// شكل هندسي (سهم / دائرة / مربع / مستطيل)
/// محدد بمستطيل احتواء نسبي (من نقطة بداية إلى نقطة نهاية) بالإضافة إلى لون الحدود ولون التعبئة (قد يكون شفافاً).
class ShapeModel {
  final String id;
  ShapeType type;
  double startDx;
  double startDy;
  double endDx;
  double endDy;
  int borderColor;
  int? fillColor; // null = بلا تعبئة (شفاف)
  double borderWidth;

  ShapeModel({
    required this.id,
    required this.type,
    required this.startDx,
    required this.startDy,
    required this.endDx,
    required this.endDy,
    required this.borderColor,
    this.fillColor,
    this.borderWidth = 0.004,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'sx': startDx,
      'sy': startDy,
      'ex': endDx,
      'ey': endDy,
      'bc': borderColor,
      'fc': fillColor,
      'bw': borderWidth,
    };
  }

  factory ShapeModel.fromJson(Map<String, dynamic> json) {
    return ShapeModel(
      id: json['id'] as String,
      type: ShapeType.values[json['type'] as int],
      startDx: (json['sx'] as num).toDouble(),
      startDy: (json['sy'] as num).toDouble(),
      endDx: (json['ex'] as num).toDouble(),
      endDy: (json['ey'] as num).toDouble(),
      borderColor: json['bc'] as int,
      fillColor: json['fc'] as int?,
      borderWidth: (json['bw'] as num?)?.toDouble() ?? 0.004,
    );
  }
}
