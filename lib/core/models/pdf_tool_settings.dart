/// إعدادات الأدوات المحفوظة بين الجلسات (لا تتعلق بملف PDF معين، بل عامة للقارئ)
class PdfToolSettings {
  // القلم
  int penColor;
  double penThickness; // نسبي لعرض الصفحة
  double penOpacity;

  // الهايلايتر
  int highlighterColor;
  double highlighterOpacity;

  // التسطير
  int underlineColor;

  // النص
  int textColor;
  double textFontSize;

  // الأشكال
  int shapeBorderColor;
  int? shapeFillColor;
  double shapeBorderWidth;

  // رفض راحة اليد
  bool palmRejectionEnabled;

  // الهايلايتر الحر
  double freehandHighlighterThickness;

  PdfToolSettings({
    this.penColor = 0xFFEF4444,
    this.penThickness = 0.003,
    this.penOpacity = 1.0,
    this.highlighterColor = 0xFFFFEB3B,
    this.highlighterOpacity = 0.4,
    this.underlineColor = 0xFFEF4444,
    this.textColor = 0xFFFFFFFF,
    this.textFontSize = 0.022,
    this.shapeBorderColor = 0xFFEF4444,
    this.shapeFillColor,
    this.shapeBorderWidth = 0.004,
    this.palmRejectionEnabled = false,
    this.freehandHighlighterThickness = 0.025,
  });

  Map<String, dynamic> toJson() => {
        'pc': penColor,
        'pt': penThickness,
        'po': penOpacity,
        'hc': highlighterColor,
        'ho': highlighterOpacity,
        'uc': underlineColor,
        'tc': textColor,
        'tfs': textFontSize,
        'sbc': shapeBorderColor,
        'sfc': shapeFillColor,
        'sbw': shapeBorderWidth,
        'palm': palmRejectionEnabled,
        'fht': freehandHighlighterThickness,
      };

  factory PdfToolSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PdfToolSettings();
    return PdfToolSettings(
      penColor: json['pc'] as int? ?? 0xFFEF4444,
      penThickness: (json['pt'] as num?)?.toDouble() ?? 0.003,
      penOpacity: (json['po'] as num?)?.toDouble() ?? 1.0,
      highlighterColor: json['hc'] as int? ?? 0xFFFFEB3B,
      highlighterOpacity: (json['ho'] as num?)?.toDouble() ?? 0.4,
      underlineColor: json['uc'] as int? ?? 0xFFEF4444,
      textColor: json['tc'] as int? ?? 0xFFFFFFFF,
      textFontSize: (json['tfs'] as num?)?.toDouble() ?? 0.022,
      shapeBorderColor: json['sbc'] as int? ?? 0xFFEF4444,
      shapeFillColor: json['sfc'] as int?,
      shapeBorderWidth: (json['sbw'] as num?)?.toDouble() ?? 0.004,
      palmRejectionEnabled: json['palm'] as bool? ?? false,
      freehandHighlighterThickness: (json['fht'] as num?)?.toDouble() ?? 0.025,
    );
  }
}
