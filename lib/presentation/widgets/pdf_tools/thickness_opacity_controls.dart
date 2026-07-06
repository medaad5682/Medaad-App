import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// أشرطة تحكم بالسماكة والشفافية، قابلة لإعادة الاستخدام لأي أداة رسم
/// (القلم، الهايلايتر، حدود الأشكال...).
class ThicknessOpacityControls extends StatelessWidget {
  final double thickness;
  final double minThickness;
  final double maxThickness;
  final ValueChanged<double> onThicknessChanged;

  final double? opacity; // null لإخفاء شريط الشفافية (مثل حدود الأشكال غير الشفافة)
  final ValueChanged<double>? onOpacityChanged;

  final Color previewColor;

  const ThicknessOpacityControls({
    super.key,
    required this.thickness,
    required this.onThicknessChanged,
    required this.previewColor,
    this.minThickness = 0.001,
    this.maxThickness = 0.08,
    this.opacity,
    this.onOpacityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.line_weight, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3),
                child: Slider(
                  value: thickness,
                  min: minThickness,
                  max: maxThickness,
                  activeColor: previewColor,
                  inactiveColor: previewColor.withOpacity(0.25),
                  onChanged: onThicknessChanged,
                ),
              ),
            ),
            // معاينة مباشرة لسماكة الخط الحالية
            Container(
              width: 28,
              height: (thickness / maxThickness * 14).clamp(2.0, 14.0),
              decoration: BoxDecoration(
                color: previewColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        if (opacity != null && onOpacityChanged != null)
          Row(
            children: [
              Icon(Icons.opacity, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 3),
                  child: Slider(
                    value: opacity!,
                    min: 0.05,
                    max: 1.0,
                    activeColor: previewColor,
                    inactiveColor: previewColor.withOpacity(0.25),
                    onChanged: onOpacityChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  "${(opacity! * 100).toInt()}%",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
