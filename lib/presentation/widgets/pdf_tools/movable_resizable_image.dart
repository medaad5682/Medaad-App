import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/image_annotation_model.dart';

/// عنصر صورة واحدة موضوعة على صفحة الـ PDF: قابلة للسحب وتغيير الحجم
/// عبر مقبض في الزاوية السفلية اليمنى، مع زر حذف يظهر فقط في وضع التعديل.
class MovableResizableImage extends StatelessWidget {
  final ImageAnnotationModel image;
  final double pageWidth;
  final double pageHeight;
  final bool editable;
  final ValueChanged<Offset> onMoveDelta; // نسبي لعرض/ارتفاع الصفحة
  final ValueChanged<Offset> onResizeDelta; // نسبي لعرض/ارتفاع الصفحة
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

    return SizedBox(
      width: widthPx,
      height: heightPx,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: editable
                ? (details) => onMoveDelta(
                      Offset(details.delta.dx / pageWidth, details.delta.dy / pageHeight),
                    )
                : null,
            child: Container(
              decoration: BoxDecoration(
                border: editable
                    ? Border.all(color: AppColors.accentYellow.withOpacity(0.7), width: 1.5)
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
                  child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                ),
              ),
            ),
          ),
          if (editable) ...[
            // مقبض تغيير الحجم
            Positioned(
              right: -10,
              bottom: -10,
              child: GestureDetector(
                onPanUpdate: (details) => onResizeDelta(
                  Offset(details.delta.dx / pageWidth, details.delta.dy / pageHeight),
                ),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.open_in_full, size: 12, color: Colors.black),
                ),
              ),
            ),
            // زر الحذف
            Positioned(
              right: -10,
              top: -10,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
