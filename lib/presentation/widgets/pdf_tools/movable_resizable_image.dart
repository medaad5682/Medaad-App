import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/image_annotation_model.dart';

/// عنصر صورة واحدة موضوعة على صفحة الـ PDF:
/// - قابلة للسحب والتحريك بالضغط على جسم الصورة.
/// - زر حذف في الزاوية العلوية اليسرى.
/// - مقابض تغيير الحجم على المنتصفات والزاوية:
///   • منتصف اليمين  → يوسّع/يُضيّق الحافة اليمنى أفقياً فقط.
///   • منتصف اليسار  → يوسّع/يُضيّق الحافة اليسرى أفقياً فقط (تحريك + تغيير عرض).
///   • منتصف الأعلى  → يوسّع/يُضيّق الحافة العليا رأسياً فقط (تحريك + تغيير ارتفاع).
///   • منتصف الأسفل  → يوسّع/يُضيّق الحافة السفلية رأسياً فقط.
///   • الزاوية السفلية اليمنى → تغيير متناسب للعرض والارتفاع معاً.
/// - الحجم النهائي يُحفَظ بدقة عند رفع الإصبع (onPanEnd).
class MovableResizableImage extends StatefulWidget {
  final ImageAnnotationModel image;
  final double pageWidth;
  final double pageHeight;
  final bool editable;
  final ValueChanged<Offset> onMoveDelta;

  /// [onResizeDelta] يُستدعى أثناء السحب (معاينة مباشرة).
  final ValueChanged<Offset> onResizeDelta;

  /// [onResizeEnd] يُستدعى مرة واحدة عند رفع الإصبع لحفظ الحجم النهائي الدقيق.
  final void Function(double finalWidth, double finalHeight) onResizeEnd;

  /// [onMoveEnd] يُستدعى عند انتهاء سحب الحافة اليسرى/العليا لتثبيت موضع الصورة.
  final void Function(double finalDx, double finalDy)? onMoveEnd;

  final VoidCallback onDelete;

  const MovableResizableImage({
    super.key,
    required this.image,
    required this.pageWidth,
    required this.pageHeight,
    required this.editable,
    required this.onMoveDelta,
    required this.onResizeDelta,
    required this.onResizeEnd,
    this.onMoveEnd,
    required this.onDelete,
  });

  @override
  State<MovableResizableImage> createState() => _MovableResizableImageState();
}

class _MovableResizableImageState extends State<MovableResizableImage> {
  // دلتا محلية مؤقتة أثناء السحب فقط — تُصفَّر عند رفع الإصبع
  double _localDw = 0;
  double _localDh = 0;

  double get _widthPx  => (widget.image.width  * widget.pageWidth  + _localDw).clamp(40.0, double.infinity);
  double get _heightPx => (widget.image.height * widget.pageHeight + _localDh).clamp(40.0, double.infinity);

