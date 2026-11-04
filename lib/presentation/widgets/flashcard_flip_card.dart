import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/flashcard_model.dart';
import '../../l10n/generated/app_localizations.dart';

/// 🃏 بطاقة الفلاش كاردس القابلة للقلب (Step 14).
///
/// - النقر على البطاقة يقلبها (أنيميشن دوران).
/// - السحب يمين/يسار اختصار اختياري للتقييم، ويعمل **بعد القلب فقط** حتى لا يقيّم الطالب دون رؤية الإجابة.
///   أثناء السحب تتلوّن البطاقة بالأخضر (يمين = عرفتها) أو الأحمر (يسار = ما زلت أتعلمها) مع نص يوضح المعنى.
/// - الأزرار في الشاشة الأم هي التحكم الأساسي وتستدعي [FlashcardFlipCardState.flyOut].
/// - النقر على صورة البطاقة يفتح [onImageTap] (تكبير) بدل القلب.
///
/// يُعطى لكل بطاقة `key` مختلف (مثل ValueKey(card.id)) فتبدأ حالتها من جديد مع أنيميشن ظهور.
class FlashcardFlipCard extends StatefulWidget {
  final FlashcardModel card;

  /// يبني رابط الصورة من اسم الملف (أو null إن لم يتوفر).
  final String Function(String fileId) imageUrlBuilder;
  final Map<String, String> imageHeaders;

  /// يُستدعى عند تغيّر حالة القلب (true = ظهر الوجه الخلفي).
  final ValueChanged<bool> onFlipChanged;

  /// يُستدعى بعد انتهاء أنيميشن الخروج (سحب أو زر). known=true يعني «عرفتها».
  final ValueChanged<bool> onDecision;

  /// يُستدعى عند النقر على صورة لتكبيرها.
  final ValueChanged<String> onImageTap;

  const FlashcardFlipCard({
    super.key,
    required this.card,
    required this.imageUrlBuilder,
    required this.imageHeaders,
    required this.onFlipChanged,
    required this.onDecision,
    required this.onImageTap,
  });

  @override
  State<FlashcardFlipCard> createState() => FlashcardFlipCardState();
}

