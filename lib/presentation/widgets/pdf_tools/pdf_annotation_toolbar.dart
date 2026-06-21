import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/pdf_viewer/pdf_tool.dart';
import '../../../core/models/shape_model.dart';
import 'color_palette_row.dart';
import 'thickness_opacity_controls.dart';

/// شريط الأدوات الرئيسي المعاد بناؤه لقارئ الـ PDF.
///
/// المبدأ العام: الضغط على أيقونة أداة نشطة بالفعل يقوم بإغلاقها (تعطيلها)،
/// تماشياً مع طلب "إغلاق/تعطيل الأداة عند الضغط عليها مرة ثانية".
class PdfAnnotationToolbar extends StatelessWidget {
  final PdfTool activeTool;
  final ValueChanged<PdfTool> onToolTap;

  // القلم
  final Color penColor;
  final double penThickness;
  final double penOpacity;
  final ValueChanged<Color> onPenColorChanged;
  final ValueChanged<double> onPenThicknessChanged;
  final ValueChanged<double> onPenOpacityChanged;

  // التمييز
  final Color highlighterColor;
  final double highlighterOpacity;
  final ValueChanged<Color> onHighlighterColorChanged;
  final ValueChanged<double> onHighlighterOpacityChanged;

  // التسطير
  final Color underlineColor;
  final ValueChanged<Color> onUnderlineColorChanged;

  // الممحاة
  final double eraserSize;
  final ValueChanged<double> onEraserSizeChanged;

  // النص
  final Color textColor;
  final ValueChanged<Color> onTextColorChanged;

  // الأشكال
  final ShapeType shapeType;
  final ValueChanged<ShapeType> onShapeTypeChanged;
  final Color shapeBorderColor;
  final ValueChanged<Color> onShapeBorderColorChanged;
  final Color? shapeFillColor; // null = شفاف
  final ValueChanged<Color?> onShapeFillColorChanged;
  final double shapeBorderWidth;
  final ValueChanged<double> onShapeBorderWidthChanged;

  // عام
  final VoidCallback onUndo;
  final VoidCallback onPickImage;
  final bool palmRejectionEnabled;
  final ValueChanged<bool> onPalmRejectionChanged;

  const PdfAnnotationToolbar({
    super.key,
    required this.activeTool,
    required this.onToolTap,
    required this.penColor,
    required this.penThickness,
    required this.penOpacity,
    required this.onPenColorChanged,
    required this.onPenThicknessChanged,
    required this.onPenOpacityChanged,
    required this.highlighterColor,
    required this.highlighterOpacity,
    required this.onHighlighterColorChanged,
    required this.onHighlighterOpacityChanged,
    required this.underlineColor,
    required this.onUnderlineColorChanged,
    required this.eraserSize,
    required this.onEraserSizeChanged,
    required this.textColor,
    required this.onTextColorChanged,
    required this.shapeType,
    required this.onShapeTypeChanged,
    required this.shapeBorderColor,
    required this.onShapeBorderColorChanged,
    required this.shapeFillColor,
    required this.onShapeFillColorChanged,
    required this.shapeBorderWidth,
    required this.onShapeBorderWidthChanged,
    required this.onUndo,
    required this.onPickImage,
    required this.palmRejectionEnabled,
    required this.onPalmRejectionChanged,
  });

