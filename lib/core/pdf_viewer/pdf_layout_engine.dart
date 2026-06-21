import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// يوفر إعدادات تخطيط الصفحات الثابتة (تمرير عمودي دائماً).
class PdfLayoutEngine {
  /// دالة التخطيط: null = التمرير العمودي الافتراضي لـ pdfrx.
  static PdfPageLayoutFunction? get layout => null;

  static PdfPageAnchor get anchorStart => PdfPageAnchor.top;

  static PdfPageAnchor get anchorEnd => PdfPageAnchor.bottom;

  static bool get scrollHorizontallyByMouseWheel => false;

  static ScrollPhysics get scrollPhysics => const BouncingScrollPhysics();
}
