/// كل الأدوات المتاحة في شريط أدوات القارئ بعد التحديث.
enum PdfTool {
  none,
  pen,
  highlighter, // تمييز نص حقيقي (وليس رسم حر كما كان سابقاً)
  eraser,
  comment, // أداة "الملاحظات" القديمة (أيقونة + نص)
  underline,
  text, // أداة "النص" الجديدة (كتابة نص يوضع على الصفحة)
  shape, // أداة الأشكال (سهم/دائرة/مربع/مستطيل)
  image, // إدراج صورة
}

extension PdfToolLabel on PdfTool {
  /// نص عربي مختصر لكل أداة (يُستخدم في تلميحات الأدوات Tooltips).
  String get label {
    switch (this) {
      case PdfTool.none:
        return '';
      case PdfTool.pen:
        return 'قلم';
      case PdfTool.highlighter:
        return 'تمييز';
      case PdfTool.eraser:
        return 'ممحاة';
      case PdfTool.comment:
        return 'ملاحظة';
      case PdfTool.underline:
        return 'تسطير';
      case PdfTool.text:
        return 'نص';
      case PdfTool.shape:
        return 'أشكال';
      case PdfTool.image:
        return 'صورة';
    }
  }
}
