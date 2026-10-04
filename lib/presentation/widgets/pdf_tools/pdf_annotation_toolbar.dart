import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/app_state.dart';
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

  // الهايلايتر الحر
  final double freehandHighlighterThickness;
  final ValueChanged<double> onFreehandHighlighterThicknessChanged;

  // التسطير
  final Color underlineColor;
  final ValueChanged<Color> onUnderlineColorChanged;

  // الممحاة
  final double eraserSize;
  final ValueChanged<double> onEraserSizeChanged;

  // النص
  final Color textColor;
  final ValueChanged<Color> onTextColorChanged;
  final double textFontSize;
  final ValueChanged<double> onTextFontSizeChanged;
  final bool textBold;
  final ValueChanged<bool> onTextBoldChanged;
  final bool textUnderline;
  final ValueChanged<bool> onTextUnderlineChanged;

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

  /// هل لوحة تحكم الأداة النشطة (الألوان/الشفافية/السماكة...) مفتوحة؟
  /// مغلقة افتراضياً: يظهر صف الأدوات فقط.
  final bool controlsOpen;

  /// ضغطتان على أيقونة أداة: فتح/إغلاق لوحة التحكم الخاصة بها
  /// (ضغطة واحدة تفعّل الأداة أو تُعطّلها).
  final ValueChanged<PdfTool> onToggleControls;

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
    required this.freehandHighlighterThickness,
    required this.onFreehandHighlighterThicknessChanged,
    required this.underlineColor,
    required this.onUnderlineColorChanged,
    required this.eraserSize,
    required this.onEraserSizeChanged,
    required this.textColor,
    required this.onTextColorChanged,
    required this.textFontSize,
    required this.onTextFontSizeChanged,
    required this.textBold,
    required this.onTextBoldChanged,
    required this.textUnderline,
    required this.onTextUnderlineChanged,
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
    required this.controlsOpen,
    required this.onToggleControls,
  });

  void _handleTap(PdfTool tool) {
    // الضغط على أداة مفعّلة حالياً يُغلقها (يعيدها إلى "بلا أداة")
    onToolTap(activeTool == tool ? PdfTool.none : tool);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(
        // سطح الشريط يتبع الوضع: داكن كما كان في الليلي، وفاتح بحدّ واضح في
        // النهاري (كان داكناً دائماً فتضيع حدود وألوان الأدوات في اللايت مود).
        color: AppColors.toolbarSurface,
        borderRadius: BorderRadius.circular(16),
        border: AppState.isDark
            ? null
            : Border.all(color: AppColors.toolBorder, width: 1),
        boxShadow: [
          BoxShadow(
              color: AppState.isDark ? Colors.black54 : Colors.black26,
              blurRadius: 8)
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolRow(),
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
          _toolIcon(Icons.border_color, PdfTool.highlighter),
          // هايلايتر حر (رسم يدوي)
          _toolIcon(Icons.brush, PdfTool.freehandHighlighter),
          _toolIcon(Icons.format_underlined, PdfTool.underline),
          _toolIcon(Icons.text_fields, PdfTool.text),
          _toolIcon(Icons.category_outlined, PdfTool.shape),
          _toolIcon(Icons.image_outlined, PdfTool.image, onTapOverride: onPickImage),
          // أيقونة الممحاة الحقيقية
          _toolIcon(LucideIcons.eraser, PdfTool.eraser),
          _toolIcon(Icons.comment_outlined, PdfTool.comment),
          const SizedBox(width: 6),
          Container(width: 1, height: 22, color: AppColors.toolIconInactive),
          const SizedBox(width: 6),
          _compactButton(
            icon: Icons.undo,
            color: AppColors.textPrimary,
            tooltip: 'تراجع',
            onPressed: onUndo,
          ),
          const SizedBox(width: 2),
          _palmRejectionButton(),
        ],
      ),
    );
  }

  /// زر أيقونة مضغوط (36×36 بدل 48×48 الافتراضي).
  Widget _compactButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
    );
  }

  Widget _palmRejectionButton() {
    final bool on = palmRejectionEnabled;
    return GestureDetector(
      onTap: () => onPalmRejectionChanged(!on),
      child: Tooltip(
        message: on ? 'رفض راحة اليد: مفعّل' : 'رفض راحة اليد: معطّل',
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: on ? AppColors.accentYellow.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? AppColors.accentYellow : AppColors.toolIconInactive, width: 1),
          ),
          child: Icon(
            Icons.front_hand_outlined,
            size: 18,
            color: on ? AppColors.accentYellow : AppColors.toolIconInactive,
          ),
        ),
      ),
    );
  }

  /// الأدوات التي لها لوحة تحكم (ألوان/شفافية/سماكة/...).
  static bool _hasPanel(PdfTool tool) {
    switch (tool) {
      case PdfTool.pen:
      case PdfTool.highlighter:
      case PdfTool.freehandHighlighter:
      case PdfTool.underline:
      case PdfTool.eraser:
      case PdfTool.text:
      case PdfTool.shape:
        return true;
      case PdfTool.comment:
      case PdfTool.image:
      case PdfTool.none:
        return false;
    }
  }

  Widget _toolIcon(IconData icon, PdfTool tool, {VoidCallback? onTapOverride}) {
    final bool selected = activeTool == tool;
    final bool hasPanel = onTapOverride == null && _hasPanel(tool);
    return Tooltip(
      message: tool.label,
      child: _ToolButton(
        icon: icon,
        selected: selected,
        hasPanel: hasPanel,
        panelOpen: selected && controlsOpen,
        // ضغطة واحدة: تفعيل/تعطيل الأداة.
        onTap: onTapOverride ?? () => _handleTap(tool),
        // ضغطتان: فتح/إغلاق لوحة التحكم (فقط للأدوات التي لها لوحة).
        onDoubleTap: hasPanel ? () => onToggleControls(tool) : null,
      ),
    );
  }

  /// اللوحة السياقية التي تظهر تحت شريط الأدوات حسب الأداة النشطة حالياً
  /// (لوحة ألوان، سماكة/شفافية، اختيار شكل...).
  Widget _buildContextPanel(BuildContext context) {
    // مغلقة افتراضياً: لا تظهر إلا بعد ضغطتين على أيقونة الأداة.
    if (!controlsOpen) return const SizedBox.shrink();
    switch (activeTool) {
      case PdfTool.pen:
        return _penPanel(context);
      case PdfTool.highlighter:
        return _highlighterPanel(context);
      case PdfTool.freehandHighlighter:
        return _freehandHighlighterPanel(context);
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
        const SizedBox(height: 2),
        ThicknessOpacityControls(
          compact: true,
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
                activeColor: AppColors.visibleOnToolSurface(highlighterColor),
                inactiveColor: AppColors.toolTrackInactive,
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
    // نطاق الحجم (يطابق min/max للـ Slider) لحساب معاينة دائرية لحجم الممحاة.
    const double minSize = 0.01;
    const double maxSize = 0.12;
    final double t = ((eraserSize - minSize) / (maxSize - minSize)).clamp(0.0, 1.0);
    final double previewDiameter = 8 + t * 16;
    return Row(
      children: [
        Icon(Icons.line_weight, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: eraserSize.clamp(minSize, maxSize),
            min: minSize,
            max: maxSize,
            // ألوان صريحة: الجزء المعبّأ بلون التمييز والباقي رمادي واضح، فيظهر
            // الفرق عند السحب (كان كله أبيض فلا يُرى أي فرق).
            activeColor: AppColors.accentYellow,
            inactiveColor: AppColors.toolTrackInactive,
            thumbColor: AppColors.accentYellow,
            onChanged: onEraserSizeChanged,
          ),
        ),
        // معاينة مباشرة لحجم الممحاة الحالي
        SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Container(
              width: previewDiameter,
              height: previewDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentYellow.withOpacity(0.25),
                border: Border.all(color: AppColors.toolBorder, width: 1.2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _textPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // لوحة الألوان مع معاينة فورية
        ColorPaletteRow(selectedColor: textColor, onColorSelected: onTextColorChanged),
        const SizedBox(height: 6),
        // حجم الخط
        Row(
          children: [
            Icon(Icons.format_size, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: textFontSize.clamp(0.010, 0.060),
                min: 0.010,
                max: 0.060,
                divisions: 10,
                activeColor: AppColors.visibleOnToolSurface(textColor),
                inactiveColor: AppColors.toolTrackInactive,
                onChanged: onTextFontSizeChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                "${(textFontSize * 1000).toInt()}",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
        // خط عريض
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text("عريض", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            Switch(
              value: textBold,
              activeColor: AppColors.accentYellow,
              onChanged: onTextBoldChanged,
            ),
          ],
        ),
        // تسطير
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text("تسطير", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            Switch(
              value: textUnderline,
              activeColor: AppColors.accentYellow,
              onChanged: onTextUnderlineChanged,
            ),
          ],
        ),
      ],
    );
  }

  Widget _freehandHighlighterPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorPaletteRow(selectedColor: highlighterColor, onColorSelected: onHighlighterColorChanged),
        const SizedBox(height: 6),
        // الشفافية
        Row(
          children: [
            Icon(Icons.opacity, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: highlighterOpacity,
                min: 0.1,
                max: 0.8,
                activeColor: AppColors.visibleOnToolSurface(highlighterColor),
                inactiveColor: AppColors.toolTrackInactive,
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
        // السماكة
        Row(
          children: [
            Icon(Icons.line_weight, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: freehandHighlighterThickness,
                min: 0.008,
                max: 0.06,
                activeColor: AppColors.visibleOnToolSurface(highlighterColor),
                inactiveColor: AppColors.toolTrackInactive,
                onChanged: onFreehandHighlighterThicknessChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                "${(freehandHighlighterThickness * 1000).toInt()}",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
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
        // إخفاء خيار التعبئة للسهم (الأسهم لا تحتوي منطقة مملوءة)
        if (shapeType != ShapeType.arrow) ...[
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
        ],
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
          border: Border.all(color: selected ? AppColors.accentYellow : AppColors.toolIconInactive, width: 1),
        ),
        child: Icon(icon, size: 18, color: selected ? AppColors.accentYellow : AppColors.toolIconInactive),
      ),
    );
  }
}

/// زر أداة يدعم ضغطة واحدة (تفعيل/تعطيل) وضغطتين (لوحة التحكم).
///
/// لماذا لا نستخدم onDoubleTap الجاهز؟ وجوده يجعل Flutter يؤخر **كل** ضغطة
/// واحدة ~300ms، فيتأخر اختيار الأداة. هنا:
///  • أداة غير مفعّلة: تُفعَّل فوراً عند أول ضغطة (بلا تأخير)، وإن جاءت ضغطة
///    ثانية خلال 300ms تُفتح لوحة التحكم.
///  • أداة مفعّلة: ننتظر 300ms قبل التعطيل لنرى إن كانت بداية ضغطتين؛ فإن
///    جاءت الثانية تبقى الأداة مفعّلة وتُفتح/تُغلق اللوحة.
class _ToolButton extends StatefulWidget {
  const _ToolButton({
    required this.icon,
    required this.selected,
    required this.hasPanel,
    required this.panelOpen,
    required this.onTap,
    this.onDoubleTap,
  });

  final IconData icon;
  final bool selected;
  final bool hasPanel;
  final bool panelOpen;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  DateTime? _lastPressAt;
  Timer? _pendingSingle;

  @override
  void dispose() {
    _pendingSingle?.cancel();
    super.dispose();
  }

  void _handlePress() {
    final onDouble = widget.onDoubleTap;
    if (onDouble == null) {
      widget.onTap(); // لا لوحة لهذه الأداة: ضغطة فورية دائماً
      return;
    }

    final now = DateTime.now();
    final last = _lastPressAt;
    if (last != null && now.difference(last) <= _doubleTapWindow) {
      // الضغطة الثانية: ضغطتان → لوحة التحكم.
      _lastPressAt = null;
      _pendingSingle?.cancel();
      _pendingSingle = null;
      onDouble();
      return;
    }

    _lastPressAt = now;
    if (widget.selected) {
      // قد تكون بداية ضغطتين: أجّل التعطيل قليلاً.
      _pendingSingle?.cancel();
      _pendingSingle = Timer(_doubleTapWindow, () {
        _pendingSingle = null;
        _lastPressAt = null;
        if (mounted) widget.onTap();
      });
    } else {
      widget.onTap(); // تفعيل فوري
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accentYellow.withOpacity(0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(
              widget.icon,
              color: selected ? AppColors.accentYellow : AppColors.toolIconInactive,
              size: 20,
            ),
            onPressed: _handlePress,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          // مؤشر صغير: أداة مفعّلة ولها لوحة (ممتلئ = مفتوحة، خافت = مغلقة).
          if (selected && widget.hasPanel)
            Positioned(
              bottom: 3,
              child: IgnorePointer(
                child: Container(
                  width: 12,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: widget.panelOpen
                        ? AppColors.accentYellow
                        : AppColors.toolIconInactive.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
