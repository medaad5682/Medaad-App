import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/image_annotation_model.dart';

/// عنصر صورة واحدة موضوعة على صفحة الـ PDF:
/// - قابلة للسحب والتحريك بالضغط على جسم الصورة.
/// - زر حذف في الزاوية العلوية اليسرى.
/// - مقبض تكبير/تصغير شامل في الزاوية السفلية اليمنى (يعمل بشكل صحيح).
/// - مقابض تغيير الحجم على منتصف كل ضلع (أعلى/أسفل/يسار/يمين).
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
  double _localDw = 0;
  double _localDh = 0;

  // دوال مساعدة لإرجاع أبعاد الصورة الفعلية حسب المعاينة المحلية
  double get _widthPx => widget.image.width * widget.pageWidth + _localDw;
  double get _heightPx => widget.image.height * widget.pageHeight + _localDh;

  @override
  Widget build(BuildContext context) {
    const handleSize = 28.0;
    const handleOffset = handleSize / 2;

    final w = _widthPx.clamp(40.0, double.infinity);
    final h = _heightPx.clamp(40.0, double.infinity);

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── جسم الصورة: السحب للتحريك ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: widget.editable
                ? (details) {
                    widget.onMoveDelta(Offset(
                      details.delta.dx / widget.pageWidth,
                      details.delta.dy / widget.pageHeight,
                    ));
                  }
                : null,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                border: widget.editable
                    ? Border.all(
                        color: AppColors.accentYellow.withOpacity(0.8),
                        width: 1.5)
                    : null,
              ),
              child: Image.file(
                File(widget.image.path),
                width: w,
                height: h,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                ),
              ),
            ),
          ),

          if (widget.editable) ...[
            // ── زر الحذف: الزاوية العلوية اليسرى ──
            Positioned(
              left: -handleOffset,
              top: -handleOffset,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline, size: 15, color: Colors.white),
                ),
              ),
            ),

            // ── مقبض تكبير/تصغير شامل: الزاوية السفلية اليمنى ──
            Positioned(
              right: -handleOffset,
              bottom: -handleOffset,
              child: _EdgeHandle(
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

            // ── مقبض الحافة العلوية: يُصغّر/يُكبّر من الأعلى (يُحرّك الحافة العليا) ──
            Positioned(
              top: -handleOffset,
              left: w / 2 - handleOffset,
              child: _EdgeHandle(
                icon: Icons.unfold_less,
                onDelta: (d) {
                  final newH = (h - d.dy).clamp(40.0, double.infinity);
                  final dh = newH - h;
                  setState(() => _localDh += dh);
                  // تغيير الارتفاع فقط (الحافة العليا تتحرك = تغيير الـ dy والارتفاع)
                  widget.onResizeDelta(Offset(0, -d.dy / widget.pageHeight));
                  // تحريك الصورة للأعلى بمقدار التغيير لتثبيت الحافة السفلية
                  widget.onMoveDelta(Offset(0, d.dy / widget.pageHeight));
                },
                onEnd: () => setState(() => _localDh = 0),
              ),
            ),

            // ── مقبض الحافة السفلية: يُصغّر/يُكبّر من الأسفل ──
            Positioned(
              bottom: -handleOffset,
              left: w / 2 - handleOffset,
              child: _EdgeHandle(
                icon: Icons.unfold_more,
                onDelta: (d) {
                  setState(() => _localDh += d.dy);
                  widget.onResizeDelta(Offset(0, d.dy / widget.pageHeight));
                },
                onEnd: () => setState(() => _localDh = 0),
              ),
            ),

            // ── مقبض الحافة اليسرى: يُصغّر/يُكبّر من اليسار ──
            Positioned(
              left: -handleOffset,
              top: h / 2 - handleOffset,
              child: _EdgeHandle(
                icon: Icons.unfold_less,
                onDelta: (d) {
                  final newW = (w - d.dx).clamp(40.0, double.infinity);
                  final dw = newW - w;
                  setState(() => _localDw += dw);
                  widget.onResizeDelta(Offset(-d.dx / widget.pageWidth, 0));
                  widget.onMoveDelta(Offset(d.dx / widget.pageWidth, 0));
                },
                onEnd: () => setState(() => _localDw = 0),
              ),
            ),

            // ── مقبض الحافة اليمنى: يُصغّر/يُكبّر من اليمين ──
            Positioned(
              right: -handleOffset,
              top: h / 2 - handleOffset,
              child: _EdgeHandle(
                icon: Icons.unfold_more,
                onDelta: (d) {
                  setState(() => _localDw += d.dx);
                  widget.onResizeDelta(Offset(d.dx / widget.pageWidth, 0));
                },
                onEnd: () => setState(() => _localDw = 0),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مقبض دائري صغير لتغيير الحجم بالسحب.
class _EdgeHandle extends StatelessWidget {
  final IconData icon;
  final ValueChanged<Offset> onDelta;
  final VoidCallback onEnd;

  const _EdgeHandle({required this.icon, required this.onDelta, required this.onEnd});

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