class FlashcardFlipCardState extends State<FlashcardFlipCard> with TickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  late final AnimationController _moveCtrl;
  late final AnimationController _enterCtrl;

  bool _flipped = false;
  bool _busy = false; // أثناء الخروج/الرجوع لا نقبل لمسات
  double _dx = 0;
  double _cardWidth = 300;
  double _moveFrom = 0;
  double _moveTo = 0;
  VoidCallback? _moveDone;

  bool get isFlipped => _flipped;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..forward();
    _moveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        final t = Curves.easeOut.transform(_moveCtrl.value);
        setState(() => _dx = _moveFrom + (_moveTo - _moveFrom) * t);
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          final cb = _moveDone;
          _moveDone = null;
          cb?.call();
        }
      });
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _moveCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── واجهة عامة للشاشة الأم ─────────────────────────

  void flip() {
    if (_busy) return;
    setState(() => _flipped = !_flipped);
    if (_flipped) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
    widget.onFlipChanged(_flipped);
  }

  /// يُخرج البطاقة جانباً (يمين=معروفة، يسار=غير معروفة) ثم يستدعي onDecision.
  /// يرجع false إن لم يبدأ (البطاقة غير مقلوبة أو مشغولة بحركة أخرى).
  bool flyOut(bool known) {
    if (_busy || !_flipped) return false;
    _busy = true;
    _animateTo(
      (known ? 1 : -1) * (_cardWidth * 1.6),
      onDone: () {
        if (mounted) widget.onDecision(known);
      },
    );
    return true;
  }

  /// تلميح السحب (أول مرة فقط): تميل البطاقة يميناً ثم يساراً ثم تعود.
  Future<void> playSwipeHint() async {
    if (_busy || !mounted) return;
    _busy = true;
    final nudge = _cardWidth * 0.22;
    for (final target in [nudge, -nudge, 0.0]) {
      if (!mounted) return;
      await _animateToAsync(target, const Duration(milliseconds: 380));
      if (target != 0.0) {
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
    }
    if (mounted) _busy = false;
  }

  // ───────────────────────── الحركة ─────────────────────────

  void _animateTo(double target, {VoidCallback? onDone, Duration? duration}) {
    _moveFrom = _dx;
    _moveTo = target;
    _moveDone = onDone;
    _moveCtrl.duration = duration ?? const Duration(milliseconds: 240);
    _moveCtrl.forward(from: 0);
  }

  Future<void> _animateToAsync(double target, Duration duration) {
    final completer = Completer<void>();
    _animateTo(target, duration: duration, onDone: () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_busy || !_flipped) return;
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_busy || !_flipped) return;
    final v = d.primaryVelocity ?? 0;
    final farEnough = _dx.abs() > _cardWidth * 0.28;
    final fastFling = v.abs() > 800 && _dx.abs() > 8 && (v > 0) == (_dx > 0);
    if (farEnough || fastFling) {
      flyOut(_dx > 0);
    } else {
      _busy = true;
      _animateTo(0, onDone: () {
        if (mounted) _busy = false;
      });
    }
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _cardWidth = constraints.maxWidth;
        final progress = (_dx.abs() / (_cardWidth * 0.28)).clamp(0.0, 1.0);
        final known = _dx > 0;
        final tint = known ? AppColors.success : AppColors.error;

        return FadeTransition(
          opacity: _enterCtrl,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: flip,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Transform.translate(
                offset: Offset(_dx, 0),
                child: Transform.rotate(
                  angle: (_dx / _cardWidth) * 0.22,
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _flipCtrl,
                        builder: (context, _) {
                          final angle = _flipCtrl.value * math.pi;
                          final showBack = angle > math.pi / 2;
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0012)
                              ..rotateY(angle),
                            child: showBack
                                // الوجه الخلفي يُعكس نصف دورة حتى لا يظهر مقلوباً
                                ? Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()..rotateY(math.pi),
                                    child: _face(back: true),
                                  )
                                : _face(back: false),
                          );
                        },
                      ),
                      // تلوين السحب + النص التوضيحي
                      if (progress > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: tint.withOpacity(0.30 * progress),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: tint.withOpacity(0.9 * progress),
                                  width: 3,
                                ),
                              ),
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(top: 20),
                              child: Opacity(
                                opacity: progress,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: tint,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    known
                                        ? AppLocalizations.of(context)!.flashcardSwipeKnown
                                        : AppLocalizations.of(context)!.flashcardSwipeLearning,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _face({required bool back}) {
    final accent = AppColors.flashcardAccent;
    final String trimmed =
        ((back ? widget.card.backText : widget.card.frontText) ?? '').trim();
    final imageId = back ? widget.card.backImageFileId : widget.card.frontImageFileId;
    final hasText = trimmed.isNotEmpty;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: back ? AppColors.flashcardAccentSoft.withOpacity(0.5) : AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(back ? 0.7 : 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (imageId != null && imageId.isNotEmpty) _image(imageId, hasText),
                      if (imageId != null && imageId.isNotEmpty && hasText)
                        const SizedBox(height: 16),
                      if (hasText)
                        Text(
                          trimmed,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: _fontSizeFor(trimmed.length, imageId != null),
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // وسم الوجه (سؤال/إجابة)
          PositionedDirectional(
            top: 14,
            start: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                back ? AppLocalizations.of(context)!.flashcardBack : AppLocalizations.of(context)!.flashcardFront,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _fontSizeFor(int length, bool hasImage) {
    if (hasImage) return length > 120 ? 15 : 17;
    if (length <= 40) return 24;
    if (length <= 120) return 20;
    if (length <= 300) return 17;
    return 15;
  }

  Widget _image(String fileId, bool hasText) {
    final url = widget.imageUrlBuilder(fileId);
    return GestureDetector(
      // النقر على الصورة يكبّرها ولا يقلب البطاقة
      onTap: () => widget.onImageTap(url),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: hasText ? 200 : 320),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: url,
                httpHeaders: widget.imageHeaders,
                fit: BoxFit.contain,
                placeholder: (context, _) => SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator(color: AppColors.flashcardAccent)),
                ),
                errorWidget: (context, _, __) => const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.broken_image_outlined, color: AppColors.error)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
