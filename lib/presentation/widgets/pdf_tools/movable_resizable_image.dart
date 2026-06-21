import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/image_annotation_model.dart';

/// عنصر صورة واحدة موضوعة على صفحة الـ PDF:
/// - قابلة للسحب والتحريك بالضغط على جسم الصورة.
/// - مقابض تغيير الحجم في **أربع زوايا** (يمين-أسفل، يسار-أسفل، يمين-أعلى، يسار-أعلى).
/// - زر حذف (سلة) في الزاوية العلوية اليسرى.
/// - جميع عناصر التحكم تظهر فقط في وضع التعديل.
class MovableResizableImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final widthPx = image.width * pageWidth;
    final heightPx = image.height * pageHeight;
    const handleSize = 24.0;
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
            onPanUpdate: editable
                ? (details) => onMoveDelta(
                      Offset(details.delta.dx / pageWidth,
                          details.delta.dy / pageHeight))
                : null,
            child: Container(
              width: widthPx,
              height: heightPx,
              decoration: BoxDecoration(
                border: editable
                    ? Border.all(
                        color: AppColors.accentYellow.withOpacity(0.8), width: 1.5)
                    : null,
              ),
              child: Image.file(
                File(image.path),
                width: widthPx,
                height: heightPx,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stack) => Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child:
                      const Icon(Icons.broken_image_outlined, color: Colors.white54),
                ),
              ),
            ),
          ),

          if (editable) ...[
            // ── مقبض يمين-أسفل ──
            Positioned(
              right: -handleOffset,
              bottom: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                onDelta: (d) =>
                    onResizeDelta(Offset(d.dx / pageWidth, d.dy / pageHeight)),
              ),
            ),
            // ── مقبض يسار-أسفل ──
            Positioned(
              left: -handleOffset,
              bottom: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                onDelta: (d) => onResizeDelta(
                    Offset(-d.dx / pageWidth, d.dy / pageHeight)),
              ),
            ),
            // ── مقبض يمين-أعلى ──
            Positioned(
              right: -handleOffset,
              top: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                onDelta: (d) => onResizeDelta(
                    Offset(d.dx / pageWidth, -d.dy / pageHeight)),
              ),
            ),
            // ── زر الحذف (سلة) في يسار-أعلى ──
            Positioned(
              left: -handleOffset,
              top: -handleOffset,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: const BoxDecoration(
                      color: Colors.redAccent, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.delete_outline, size: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مقبض دائري صغير لتغيير الحجم بالسحب.
class _ResizeHandle extends StatelessWidget {
  final IconData icon;
  final ValueChanged<Offset> onDelta;

  const _ResizeHandle({required this.icon, required this.onDelta});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => onDelta(details.delta),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.accentYellow,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(icon, size: 12, color: Colors.black),
      ),
    );
  }
}