  void _handleTap(PdfTool tool) {
    // الضغط على أداة مفعّلة حالياً يُغلقها (يعيدها إلى "بلا أداة")
    onToolTap(activeTool == tool ? PdfTool.none : tool);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolRow(),
          const SizedBox(height: 4),
          _buildContextPanel(context),
        ],
      ),
    );
  }

  Widget _buildToolRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toolIcon(Icons.edit, PdfTool.pen),
          const SizedBox(width: 6),
          _toolIcon(Icons.border_color, PdfTool.highlighter),
          const SizedBox(width: 6),
          _toolIcon(Icons.format_underlined, PdfTool.underline),
          const SizedBox(width: 6),
          _toolIcon(Icons.text_fields, PdfTool.text),
          const SizedBox(width: 6),
          _toolIcon(Icons.category_outlined, PdfTool.shape),
          const SizedBox(width: 6),
          _toolIcon(Icons.image_outlined, PdfTool.image, onTapOverride: onPickImage),
          const SizedBox(width: 6),
          _toolIcon(Icons.auto_fix_normal, PdfTool.eraser),
          const SizedBox(width: 6),
          _toolIcon(Icons.comment_outlined, PdfTool.comment),
          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: Colors.grey),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white, size: 20),
            onPressed: onUndo,
            tooltip: 'تراجع',
          ),
          const SizedBox(width: 4),
          _palmRejectionButton(),
        ],
      ),
    );
  }

  Widget _palmRejectionButton() {
    final bool on = palmRejectionEnabled;
    return GestureDetector(
      onTap: () => onPalmRejectionChanged(!on),
      child: Tooltip(
        message: on ? 'رفض راحة اليد: مفعّل' : 'رفض راحة اليد: معطّل',
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: on ? AppColors.accentYellow.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? AppColors.accentYellow : Colors.grey, width: 1),
          ),
          child: Icon(
            Icons.front_hand_outlined,
            size: 18,
            color: on ? AppColors.accentYellow : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _toolIcon(IconData icon, PdfTool tool, {VoidCallback? onTapOverride}) {
    final bool selected = activeTool == tool;
    return Tooltip(
      message: tool.label,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.accentYellow.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(icon, color: selected ? AppColors.accentYellow : Colors.grey, size: 20),
          onPressed: onTapOverride ?? () => _handleTap(tool),
        ),
      ),
    );
  }

  /// اللوحة السياقية التي تظهر تحت شريط الأدوات حسب الأداة النشطة حالياً
  /// (لوحة ألوان، سماكة/شفافية، اختيار شكل...).
  Widget _buildContextPanel(BuildContext context) {
    switch (activeTool) {
      case PdfTool.pen:
        return _penPanel(context);
      case PdfTool.highlighter:
        return _highlighterPanel(context);
      case PdfTool.underline:
        return _underlinePanel(context);
      case PdfTool.eraser:
        return _eraserPanel(context);
      case PdfTool.text:
        return _textPanel(context);
      case PdfTool.shape:
        return _shapePanel(context);
      case PdfTool.comment:
      case PdfTool.image:
      case PdfTool.none:
        return const SizedBox.shrink();
    }
  }

  Widget _penPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorPaletteRow(selectedColor: penColor, onColorSelected: onPenColorChanged),
        const SizedBox(height: 6),
        ThicknessOpacityControls(
          thickness: penThickness,
          onThicknessChanged: onPenThicknessChanged,
          opacity: penOpacity,
          onOpacityChanged: onPenOpacityChanged,
          previewColor: penColor,
        ),
      ],
    );
  }

  Widget _highlighterPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorPaletteRow(selectedColor: highlighterColor, onColorSelected: onHighlighterColorChanged),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.opacity, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: highlighterOpacity,
                min: 0.1,
                max: 0.8,
                activeColor: highlighterColor,
                inactiveColor: highlighterColor.withOpacity(0.25),
                onChanged: onHighlighterOpacityChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                "${(highlighterOpacity * 100).toInt()}%",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _underlinePanel(BuildContext context) {
    return ColorPaletteRow(selectedColor: underlineColor, onColorSelected: onUnderlineColorChanged);
  }

  Widget _eraserPanel(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.line_weight, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: eraserSize,
            min: 0.01,
            max: 0.12,
            activeColor: Colors.white,
            onChanged: onEraserSizeChanged,
          ),
        ),
      ],
    );
  }

  Widget _textPanel(BuildContext context) {
    return ColorPaletteRow(selectedColor: textColor, onColorSelected: onTextColorChanged);
  }

  Widget _shapePanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _shapeTypeIcon(Icons.arrow_forward, ShapeType.arrow),
            const SizedBox(width: 10),
            _shapeTypeIcon(Icons.circle_outlined, ShapeType.circle),
            const SizedBox(width: 10),
            _shapeTypeIcon(Icons.crop_square, ShapeType.square),
            const SizedBox(width: 10),
            _shapeTypeIcon(Icons.rectangle_outlined, ShapeType.rectangle),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text("الحدود: ", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          Expanded(
            child: ColorPaletteRow(selectedColor: shapeBorderColor, onColorSelected: onShapeBorderColorChanged),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text("التعبئة: ", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          Expanded(
            child: ColorPaletteRow(
              selectedColor: shapeFillColor ?? Colors.transparent,
              onColorSelected: (c) => onShapeFillColorChanged(c),
              allowTransparentOption: true,
              isTransparentSelected: shapeFillColor == null,
              onTransparentSelected: () => onShapeFillColorChanged(null),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        ThicknessOpacityControls(
          thickness: shapeBorderWidth,
          onThicknessChanged: onShapeBorderWidthChanged,
          previewColor: shapeBorderColor,
          minThickness: 0.001,
          maxThickness: 0.02,
        ),
      ],
    );
  }

  Widget _shapeTypeIcon(IconData icon, ShapeType type) {
    final bool selected = shapeType == type;
    return GestureDetector(
      onTap: () => onShapeTypeChanged(type),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentYellow.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.accentYellow : Colors.grey, width: 1),
        ),
        child: Icon(icon, size: 18, color: selected ? AppColors.accentYellow : Colors.grey),
      ),
    );
  }
}
