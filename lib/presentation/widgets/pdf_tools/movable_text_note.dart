import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/text_note_model.dart';

/// عنصر نص واحد موضوع على صفحة الـ PDF:
/// - قابل للسحب (في وضع التعديل).
/// - يحتوي على أيقونة حذف في الزاوية العلوية اليسرى.
/// - النقر عليه في وضع التعديل يفتح محرر نص موسّع يشمل:
///   ضبط حجم الخط، تغيير اللون بمعاينة فورية، وخيار الحذف.
class MovableTextNote extends StatelessWidget {
  final TextNoteModel note;
  final double pageWidth;
  final bool editable;
  final ValueChanged<Offset> onDragDelta; // بالوحدات النسبية
  final VoidCallback onTap;
  final VoidCallback? onDelete; // حذف مباشر من أيقونة الزاوية

  const MovableTextNote({
    super.key,
    required this.note,
    required this.pageWidth,
    required this.editable,
    required this.onDragDelta,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = note.fontSize * pageWidth;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onPanUpdate: editable
              ? (details) => onDragDelta(
                    Offset(details.delta.dx / pageWidth, details.delta.dy / pageWidth))
              : null,
          child: Container(
            constraints: BoxConstraints(maxWidth: pageWidth * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: editable
                ? BoxDecoration(
                    border: Border.all(
                        color: AppColors.accentYellow.withOpacity(0.7), width: 1.2),
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
              textDirection: _detectDirection(note.text),
            ),
          ),
        ),
        // أيقونة الحذف في الزاوية العلوية اليسرى (تظهر فقط في وضع التعديل)
        if (editable && onDelete != null)
          Positioned(
            left: -10,
            top: -10,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration:
                    const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, size: 13, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  TextDirection _detectDirection(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0600 && rune <= 0x06FF) return TextDirection.rtl;
      if ((rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A)) {
        return TextDirection.ltr;
      }
    }
    return TextDirection.rtl;
  }
}
