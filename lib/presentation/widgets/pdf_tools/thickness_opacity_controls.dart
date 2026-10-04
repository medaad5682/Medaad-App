import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// أشرطة تحكم بالسماكة والشفافية، قابلة لإعادة الاستخدام لأي أداة رسم
/// (القلم، الهايلايتر، حدود الأشكال...).
///
/// [compact]: وضع مضغوط لشريط الأدوات العائم — مقابض أصغر وارتفاع أقل، ويُعرَض
/// شريطا السماكة والشفافية **جنباً إلى جنب** في صف واحد عندما يتسع العرض
/// (بدل صفّين متراكبين)، فيصغر ارتفاع اللوحة إلى النصف تقريباً.
class ThicknessOpacityControls extends StatelessWidget {
  final double thickness;
  final double minThickness;
  final double maxThickness;
  final ValueChanged<double> onThicknessChanged;

  final double? opacity; // null لإخفاء شريط الشفافية (مثل حدود الأشكال غير الشفافة)
  final ValueChanged<double>? onOpacityChanged;

  final Color previewColor;
  final bool compact;

  const ThicknessOpacityControls({
    super.key,
    required this.thickness,
    required this.onThicknessChanged,
    required this.previewColor,
    this.minThickness = 0.001,
    this.maxThickness = 0.08,
    this.opacity,
    this.onOpacityChanged,
    this.compact = false,
  });

  bool get _hasOpacity => opacity != null && onOpacityChanged != null;

  SliderThemeData _sliderTheme(BuildContext context) {
    final base = SliderTheme.of(context);
    if (!compact) return base.copyWith(trackHeight: 3);
    return base.copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    );
  }

  Widget _thicknessRow(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.line_weight, size: 16, color: AppColors.textSecondary),
        SizedBox(width: compact ? 4 : 8),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value: thickness.clamp(minThickness, maxThickness),
              min: minThickness,
              max: maxThickness,
              activeColor: AppColors.visibleOnToolSurface(previewColor),
              inactiveColor: AppColors.toolTrackInactive,
              onChanged: onThicknessChanged,
            ),
          ),
        ),
        // معاينة مباشرة لسماكة الخط الحالية
        Container(
          width: compact ? 22 : 28,
          height: (thickness / maxThickness * 14).clamp(2.0, 14.0),
          decoration: BoxDecoration(
            color: previewColor,
            borderRadius: BorderRadius.circular(4),
            // حد خفيف كي تظهر المعاينة حتى لو كان اللون أبيض/أسود فوق السطح.
            border: Border.all(color: AppColors.toolBorder, width: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _opacityRow(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.opacity, size: 16, color: AppColors.textSecondary),
        SizedBox(width: compact ? 4 : 8),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value: opacity!,
              min: 0.05,
              max: 1.0,
              activeColor: AppColors.visibleOnToolSurface(previewColor),
              inactiveColor: AppColors.toolTrackInactive,
              onChanged: onOpacityChanged,
            ),
          ),
        ),
        SizedBox(
          width: compact ? 32 : 36,
          child: Text(
            "${(opacity! * 100).toInt()}%",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact && _hasOpacity) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // عرض كافٍ: صف واحد (سماكة | شفافية). ضيق (هاتف): صفّان كما كان.
          if (constraints.maxWidth >= 380) {
            return Row(
              children: [
                Expanded(child: _thicknessRow(context)),
                const SizedBox(width: 12),
                Expanded(child: _opacityRow(context)),
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _thicknessRow(context),
              _opacityRow(context),
            ],
          );
        },
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _thicknessRow(context),
        if (_hasOpacity) _opacityRow(context),
      ],
    );
  }
}
