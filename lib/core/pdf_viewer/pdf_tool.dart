import 'package:flutter/widgets.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

/// كل الأدوات المتاحة في شريط أدوات القارئ بعد التحديث.
enum PdfTool {
  none,
  pen,
  highlighter,        // تمييز نص حقيقي (مرتبط بتحديد النص)
  freehandHighlighter, // تمييز حر بالرسم اليدوي (هايلايتر قلم)
  eraser,
  comment, // أداة "الملاحظات" القديمة (أيقونة + نص)
  underline,
  text, // أداة "النص" الجديدة (كتابة نص يوضع على الصفحة)
  shape, // أداة الأشكال (سهم/دائرة/مربع/مستطيل)
  image, // إدراج صورة
}

extension PdfToolLabel on PdfTool {
  /// نص مختصر لكل أداة (يُستخدم في تلميحات الأدوات Tooltips)، حسب اللغة الحالية.
  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (this) {
      case PdfTool.none:
        return '';
      case PdfTool.pen:
        return l10n.pdfToolPen;
      case PdfTool.highlighter:
        return l10n.pdfToolHighlightText;
      case PdfTool.freehandHighlighter:
        return l10n.pdfToolFreehandHighlight;
      case PdfTool.eraser:
        return l10n.pdfToolEraser;
      case PdfTool.comment:
        return l10n.pdfToolComment;
      case PdfTool.underline:
        return l10n.pdfToolUnderline;
      case PdfTool.text:
        return l10n.pdfToolText;
      case PdfTool.shape:
        return l10n.pdfToolShapes;
      case PdfTool.image:
        return l10n.pdfToolImage;
    }
  }
}
