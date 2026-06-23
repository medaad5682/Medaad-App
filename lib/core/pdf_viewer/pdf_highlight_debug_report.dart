import 'dart:convert';

/// يجمع سجل خطوات تنفيذ عملية تمييز/تسطير واحدة، بالإضافة إلى كل القيم
/// والإحداثيات وبيانات التخزين ذات الصلة، لإنتاج تقرير نصي واحد قابل للنسخ
/// يمكن مشاركته لتحليل مشكلة عدم ظهور التمييز/التسطير على بعض الصفحات.
///
/// لا يُستخدم هذا الكائن في أي منطق تنفيذي فعلي — هو وسيلة مراقبة (observability)
/// فقط، يُملأ خطوة بخطوة أثناء تنفيذ [PdfHighlightController.handleTextSelectionChange]
/// ثم يُعرض في حوار قابل للنسخ بعد انتهاء العملية (بنجاح أو فشل).
class PdfHighlightDebugReport {
  PdfHighlightDebugReport({required this.toolName});

  /// اسم الأداة المستخدمة وقت بدء العملية ("تمييز" أو "تسطير").
  final String toolName;

  final DateTime startedAt = DateTime.now();
  DateTime? finishedAt;

  final List<String> _steps = [];
  final Map<String, dynamic> _summary = {};
  final List<Map<String, dynamic>> _perRangeDetails = [];

  /// إضافة سطر سجل عام (خطوة تنفيذ).
  void log(String message) {
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    _steps.add('[+${elapsedMs}ms] $message');
  }

  /// تسجيل قيمة ملخّصة (key/value) تظهر في أعلى التقرير.
  void setSummary(String key, dynamic value) {
    _summary[key] = value;
  }

  /// تسجيل تفاصيل كاملة عن نطاق نص واحد (range) تمت معالجته، بما في ذلك
  /// حالة كاش النص، أبعاد الصفحة المستخدمة، المستطيلات المحسوبة، وحالة الحفظ.
  void addRangeDetail(Map<String, dynamic> detail) {
    _perRangeDetails.add(detail);
  }

  void markFinished() {
    finishedAt = DateTime.now();
  }

  /// يُنتج نص التقرير الكامل، منسّقاً وقابلاً للنسخ بالكامل.
  String build() {
    final buffer = StringBuffer();
    final totalMs = (finishedAt ?? DateTime.now()).difference(startedAt).inMilliseconds;

    buffer.writeln('══════════════════════════════════════════');
    buffer.writeln(' تقرير تشخيص التمييز/التسطير');
    buffer.writeln('══════════════════════════════════════════');
    buffer.writeln('الأداة: $toolName');
    buffer.writeln('وقت البدء: ${startedAt.toIso8601String()}');
    buffer.writeln('المدة الإجمالية: ${totalMs}ms');
    buffer.writeln('');

    buffer.writeln('── ملخص ──');
    if (_summary.isEmpty) {
      buffer.writeln('(لا توجد بيانات ملخصة)');
    } else {
      _summary.forEach((key, value) {
        buffer.writeln('$key: ${_stringifyValue(value)}');
      });
    }
    buffer.writeln('');

    buffer.writeln('── خطوات التنفيذ بالترتيب ──');
    if (_steps.isEmpty) {
      buffer.writeln('(لا توجد خطوات مسجّلة)');
    } else {
      for (var i = 0; i < _steps.length; i++) {
        buffer.writeln('${i + 1}. ${_steps[i]}');
      }
    }
    buffer.writeln('');

    buffer.writeln('── تفاصيل كل نطاق نص (Range) ──');
    if (_perRangeDetails.isEmpty) {
      buffer.writeln('(لا توجد نطاقات تمت معالجتها)');
    } else {
      for (var i = 0; i < _perRangeDetails.length; i++) {
        buffer.writeln('▸ النطاق رقم ${i + 1}:');
        buffer.writeln(_indent(_prettyJson(_perRangeDetails[i]), '    '));
      }
    }
    buffer.writeln('');
    buffer.writeln('══════════════════════════════════════════');

    return buffer.toString();
  }

  static String _stringifyValue(dynamic value) {
    if (value is Map || value is List) return _prettyJson(value);
    return value.toString();
  }

  static String _prettyJson(dynamic value) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  static String _indent(String text, String prefix) {
    return text.split('\n').map((line) => '$prefix$line').join('\n');
  }
}
