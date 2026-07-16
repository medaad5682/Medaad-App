import 'dart:async';
import 'package:flutter/material.dart';

/// 🔤 [جديد] نص يتحرك أفقياً تلقائياً (Marquee) عندما يكون أطول من
/// المساحة المتاحة له، بحيث يستطيع المستخدم قراءة العنوان بالكامل دون أي
/// تفاعل يدوي. إذا كان النص يتسع بالفعل ضمن المساحة المتاحة، يُعرض بشكل
/// طبيعي وثابت تماماً كالسابق (بدون أي حركة أو تأثير).
///
/// يدعم اتجاه الكتابة RTL/LTR تلقائياً عبر [Directionality] المحيط، ويتوقف
/// بضع لحظات عند كل طرف (بداية/نهاية) قبل عكس اتجاه الحركة، مثل الشرائط
/// الإخبارية المتحركة.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final double velocity; // بكسل/ثانية
  final Duration pauseAtEnds;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.velocity = 32,
    this.pauseAtEnds = const Duration(milliseconds: 1100),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  Timer? _pauseTimer;
  bool _forward = true;
  bool _running = false;
  String? _lastText;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      // 🔁 إعادة الضبط عند تغيّر النص (مثلاً بعد تحديث البيانات)
      _pauseTimer?.cancel();
      _running = false;
      _forward = true;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startIfNeeded(double overflow) {
    if (_running) return;
    _running = true;
    _scheduleNextPass(overflow);
  }

  void _scheduleNextPass(double overflow) {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(widget.pauseAtEnds, () => _runPass(overflow));
  }

  Future<void> _runPass(double overflow) async {
    if (!mounted || !_controller.hasClients) return;
    final double target = _forward ? overflow : 0.0;
    final int ms =
        ((overflow / widget.velocity) * 1000).clamp(500, 25000).toInt();
    try {
      await _controller.animateTo(
        target,
        duration: Duration(milliseconds: ms),
        curve: Curves.linear,
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _forward = !_forward;
    _scheduleNextPass(overflow);
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection direction = Directionality.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      final double maxWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;

      final TextPainter painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: direction,
      )..layout();

      final double overflow = painter.width - maxWidth;

      // ✅ النص يتسع بالفعل ضمن المساحة المتاحة — لا داعي لأي حركة
      if (overflow <= 0.5 || widget.text.trim().isEmpty) {
        _pauseTimer?.cancel();
        _running = false;
        return Text(
          widget.text,
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }

      if (_lastText != widget.text) {
        _lastText = widget.text;
        _running = false;
        _forward = true;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startIfNeeded(overflow);
      });

      return ClipRect(
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      );
    });
  }
}