  // ── مساعد: إرسال resize + حفظ الحجم النهائي عند رفع الإصبع ──
  void _commitResize() {
    setState(() {
      _localDw = 0;
      _localDh = 0;
    });
    widget.onResizeEnd(
      widget.image.width,
      widget.image.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    const handleSize   = 28.0;
    const handleOffset = handleSize / 2;

    final w = _widthPx;
    final h = _heightPx;

    return SizedBox(
      width:  w,
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
              width:  w,
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
                width:  w,
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
              top:  -handleOffset,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width:  handleSize,
                  height: handleSize,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline, size: 15, color: Colors.white),
                ),
              ),
            ),

            // ── منتصف اليمين: يحرّك الحافة اليمنى أفقياً فقط ──
            Positioned(
              right: -handleOffset,
              top:   h / 2 - handleOffset,
              child: _ResizeHandle(
                icon: Icons.drag_handle,
                rotate: true,
                onDelta: (d) {
                  final newW = (w + d.dx).clamp(40.0, double.infinity);
                  final dw   = newW - w;
                  setState(() => _localDw += dw);
                  widget.onResizeDelta(Offset(dw / widget.pageWidth, 0));
                },
                onEnd: _commitResize,
              ),
            ),

            // ── منتصف اليسار: يحرّك الحافة اليسرى أفقياً فقط ──
            Positioned(
              left: -handleOffset,
              top:  h / 2 - handleOffset,
              child: _ResizeHandle(
                icon: Icons.drag_handle,
                rotate: true,
                onDelta: (d) {
                  // الحافة اليسرى: يزيد العرض عند السحب لليسار (dx سالب)
                  final newW = (w - d.dx).clamp(40.0, double.infinity);
                  final dw   = newW - w;
                  setState(() => _localDw += dw);
                  widget.onResizeDelta(Offset(dw / widget.pageWidth, 0));
                  // تحريك الصورة يساراً لتثبيت الحافة اليمنى
                  widget.onMoveDelta(Offset(-dw / widget.pageWidth, 0));
                },
                onEnd: () {
                  setState(() { _localDw = 0; });
                  widget.onResizeEnd(widget.image.width, widget.image.height);
                  widget.onMoveEnd?.call(widget.image.dx, widget.image.dy);
                },
              ),
            ),

            // ── منتصف الأعلى: يحرّك الحافة العليا رأسياً فقط ──
            Positioned(
              top:  -handleOffset,
              left: w / 2 - handleOffset,
              child: _ResizeHandle(
                icon: Icons.drag_handle,
                rotate: false,
                onDelta: (d) {
                  final newH = (h - d.dy).clamp(40.0, double.infinity);
                  final dh   = newH - h;
                  setState(() => _localDh += dh);
                  widget.onResizeDelta(Offset(0, dh / widget.pageHeight));
                  widget.onMoveDelta(Offset(0, -dh / widget.pageHeight));
                },
                onEnd: () {
                  setState(() { _localDh = 0; });
                  widget.onResizeEnd(widget.image.width, widget.image.height);
                  widget.onMoveEnd?.call(widget.image.dx, widget.image.dy);
                },
              ),
            ),

            // ── منتصف الأسفل: يحرّك الحافة السفلية رأسياً فقط ──
            Positioned(
              bottom: -handleOffset,
              left:   w / 2 - handleOffset,
              child: _ResizeHandle(
                icon: Icons.drag_handle,
                rotate: false,
                onDelta: (d) {
                  final newH = (h + d.dy).clamp(40.0, double.infinity);
                  final dh   = newH - h;
                  setState(() => _localDh += dh);
                  widget.onResizeDelta(Offset(0, dh / widget.pageHeight));
                },
                onEnd: _commitResize,
              ),
            ),

            // ── الزاوية السفلية اليمنى: تغيير متناسب (عرض وارتفاع معاً) ──
            Positioned(
              right:  -handleOffset,
              bottom: -handleOffset,
              child: _ResizeHandle(
                icon: Icons.open_in_full,
                rotate: false,
                onDelta: (d) {
                  setState(() {
                    _localDw += d.dx;
                    _localDh += d.dy;
                  });
                  widget.onResizeDelta(Offset(
                    d.dx / widget.pageWidth,
                    d.dy / widget.pageHeight,
                  ));
                },
                onEnd: _commitResize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مقبض دائري صغير لتغيير الحجم بالسحب.
/// [rotate] = true يعرض الأيقونة مُدارة 90° (للحواف الأفقية → سحب رأسي).
class _ResizeHandle extends StatelessWidget {
  final IconData icon;
  final bool rotate;
  final ValueChanged<Offset> onDelta;
  final VoidCallback onEnd;

  const _ResizeHandle({
    required this.icon,
    required this.rotate,
    required this.onDelta,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDelta(details.delta),
      onPanEnd: (_) => onEnd(),
      child: Container(
        width:  28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.accentYellow,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: RotatedBox(
          quarterTurns: rotate ? 1 : 0,
          child: Icon(icon, size: 14, color: Colors.black),
        ),
      ),
    );
  }
}
