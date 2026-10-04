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

  /// الشكل الذي يمتد على أكثر من صفحة يُقسَّم إلى أجزاء، لكل صفحة جزؤها بإحداثيات
  /// نسبية لتلك الصفحة (قد تتجاوز 0..1 ويقصّها رسم الصفحة عند حدودها). كل أجزاء
  /// الشكل الواحد تشترك في [groupId] وتحمل [groupPages] (أرقام صفحات الأجزاء).
  /// null للأشكال القديمة (جزء وحيد): معرّفها [id] هو معرّف المجموعة.
  String? groupId;
  List<int>? groupPages;

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
    this.groupId,
    this.groupPages,
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
      if (groupId != null) 'gid': groupId,
      if (groupPages != null) 'gp': groupPages,
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
      groupId: json['gid'] as String?,
      groupPages: (json['gp'] as List?)?.map((e) => (e as num).toInt()).toList(),
    );
  }
}
