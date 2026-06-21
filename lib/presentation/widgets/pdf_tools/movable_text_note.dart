import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/text_note_model.dart';

/// عنصر نص واحد موضوع على صفحة الـ PDF: قابل للسحب (في وضع التعديل)،
/// والنقر عليه يفتح محرر نص + خيارات لون/حذف.
class MovableTextNote extends StatelessWidget {
  final TextNoteModel note;
  final double pageWidth;
  final bool editable;
  final ValueChanged<Offset> onDragDelta; // بالوحدات النسبية
  final VoidCallback onTap;

  const MovableTextNote({
    super.key,
    required this.note,
    required this.pageWidth,
    required this.editable,
    required this.onDragDelta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = note.fontSize * pageWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanUpdate: editable
          ? (details) => onDragDelta(Offset(details.delta.dx / pageWidth, details.delta.dy / pageWidth))
          : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: pageWidth * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: editable
            ? BoxDecoration(
                border: Border.all(color: AppColors.accentYellow.withOpacity(0.6), width: 1),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          note.text,
          style: TextStyle(
            color: Color(note.color),
            fontSize: fontSize,
            fontWeight: note.bold ? FontWeight.bold : FontWeight.normal,
          ),
          // الكتابة المختلطة (عربي/إنجليزي) تُعرض بترتيب صحيح تلقائياً عبر
          // خوارزمية Bidi المدمجة في Flutter عند ضبط الاتجاه تلقائياً.
          textDirection: _detectDirection(note.text),
        ),
      ),
    );
  }

  /// يحدد اتجاه النص العام بناءً على أول حرف "قوي" (عربي أو لاتيني) فيه،
  /// مع ترك خوارزمية Bidi الداخلية في Flutter تتعامل مع الأجزاء المختلطة
  /// داخل الفقرة نفسها بشكل صحيح (لا حاجة لتقسيم النص يدوياً).
  TextDirection _detectDirection(String text) {
    for (final rune in text.runes) {
      // نطاقات الأحرف العربية الأساسية
      if (rune >= 0x0600 && rune <= 0x06FF) return TextDirection.rtl;
      // نطاقات الأحرف اللاتينية الأساسية
      if ((rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A)) {
        return TextDirection.ltr;
      }
    }
    return TextDirection.rtl; // افتراضي مناسب لتطبيق عربي
  }
}
