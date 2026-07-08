import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/floating_video_controller.dart';
import '../../main.dart' show navigatorKey;
import '../screens/native_video_player_screen.dart';

// ============================================================
// 🎬 FloatingVideoOverlay
//
// A draggable, resizable Picture-in-Picture (PiP) video player.
// Drop this widget inside the Stack of any screen that should
// support floating video (e.g. PdfViewerScreen).
//
// Security contract
// ─────────────────
// • FLAG_SECURE is applied at the Android window level by
//   FlutterWindowManagerPlus.  That flag belongs to the *Activity*
//   (window), not individual widgets, so it remains active for the
//   entire app once set — the floating overlay simply inherits it.
// • This widget never calls removeFlags, so security is preserved.
// • The FLAG is re-asserted in initState as a belt-and-braces guard.
// ============================================================

class FloatingVideoOverlay extends StatefulWidget {
  /// Initial position offset from the bottom-right corner.
  final Offset initialOffset;

  const FloatingVideoOverlay({
    super.key,
    this.initialOffset = const Offset(16, 100),
  });

  @override
  State<FloatingVideoOverlay> createState() => _FloatingVideoOverlayState();
}

class _FloatingVideoOverlayState extends State<FloatingVideoOverlay>
    with WidgetsBindingObserver {
  // ── Geometry ────────────────────────────────────────────────
  static const double _minW = 180.0;
  // ✅ لا يوجد حد أقصى ثابت بعد الآن — يُحسب الحد الأقصى ديناميكيًا من
  // مقاس الشاشة في _maxWidthForScreen() بحيث تكبر النافذة العائمة حتى
  // حواف الشاشة (مع هامش صغير) على أي جهاز، بما في ذلك الأجهزة اللوحية.
  static const double _screenMargin = 16.0;
  static const double _aspectRatio = 16 / 9;

  double _width = 240.0;
  double get _height => _width / _aspectRatio;

  /// أقصى عرض ممكن للنافذة العائمة بناءً على مقاس الشاشة الحالي، بحيث لا
  /// يتجاوز عرض أو ارتفاع النافذة حدود الشاشة (مع هامش [_screenMargin]).
  double _maxWidthForScreen(Size screen) {
    final maxByWidth = screen.width - (_screenMargin * 2);
    final maxByHeight = (screen.height - (_screenMargin * 2)) * _aspectRatio;
    final maxW = maxByWidth < maxByHeight ? maxByWidth : maxByHeight;
    return maxW < _minW ? _minW : maxW;
  }

  late Offset _position; // top-left of the floating window
  bool _isDragging = false;

  // ── Player ──────────────────────────────────────────────────
  BetterPlayerController? _controller;
  bool _isPlaying = false;
  bool _isInitializing = true;
  bool _isError = false;
  String _currentQuality = '';
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;
  bool _handoffApplied = false;

  // ── Seeking ─────────────────────────────────────────────────
  Duration _videoPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  bool _isScrubbing = false;
  double _scrubFraction = 0.0; // 0..1, only meaningful while scrubbing

  bool _showSeekBubble = false;
  bool _seekBubbleForward = true;
  Timer? _seekBubbleTimer;
  static const Duration _seekStep = Duration(seconds: 10);

  // ✅ التراكم عند النقر المزدوج المتكرر (Cumulative seek):
  // _seekBurstBase هو الموضع الذي بدأت عنده "الدفعة" الحالية من النقرات
  // المتتالية، و _seekBurstSteps هو عدد خطوات الـ 10 ثوانٍ المتراكمة
  // (موجب للأمام، سالب للخلف) ضمن هذه الدفعة. _seekBubbleSeconds تُستخدم
  // فقط لعرض الرقم التراكمي في فقاعة الـ UI. _seekCommitTimer يؤجل
  // استدعاء seekTo() الفعلي حتى تهدأ سلسلة النقرات، حتى لا تتنافس عدة
  // أوامر seek غير متزامنة مع بعضها وتكسر التراكم.
  Duration _seekBurstBase = Duration.zero;
  int _seekBurstSteps = 0;
  int _seekBubbleSeconds = 0;
  Timer? _seekCommitTimer;

  // ── Watermark ───────────────────────────────────────────────
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;

  // ── Controls visibility ─────────────────────────────────────
  bool _controlsVisible = false;
  Timer? _controlsTimer;

  final FloatingVideoController _fvc = FloatingVideoController.instance;

  @override
  void initState() {
    super.initState();
    // Default position: bottom-right corner (adjusted in first build)
    _position = const Offset(16, 400);
    _assertFlagSecure();
    _initPlayer();
    _startWatermark();
    WidgetsBinding.instance.addObserver(this);
    _fvc.addListener(_onControllerChanged);
  }

  // ── Security ────────────────────────────────────────────────

  Future<void> _assertFlagSecure() async {
    try {
      await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _assertFlagSecure();
    }
    if (state == AppLifecycleState.paused) {
      _controller?.pause();
    }
  }

  // ── FloatingVideoController listener ────────────────────────

  void _onControllerChanged() {
    if (!_fvc.isFloating) {
      // Floating was stopped externally — dispose player
      _disposePlayer();
    }
  }

  // ── Player init ─────────────────────────────────────────────

  void _initPlayer() {
    final state = _fvc.videoState;
    if (state == null) return;

    _sortedQualities = state.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      final nA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final nB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return nA.compareTo(nB); // ascending: start with lowest for PiP
    });

    // Keep the exact same quality that was playing full-screen, if it was
    // handed off to us. Otherwise fall back to a modest default for PiP.
    final handoffQuality = state.initialQuality;
    if (handoffQuality != null && _sortedQualities.contains(handoffQuality)) {
      _currentQuality = handoffQuality;
    } else {
      const preferred = ['360', '240', '480', '720'];
      int chosenIdx = 0;
      for (final p in preferred) {
        final idx = _sortedQualities
            .indexWhere((q) => q.replaceAll(RegExp(r'[^0-9]'), '') == p);
        if (idx != -1) {
          chosenIdx = idx;
          break;
        }
      }
      _currentQuality = _sortedQualities[chosenIdx];
    }
    _currentSpeed = state.playbackSpeed;

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      state.streams[_currentQuality]!,
      headers: const {'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)'},
      videoFormat: BetterPlayerVideoFormat.hls,
      resolutions: state.streams,
      cacheConfiguration:
          const BetterPlayerCacheConfiguration(useCache: false),
      notificationConfiguration:
          const BetterPlayerNotificationConfiguration(showNotification: false),
    );

    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        fit: BoxFit.contain,
        autoPlay: state.wasPlaying,
        looping: false,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        autoDetectFullscreenDeviceOrientation: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
          showControlsOnInitialize: false,
          enableFullscreen: false,
          enablePip: false,
          enableQualities: false,
          enableSubtitles: false,
          enableSkips: false,
          enableMute: true,
          enablePlaybackSpeed: false,
          enableOverflowMenu: false,
          loadingColor: AppColors.accentYellow,
        ),
        errorBuilder: (context, _) => const SizedBox.shrink(),
      ),
      betterPlayerDataSource: dataSource,
    );

    controller.addEventsListener(_onPlayerEvent);

    setState(() {
      _controller = controller;
      _isInitializing = false;
    });
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (!mounted) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _attachVideoListener();
        _applyHandoffStateIfNeeded();
        break;
      case BetterPlayerEventType.exception:
        setState(() => _isError = true);
        FirebaseCrashlytics.instance.log(
          '⚠️ FloatingVideo exception: ${event.parameters}',
        );
        break;
      default:
        break;
    }
  }

  void _attachVideoListener() {
    _controller?.videoPlayerController
        ?.removeListener(_onVideoValueChanged);
    _controller?.videoPlayerController
        ?.addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _onVideoValueChanged() {
    if (!mounted) return;
    final v = _controller?.videoPlayerController?.value;
    if (v == null) return;
    setState(() {
      _isPlaying = v.isPlaying;
      if (!_isScrubbing) _videoPosition = v.position;
      _videoDuration = v.duration ?? Duration.zero;
    });
  }

  /// Resumes playback at the exact position/speed handed off from the
  /// full-screen player, the first time the floating player initializes.
  void _applyHandoffStateIfNeeded() {
    if (_handoffApplied || !mounted) return;
    _handoffApplied = true;

    final pos = _fvc.videoState?.initialPosition ?? Duration.zero;
    if (pos > Duration.zero) {
      try {
        _controller?.seekTo(pos);
      } catch (_) {}
    }
    if (_currentSpeed != 1.0) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        try {
          _controller?.setSpeed(_currentSpeed);
        } catch (_) {}
      });
    }
  }

  // ── Controls auto-hide ───────────────────────────────────────

  void _showControls() {
    _controlsTimer?.cancel();
    setState(() => _controlsVisible = true);
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  // ── Watermark ────────────────────────────────────────────────

  void _startWatermark() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final r = Random();
      setState(() {
        _watermarkAlignment = Alignment(
          (r.nextDouble() * 1.6) - 0.8,
          (r.nextDouble() * 1.6) - 0.8,
        );
      });
    });
  }

  // ── Dispose ──────────────────────────────────────────────────

  // ✅ إصلاح Crash فادح: "'_lifecycleState != _ElementLifecycle.defunct':
  // is not true". السبب: عند استدعاء _disposePlayer() من داخل
  // State.dispose() نفسها (كما كان يحدث سابقًا)، فإن "mounted" لا يزال
  // true في تلك اللحظة تحديدًا (الـ framework لا يصفّر الـ Element إلا
  // بعد عودة dispose())، لكن الـ Element يكون قد انتقل داخليًا بالفعل
  // إلى الحالة "defunct" أثناء تسلسل الـ unmount. لذلك يمر فحص mounted
  // بنجاح، لكن استدعاء setState() بعده يصطدم بتأكيد داخلي في
  // markNeedsBuild() ويرمي استثناءً فادحًا يوقف الـ widget tree بالكامل.
  // القاعدة العامة في Flutter: لا يجوز أبدًا استدعاء setState() من داخل
  // dispose(). الحل: فصل "تنظيف الموارد" عن "إشعار الواجهة بإعادة البناء"
  // عبر معامل [notify]، بحيث يمرر dispose() القيمة false دائمًا.
  void _disposePlayer({bool notify = true}) {
    _controller?.videoPlayerController
        ?.removeListener(_onVideoValueChanged);
    _controlsTimer?.cancel();
    _watermarkTimer?.cancel();
    _seekBubbleTimer?.cancel();
    _seekCommitTimer?.cancel();
    final c = _controller;
    _controller = null;
    c?.dispose(forceDispose: true);
    if (notify && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fvc.removeListener(_onControllerChanged);
    // ⚠️ notify: false — لا يجوز استدعاء setState() من dispose()، انظر
    // الشرح أعلاه.
    _disposePlayer(notify: false);
    super.dispose();
  }

  // ── Clamp position to screen bounds ─────────────────────────

  Offset _clampPosition(Offset pos, Size screen) {
    final maxX = screen.width - _width;
    final maxY = screen.height - _height - 24; // avoid nav bar
    return Offset(
      pos.dx.clamp(0.0, maxX),
      pos.dy.clamp(0.0, maxY),
    );
  }

  // ── Restore full screen ─────────────────────────────────────

  /// Captures the floating player's current position/speed/quality/
  /// play-state, tears down the floating player, and pushes the
  /// full-screen player back so it resumes at exactly the same spot.
  void _expandToFullScreen() {
    final fvcState = _fvc.videoState;
    if (fvcState == null) return;

    final position =
        _controller?.videoPlayerController?.value.position ?? Duration.zero;
    final isPlaying = _controller?.isPlaying() ?? _isPlaying;

    _fvc.updatePlaybackSnapshot(
      position: position,
      speed: _currentSpeed,
      quality: _currentQuality,
      isPlaying: isPlaying,
    );

    final streams = fvcState.streams;
    final title = fvcState.title;

    _disposePlayer();
    _fvc.stopFloating();

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => NativeVideoPlayerScreen(
          streams: streams,
          title: title,
          initialPosition: position,
          initialSpeed: _currentSpeed,
          initialQuality: _currentQuality,
          initialAutoPlay: isPlaying,
        ),
      ),
    );
  }

  // ── Seek buttons ─────────────────────────────────────────────

  // ✅ إصلاح جذري لمشكلة اختفاء الـ controls نهائيًا على بعض الأجهزة (مثل
  // iPhone 11): كان الـ GestureDetector الخارجي يحمل onTap و onDoubleTap
  // معًا على نفس المنطقة. عندما يكون onDoubleTap موجودًا، يضطر Flutter إلى
  // تأخير onTap لمدة ~300ms بعد كل لمسة ليتأكد أن لمسة ثانية لن تتبعها
  // (لتمييز double-tap عن tap عادي). هذا التحكيم (gesture arbitration) هو
  // نفسه ما كان يفشل بصمت على بعض الأجهزة، فلا يصل onTap أبدًا ولا تظهر
  // الـ controls بأي طريقة. الحل الجذري: إزالة onDoubleTap كليًا من كاشف
  // الإيماءات الخارجي، واستبدال "النقر المزدوج للتقديم/الترجيع" بأيقونتين
  // صريحتين (⏪ / ⏩) داخل شريط الـ controls نفسه. الآن onTap هو الإيماءة
  // الوحيدة على تلك المنطقة فيصل فورًا وبثبات على كل الأجهزة، بينما التقديم
  // والترجيع أصبحا فعلًا صريحًا (button tap) لا يتنافس مع أي شيء.
  //
  // منطق التراكم (cumulative seek) نفسه محفوظ كما كان: الضغط المتكرر على
  // نفس الأيقونة أثناء ظهور الفقاعة يتراكم (10s, 20s, 30s...) بدلاً من أن
  // تتنافس كل ضغطة مع سابقتها.
  void _seekBy(bool forward) {
    final isSameBurst = _showSeekBubble && _seekBubbleForward == forward;
    if (!isSameBurst) {
      _seekBurstBase = _controller?.videoPlayerController?.value.position ??
          _videoPosition;
      _seekBurstSteps = 0;
    }
    _seekBurstSteps += forward ? 1 : -1;

    final total = _videoDuration;
    Duration target = _seekBurstBase + (_seekStep * _seekBurstSteps);
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;

    setState(() {
      _videoPosition = target;
      _seekBubbleForward = forward;
      _seekBubbleSeconds = _seekStep.inSeconds * _seekBurstSteps.abs();
      _showSeekBubble = true;
    });
    _showControls();

    // ✅ نؤجل استدعاء seekTo() الفعلي 350ms بعد آخر نقرة بدلاً من إرسال أمر
    // seek منفصل مع كل نقرة على حدة. عدة أوامر seek متتالية بسرعة كانت
    // تتنافس مع بعضها داخل المشغل (كل seekTo جديد يُلغي/يتجاوز السابق قبل
    // اكتماله)، فيظهر التراكم صحيحًا في الواجهة لكن الفيديو الفعلي لا
    // يصل إلا لجزء من المسافة المطلوبة.
    _seekCommitTimer?.cancel();
    _seekCommitTimer = Timer(const Duration(milliseconds: 350), () {
      try {
        _controller?.seekTo(target);
      } catch (_) {}
    });

    _seekBubbleTimer?.cancel();
    _seekBubbleTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _showSeekBubble = false;
        _seekBurstSteps = 0;
      });
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ── Quality picker ───────────────────────────────────────────

  void _switchQuality(String q) {
    final url = _fvc.videoState?.streams[q];
    if (url == null || q == _currentQuality) return;
    setState(() => _currentQuality = q);
    try {
      _controller?.setResolution(url);
      if (_currentSpeed != 1.0) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          try {
            _controller?.setSpeed(_currentSpeed);
          } catch (_) {}
        });
      }
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'FloatingVideo setResolution');
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    // ✅ إعادة ضبط العرض إذا تغيّر مقاس الشاشة (تدوير الجهاز، أو فتح
    // النافذة على شاشة أصغر) بحيث لا تبقى النافذة العائمة أكبر من المسموح.
    final maxW = _maxWidthForScreen(screen);
    if (_width > maxW) {
      _width = maxW;
    } else if (_width < _minW) {
      _width = _minW;
    }

    // On first build, snap to bottom-right
    if (_position == const Offset(16, 400)) {
      _position = Offset(
        screen.width - _width - widget.initialOffset.dx,
        screen.height - _height - widget.initialOffset.dy,
      );
    } else {
      // ✅ إصلاح: النافذة العائمة كانت "تختفي" عند تدوير الجهاز.
      //
      // السبب: _position (إحداثيات أعلى-يسار النافذة) كانت تُثبّت فقط داخل
      // معالجات السحب (onPanUpdate) ومقبض التصغير، ولا يُعاد ضبطها إطلاقًا
      // عند تغيّر *مقاس الشاشة نفسه* بسبب التدوير — فقط _width كانت تُعاد
      // مطابقتها أعلاه. فمثلاً في الوضع الأفقي (812×375) قد تكون
      // _position.dx ≈ 556 (بالقرب من الحافة اليمنى)، وهي قيمة صالحة تمامًا
      // هناك. لكن عند التدوير للوضع الرأسي يصبح عرض الشاشة 375 فقط بينما
      // تبقى dx=556 كما هي — أي خارج حدود الشاشة الجديدة تمامًا، فتُرسم
      // النافذة العائمة فعليًا خارج الشاشة المرئية (لم تُغلق ولم تُتلف، لكنها
      // غير مرئية فقط). عند العودة إلى الوضع الأفقي يتسع عرض الشاشة من جديد
      // فتصبح dx=556 صالحة مجددًا، فتظهر النافذة كأنها "عادت" من العدم.
      //
      // الحل: إعادة تثبيت (clamp) _position ضمن حدود الشاشة الحالية في كل
      // بناء (build)، وليس فقط داخل معالجات السحب/التصغير. العملية رخيصة
      // (مجرد عمليتي clamp) ولا تؤثر على أي شيء إذا كانت النافذة أصلاً ضمن
      // الحدود الصحيحة.
      _position = _clampPosition(_position, screen);
    }

    return AnimatedPositioned(
      duration: _isDragging
          ? Duration.zero
          : const Duration(milliseconds: 120),
      left: _position.dx,
      top: _position.dy,
      // ✅ إصلاح تعارض الإيماءات (gesture arena race):
      // كان مقبض التصغير (resize handle) عبارة عن GestureDetector متداخل
      // (نسل) داخل شجرة الـ GestureDetector الخارجي المسؤول عن السحب/النقر.
      // عندما يغطي كلا الـ GestureDetector نفس منطقة اللمس ويطلبان نوع
      // إيماءة من نفس العائلة (pan/drag)، يدخل الاثنان في نفس "ساحة
      // الإيماءات" (gesture arena) لكل لمسة، وFlutter يفصل الفائز بناءً على
      // تفاصيل توقيت/حركة دقيقة تختلف من جهاز لآخر — وهذا بالضبط سبب أن
      // بعض الهواتف كانت "تبتلع" كل لمسة كسحب خارجي صغير فلا يظهر onTap
      // أبدًا (ماعدا فوق أيقونة التصغير نفسها حيث كان الفائز أحيانًا هو
      // كاشف النقر الخارجي)، بينما مقبض التصغير لا يفوز أبدًا فلا يعمل.
      //
      // الحل المعماري: نجعل مقبض التصغير "شقيقًا" (sibling) للـ
      // GestureDetector الخارجي بدلاً من كونه من ذريته، عبر وضعهما معًا
      // داخل Stack واحد على نفس المستوى. بهذه الطريقة لا توجد علاقة سلف/نسل
      // بينهما إطلاقًا، ولا يوجد شيء يتنافس عليه في ساحة الإيماءات — يقوم
      // Stack باختبار الإصابة (hit-testing) ويوجّه اللمسة حتمًا إلى العنصر
      // الأعلى (مقبض التصغير) عندما تقع فوقه، وإلى الكاشف الخارجي في أي
      // مكان آخر، بشكل متطابق على كل الأجهزة.
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Whole-widget drag / tap / double-tap detector ────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // ── Drag ──────────────────────────────────────────
              onPanStart: (_) => setState(() => _isDragging = true),
              onPanUpdate: (d) {
                setState(() {
                  _position = _clampPosition(
                    _position + d.delta,
                    screen,
                  );
                });
              },
              onPanEnd: (_) => setState(() => _isDragging = false),
              // ── Tap to toggle controls ─────────────────────────
              // ✅ onDoubleTap أُزيل عمدًا من هنا — انظر شرح _seekBy() أعلاه.
              // بقاء onTap وحيدًا بلا onDoubleTap يعني عدم وجود أي تأخير أو
              // تحكيم إيماءات، فتظهر الـ controls بمجرد لمسة واحدة بثبات.
              onTap: _showControls,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _width,
                  height: _height,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                    border: Border.all(
                      color: AppColors.accentYellow.withOpacity(0.4),
                      width: 1.2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                    // ── Video ────────────────────────────────────
                    if (_controller != null && !_isError)
                      Positioned.fill(
                        child: BetterPlayer(controller: _controller!),
                      )
                    else if (_isInitializing)
                      Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.accentYellow,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 28),
                      ),

                    // ── Watermark ────────────────────────────────
                    if (_controller != null && !_isError)
                      Positioned.fill(
                        child: AnimatedAlign(
                          alignment: _watermarkAlignment,
                          duration: const Duration(seconds: 2),
                          child: IgnorePointer(
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _fvc.videoState?.watermarkText ?? '',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // ── Controls overlay ─────────────────────────
                    if (_controlsVisible)
                      _buildControls(screen),

                    // ── Double-tap seek indicator ─────────────────
                    // ✅ يعرض الآن الرقم التراكمي (10/20/30...) وليس أيقونة
                    // ثابتة فقط، حتى يرى المستخدم مقدار القفزة الفعلية عند
                    // النقر المزدوج المتكرر بسرعة.
                    if (_showSeekBubble)
                      Align(
                        alignment: _seekBubbleForward
                            ? const Alignment(0.6, 0)
                            : const Alignment(-0.6, 0),
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _seekBubbleForward
                                      ? Icons.fast_forward
                                      : Icons.fast_rewind,
                                  color: AppColors.accentYellow,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${_seekBubbleSeconds}s',
                                  style: TextStyle(
                                    color: AppColors.accentYellow,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Resize handle (bottom-right) ──────────────────
            // ✅ الآن شقيق (sibling) للـ GestureDetector الخارجي أعلاه، وليس
            // من ذريته — انظر التعليق التوضيحي فوق الـ SizedBox. هذا يزيل
            // أي علاقة سلف/نسل بين كاشفي الإيماءات فلا يتنافسان في نفس
            // ساحة الإيماءات، ويصبح ظهور الـ controls وعمل التصغير متطابقًا
            // على جميع الأجهزة.
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  setState(() {
                    // ✅ الحد الأقصى أصبح ديناميكيًا (maxW) بدلاً من رقم
                    // ثابت، فيسمح بتكبير النافذة حتى حواف الشاشة على
                    // الأجهزة اللوحية والشاشات الكبيرة.
                    _width = (_width + d.delta.dx).clamp(_minW, maxW);
                    // Re-clamp position so we don't go off-screen
                    _position = _clampPosition(_position, screen);
                  });
                },
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Icon(
                    Icons.open_in_full,
                    color: AppColors.accentYellow.withOpacity(0.85),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(Size screen) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
        ),
        child: Stack(
          children: [
            // ── Close button (top-right) ─────────────────────
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  _disposePlayer();
                  _fvc.stopFloating();
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close,
                      color: AppColors.accentYellow, size: 20),
                ),
              ),
            ),

            // ── Expand to full screen (top-right, next to close) ─
            Positioned(
              top: 4,
              right: 38,
              child: GestureDetector(
                onTap: _expandToFullScreen,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fullscreen,
                      color: AppColors.accentYellow, size: 20),
                ),
              ),
            ),

            // ── Title (top-left) ─────────────────────────────
            Positioned(
              top: 8,
              left: 6,
              right: 72,
              child: Text(
                _fvc.videoState?.title ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
            ),

            // ── Seek back / Play-Pause / Seek forward ─────────
            // ✅ الأيقونتان الجديدتان تحلّان محل النقر المزدوج القديم —
            // تراكم القفزات (10s, 20s, 30s...) محفوظ عبر _seekBy(), وكل
            // ضغطة هي فعل صريح لا يتداخل مع onTap الخاص بإظهار الـ controls.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _seekBy(false),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.replay_10,
                        color: AppColors.accentYellow,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    onTap: () {
                      if (_controller?.isPlaying() ?? false) {
                        _controller?.pause();
                      } else {
                        _controller?.play();
                      }
                      _showControls();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: AppColors.accentYellow,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    onTap: () => _seekBy(true),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.forward_10,
                        color: AppColors.accentYellow,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Quality badge (bottom-left, above seek bar) ────
            if (_sortedQualities.length > 1)
              Positioned(
                bottom: 20,
                left: 4,
                child: GestureDetector(
                  onTap: () => _showQualityPicker(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppColors.accentYellow.withOpacity(0.5),
                          width: 0.8),
                    ),
                    child: Text(
                      _currentQuality,
                      style: TextStyle(
                        color: AppColors.accentYellow,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Elapsed / total time (bottom-right, above seek bar) ─
            if (_videoDuration > Duration.zero)
              Positioned(
                bottom: 20,
                right: 4,
                child: Text(
                  '${_formatDuration(_isScrubbing ? Duration(milliseconds: (_scrubFraction * _videoDuration.inMilliseconds).round()) : _videoPosition)} / ${_formatDuration(_videoDuration)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),

            // ── Seek bar (bottom, full width, draggable) ───────
            _buildSeekBar(),
          ],
        ),
      ),
    );
  }

  /// Thin, draggable progress bar pinned to the bottom edge of the
  /// floating window. Tap anywhere on it to jump to that point, or drag
  /// the thumb to scrub — all without leaving the floating window.
  Widget _buildSeekBar() {
    final hasDuration = _videoDuration > Duration.zero;
    final progress = hasDuration
        ? (_isScrubbing
                ? _scrubFraction
                : _videoPosition.inMilliseconds /
                    _videoDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    void seekToFraction(double dx) {
      if (!hasDuration) return;
      final fraction = (dx / _width).clamp(0.0, 1.0);
      setState(() => _scrubFraction = fraction);
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 18, // generous touch target even though the visible track is thin
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          if (!hasDuration) return;
          final fraction = (d.localPosition.dx / _width).clamp(0.0, 1.0);
          final target = Duration(
              milliseconds:
                  (fraction * _videoDuration.inMilliseconds).round());
          try {
            _controller?.seekTo(target);
          } catch (_) {}
          setState(() => _videoPosition = target);
          _showControls();
        },
        onHorizontalDragStart: (d) {
          if (!hasDuration) return;
          _controlsTimer?.cancel();
          setState(() {
            _isScrubbing = true;
            _scrubFraction = progress;
          });
          seekToFraction(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => seekToFraction(d.localPosition.dx),
        onHorizontalDragEnd: (_) {
          if (!hasDuration) return;
          final target = Duration(
              milliseconds:
                  (_scrubFraction * _videoDuration.inMilliseconds).round());
          try {
            _controller?.seekTo(target);
          } catch (_) {}
          setState(() {
            _videoPosition = target;
            _isScrubbing = false;
          });
          _showControls();
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track background
              Container(height: 3, color: Colors.white24),
              // Played portion
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(height: 3, color: AppColors.accentYellow),
              ),
              // Thumb
              if (hasDuration)
                Positioned(
                  left: (progress * _width - 4).clamp(0.0, _width - 8),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualityPicker() {
    // ✅ لا نستخدم context الخاص بـ FloatingVideoOverlay هنا لأنه لا يملك
    // Navigator كسلف (النافذة العائمة موضوعة فوق الـ Navigator داخل
    // MaterialApp.builder، وليست من ذريته — انظر app.dart). استخدام هذا
    // الـ context مباشرةً مع showModalBottomSheet هو بالضبط ما كان يسبب
    // خطأ: "Navigator operation requested with a context that does not
    // include a Navigator". لذلك نستخدم navigatorKey.currentContext الذي
    // يشير دائمًا إلى سياق متصل فعليًا بجذر الـ Navigator.
    final sheetContext = navigatorKey.currentContext;
    if (sheetContext == null) return;
    showModalBottomSheet(
      context: sheetContext,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetBuilderContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 3,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            ..._sortedQualities.map((q) => ListTile(
                  dense: true,
                  leading: Icon(
                    q == _currentQuality
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: q == _currentQuality
                        ? AppColors.accentYellow
                        : Colors.white54,
                    size: 18,
                  ),
                  title: Text(q,
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    // ✅ نستخدم context الخاص ببناء الـ sheet نفسه (وهو من
                    // ذرية الـ Navigator الذي فُتحت عليه الورقة فعليًا)
                    // بدلاً من context الخارجي الخاص بالنافذة العائمة.
                    Navigator.pop(sheetBuilderContext);
                    _switchQuality(q);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
