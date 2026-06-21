import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/image_annotation_model.dart';

/// عنصر صورة واحدة موضوعة على صفحة الـ PDF:
/// - قابلة للسحب والتحريك بالضغط على جسم الصورة.
/// - مقابض تغيير الحجم في **أربع زوايا** مع استجابة سلسة وفورية.
/// - زر حذف (سلة) في الزاوية العلوية اليسرى.
/// - جميع عناصر التحكم تظهر فقط في وضع التعديل.
class MovableResizableImage extends StatefulWidget {
  final ImageAnnotationModel image;
  final double pageWidth;
  final double pageHeight;
  final bool editable;
  final ValueChanged<Offset> onMoveDelta;
  final ValueChanged<Offset> onResizeDelta;
  final VoidCallback onDelete;

  const MovableResizableImage({
    super.key,
    required this.image,
    required this.pageWidth,
    required this.pageHeight,
    required this.editable,
    required this.onMoveDelta,
    required this.onResizeDelta,
    required this.onDelete,
  });

  @override
  State<MovableResizableImage> createState() => _MovableResizableImageState();
}

class _MovableResizableImageState extends State<MovableResizableImage> {
  // تجميع الدلتا المحلية حتى نعيد البناء محلياً دون إعادة رسم الكل
  double _localDx = 0;
  double _localDy = 0;
  double _localDw = 0;
  double _localDh = 0;

  @override
  Widget build(BuildContext context) {
    final widthPx = widget.image.width * widget.pageWidth + _localDw;
    final heightPx = widget.image.height * widget.pageHeight + _localDh;
    const handleSize = 28.0;
    const handleOffset = handleSize / 2;

    return SizedBox(
      width: widthPx,
      height: heightPx,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // جسم الصورة - السحب للتحريك
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: widget.editable
                ? (details) {
                    // تحديث فوري بدون انتظار setState الخارجي
                    setState(() {
                      _localDx += details.delta.dx;
                      _localDy += details.delta.dy;
                    });
                    widget.onMoveDelta(Offset(
                      details.delta.dx / widget.pageWidth,
                      details.delta.dy / widget.pageHeight,
                    ));
                  }
                : null,
            onPanEnd: widget.editable
                ? (_) => setState(() {
                      _localDx = 0;
                      _localDy = 0;
                    })
                : null,
            child: Container(
              width: widthPx,
              height: heightPx,
              decoration: BoxDecoration(
                border: widget.editable
                    ? Border.all(
                        color: AppColors.accentYellow.withOpacity(0.8), width: 1.5)
                    : null,
              ),
              child: Image.file(
                File(widget.image.path),
                width: widthPx,
                height: heightPx,
                fit: BoxFit.fill,
                gaplessPlayback: true, // تمنع الوميض عند تغيير الحجم
                errorBuilder: (context, error, stack) => Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child:
                      const Icon(Icons.broken_image_outlined, color: Colors.white54),
                ),
              ),
            ),
          ),

          if (widget.editable) ...[
            // ── مقبض يمين-أسفل (تكبير/تصغير) ──
            Positioned(
              right: -handleOffset,
              bottom: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                onDelta: (d) {
                  setState(() {
                    _localDw += d.dx;
                    _localDh += d.dy;
                  });
                  widget.onResizeDelta(
                    Offset(d.dx / widget.pageWidth, d.dy / widget.pageHeight),
                  );
                },
                onEnd: () => setState(() {
                  _localDw = 0;
                  _localDh = 0;
                }),
              ),
            ),
            // ── مقبض يسار-أسفل ──
            Positioned(
              left: -handleOffset,
              bottom: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                onDelta: (d) {
                  setState(() {
                    _localDw -= d.dx;
                    _localDh += d.dy;
                  });
                  widget.onResizeDelta(
                    Offset(-d.dx / widget.pageWidth, d.dy / widget.pageHeight),
                  );
                },
                onEnd: () => setState(() {
                  _localDw = 0;
                  _localDh = 0;
                }),
              ),
            ),
            // ── مقبض يمين-أعلى ──
            Positioned(
              right: -handleOffset,
              top: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                onDelta: (d) {
                  setState(() {
                    _localDw += d.dx;
                    _localDh -= d.dy;
                  });
                  widget.onResizeDelta(
                    Offset(d.dx / widget.pageWidth, -d.dy / widget.pageHeight),
                  );
                },
                onEnd: () => setState(() {
                  _localDw = 0;
                  _localDh = 0;
                }),
              ),
            ),
            // ── زر الحذف (سلة) في يسار-أعلى ──
            Positioned(
              left: -handleOffset,
              top: -handleOffset,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: const BoxDecoration(
                      color: Colors.redAccent, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.delete_outline, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مقبض دائري صغير لتغيير الحجم بالسحب — مع معاودة استدعاء onEnd.
class _ResizeHandle extends StatelessWidget {
  final IconData icon;
  final ValueChanged<Offset> onDelta;
  final VoidCallback onEnd;

  const _ResizeHandle({required this.icon, required this.onDelta, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDelta(details.delta),
      onPanEnd: (_) => onEnd(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.accentYellow,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 14, color: Colors.black),
      ),
    );
  }
}
