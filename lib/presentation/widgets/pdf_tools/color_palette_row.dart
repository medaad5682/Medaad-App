import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

/// شريط لوحة ألوان كاملة قابلة لإعادة الاستخدام في كل الأدوات (قلم، هايلايتر،
/// تسطير، نص، أشكال). يعرض مجموعة ألوان شائعة بالإضافة إلى زر "لون مخصص" يفتح
/// منتقي ألوان كامل (Hue/Saturation + شفافية اختيارية).
class ColorPaletteRow extends StatelessWidget {
  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;
  final bool allowTransparentOption; // لخيار "بلا تعبئة" في الأشكال
  final VoidCallback? onTransparentSelected;
  final bool isTransparentSelected;

  const ColorPaletteRow({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
    this.allowTransparentOption = false,
    this.onTransparentSelected,
    this.isTransparentSelected = false,
  });

  static const List<Color> _palette = [
    Color(0xFFFFFFFF), // أبيض
    Color(0xFF000000), // أسود
    Color(0xFFEF4444), // أحمر
    Color(0xFFF97316), // برتقالي
    Color(0xFFFFEB3B), // أصفر
    Color(0xFF22C55E), // أخضر
    Color(0xFF06B6D4), // سماوي
    Color(0xFF3B82F6), // أزرق
    Color(0xFF8B5CF6), // بنفسجي
    Color(0xFFEC4899), // وردي
    Color(0xFF92400E), // بني
    Color(0xFF6B7280), // رمادي
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (allowTransparentOption) ...[
            _transparentCircle(),
            const SizedBox(width: 6),
          ],
          ..._palette.map((c) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: _circle(c),
              )),
          _customColorButton(context),
        ],
      ),
    );
  }

  Widget _transparentCircle() {
    return GestureDetector(
      onTap: onTransparentSelected,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isTransparentSelected ? AppColors.accentYellow : Colors.white24,
            width: isTransparentSelected ? 2.5 : 1,
          ),
        ),
        child: CustomPaint(painter: _CheckerboardPainter()),
      ),
    );
  }

  Widget _circle(Color color) {
    final bool selected = !isTransparentSelected &&
        selectedColor.value == color.value;
    return GestureDetector(
      onTap: () => onColorSelected(color),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.accentYellow : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.accentYellow.withOpacity(0.5), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }

  Widget _customColorButton(BuildContext context) {
    final bool isCustom = !isTransparentSelected && !_palette.any((c) => c.value == selectedColor.value);
    return GestureDetector(
      onTap: () async {
        final picked = await showDialog<Color>(
          context: context,
          builder: (ctx) => _CustomColorDialog(initial: selectedColor),
        );
        if (picked != null) onColorSelected(picked);
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isCustom ? AppColors.accentYellow : Colors.white24,
            width: isCustom ? 2.5 : 1,
          ),
          gradient: const SweepGradient(colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ]),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 16),
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()..color = Colors.white;
    final paintDark = Paint()..color = Colors.grey.shade400;
    canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height)));
    const cell = 6.0;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isDark = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isDark ? paintDark : paintLight);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// منتقي لون مخصص كامل (Hue + Saturation/Brightness عبر شريطين، مع معاينة فورية).
class _CustomColorDialog extends StatefulWidget {
  final Color initial;
  const _CustomColorDialog({required this.initial});

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(AppLocalizations.of(context)!.chooseColorTitle, style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: current,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 16),
            // درجة اللون (Hue)
            Container(
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ]),
              ),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: _hsv.hue,
                  min: 0,
                  max: 360,
                  activeColor: Colors.transparent,
                  inactiveColor: Colors.transparent,
                  onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // التشبع
            Row(children: [
              Text(AppLocalizations.of(context)!.saturationLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _hsv.saturation,
                  activeColor: AppColors.accentYellow,
                  onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
                ),
              ),
            ]),
            // السطوع
            Row(children: [
              Text(AppLocalizations.of(context)!.brightnessLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _hsv.value,
                  activeColor: AppColors.accentYellow,
                  onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
                ),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel, style: const TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentYellow, foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(context, current),
          child: Text(AppLocalizations.of(context)!.selectAction, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
