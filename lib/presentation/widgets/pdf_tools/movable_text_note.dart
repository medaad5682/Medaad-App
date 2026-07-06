import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/text_note_model.dart';

/// عنصر نص واحد موضوع على صفحة الـ PDF:
/// - قابل للسحب المباشر في وضع التعديل (بدون الحاجة لتفعيل أداة النص).
/// - يحتوي على أيقونة حذف في الزاوية العلوية اليسرى.
/// - النقر عليه في وضع التعديل يفتح محرر نص موسّع يشمل:
///   ضبط حجم الخط، تغيير اللون بمعاينة فورية، وخيار الحذف.
class MovableTextNote extends StatefulWidget {
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
  State<MovableTextNote> createState() => _MovableTextNoteState();
}

class _MovableTextNoteState extends State<MovableTextNote> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.note.fontSize * widget.pageWidth;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // ── السحب المباشر: يعمل في وضع التعديل بدون الحاجة لتفعيل أداة النص ──
          onPanStart: widget.editable
              ? (_) => setState(() => _isDragging = true)
              : null,
          onPanUpdate: widget.editable
              ? (details) => widget.onDragDelta(
                    Offset(
                      details.delta.dx / widget.pageWidth,
                      details.delta.dy / widget.pageWidth,
                    ),
                  )
              : null,
          onPanEnd: widget.editable
              ? (_) => setState(() => _isDragging = false)
              : null,
          onTap: _isDragging ? null : widget.onTap,
          child: Container(
            constraints: BoxConstraints(maxWidth: widget.pageWidth * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: widget.editable
                ? BoxDecoration(
                    border: Border.all(
                      color: _isDragging
                          ? AppColors.accentYellow
                          : AppColors.accentYellow.withOpacity(0.7),
                      width: _isDragging ? 2.0 : 1.2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    color: _isDragging
                        ? AppColors.accentYellow.withOpacity(0.05)
                        : null,
                  )
                : null,
            child: Text(
              widget.note.text,
              style: TextStyle(
                color: Color(widget.note.color),
                fontSize: fontSize,
                fontWeight: widget.note.bold ? FontWeight.bold : FontWeight.normal,
                decoration: widget.note.underline ? TextDecoration.underline : TextDecoration.none,
                decorationColor: Color(widget.note.color),
              ),
              textDirection: _detectDirection(widget.note.text),
            ),
          ),
        ),
        // أيقونة الحذف في الزاوية العلوية اليسرى (تظهر فقط في وضع التعديل)
        if (widget.editable && widget.onDelete != null)
          Positioned(
            left: -10,
            top: -10,
            child: GestureDetector(
              onTap: widget.onDelete,
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
