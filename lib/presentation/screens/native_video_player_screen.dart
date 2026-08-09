import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/services/audio_protection_service.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../core/services/app_state.dart';
import '../../core/services/floating_video_controller.dart'; // إضافة متحكم الفيديو العائم
import '../../main.dart' show navigatorKey;

class NativeVideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
  final String title;

  /// Lesson/video ID used to re-fetch a fresh signed stream URL from
  /// `/api/secure/get-video-id` when the user retries after a playback
  /// error. Optional so screens that don't have an ID handy still work —
  /// retry then simply reuses the original (possibly stale/expired) URLs,
  /// same as before this fix.
  final String? lessonId;

  /// Playback handoff — set when returning from the floating (PiP) player,
  /// so full-screen resumes at the same position, speed and quality
  /// instead of restarting from the beginning.
  final Duration? initialPosition;
  final double? initialSpeed;
  final String? initialQuality;
  final bool initialAutoPlay;

  const NativeVideoPlayerScreen({
    super.key,
    required this.streams,
    required this.title,
    this.lessonId,
    this.initialPosition,
    this.initialSpeed,
    this.initialQuality,
    this.initialAutoPlay = true,
  });

  @override
  State<NativeVideoPlayerScreen> createState() =>
      _NativeVideoPlayerScreenState();
}

class _NativeVideoPlayerScreenState extends State<NativeVideoPlayerScreen>
    with WidgetsBindingObserver {
  BetterPlayerController? _betterPlayerController;

  final AudioProtectionService _protectionService = AudioProtectionService();
  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;

  // ✅ نسخة قابلة للتعديل من widget.streams. تبدأ بنفس القيم الممرَّرة من
  // الشاشة السابقة، لكن _retryCurrentQuality() قد يستبدلها بروابط جديدة
  // موقّعة حديثًا (بعد استدعاء get-video-id من جديد) بدل الاعتماد إلى الأبد
  // على نفس الخريطة الأصلية التي قد تحتوي روابط منتهية الصلاحية.
  late Map<String, String> _streamsMap;

  String _currentQuality = "";
  List<String> _sortedQualities = [];

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitializing = true;
  bool _isDisposing = false;

  int _currentQualityIndex = 0;
  bool _handoffApplied = false;

  // ✅ إصلاح "إعادة المحاولة" بعد انقطاع الشبكة: نحفظ هنا آخر موضع تشغيل
  // معروف لحظة ظهور الخطأ، لنتمكن من العودة إليه بعد إعادة إنشاء المشغّل
  // من جديد في _retryCurrentQuality() (انظر التعليق هناك لتفاصيل السبب).
  Duration? _pendingRetryPosition;

  // ✅ آخر موضع طُبِّق فعليًا كـ seekTo() بعد إعادة محاولة سابقة. يُستخدَم في
  // _applyRetryStateIfNeeded() لتفادي إعادة الالتصاق بنفس النقطة التي فشل
  // التشغيل عندها للتو (انظر التعليق هناك).
  Duration? _lastRetrySeekTarget;

  // ✅ عداد وتايمر إعادة المحاولة التلقائية عند اكتشاف خطأ من نوع "خطأ خادم"
  // (يوجد اتصال إنترنت لكن البث نفسه فشل) — انظر _classifyAndHandleNetworkError.
  int _autoRetryAttempt = 0;
  Timer? _autoRetryTimer;
  static const int _maxAutoRetries = 3;

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  double _currentSpeed = 1.0;
  static const List<double> _speedOptions = [
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0,
  ];

  int _pendingSeekDelta = 0;
  Duration _seekBaseline = Duration.zero;
  Timer? _seekIndicatorTimer;
  bool _showSeekIndicator = false;
  bool _seekIndicatorIsForward = true;

  BoxFit _videoFit = BoxFit.contain;
  static const List<BoxFit> _fitCycle = [BoxFit.contain, BoxFit.fill, BoxFit.fitWidth];
  static const List<String> _fitLabels = ['16:9', 'Full', 'Wide'];
  int _fitIndex = 0;

  bool _isHolding2x = false;
  double _speedBeforeHold = 1.0;

  final Map<String, String> _headers = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)',
  };

  // ── Custom Controls State ──────────────────────────────────────────────
  bool _controlsVisible = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _videoDuration = Duration.zero;
  bool _isSeekBarDragging = false;
  Timer? _controlsAutoHideTimer;

  void _toggleControls() {
    if (_betterPlayerController == null || _isDisposing) return;
    setState(() => _controlsVisible = !_controlsVisible);
    _resetAutoHideTimer();
  }

  void _resetAutoHideTimer() {
    _controlsAutoHideTimer?.cancel();
    if (_controlsVisible) {
      _controlsAutoHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !_isSeekBarDragging) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _togglePlayPause() {
    if (_betterPlayerController == null || _isDisposing) return;
    if (_betterPlayerController!.isPlaying() ?? false) {
      _betterPlayerController!.pause();
    } else {
      _betterPlayerController!.play();
    }
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _resetAutoHideTimer();
  }

  void _attachVideoListener() {
    final vpc = _betterPlayerController?.videoPlayerController;
    if (vpc == null) return;
    vpc.removeListener(_onVideoValueChanged);
    vpc.addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _onVideoValueChanged() {
    if (!mounted || _isDisposing) return;
    final value = _betterPlayerController?.videoPlayerController?.value;
    if (value == null) return;
    setState(() {
      _isPlaying = value.isPlaying;
      if (!_isSeekBarDragging) _position = value.position;
      _videoDuration = value.duration ?? Duration.zero;
    });

    // ✅ التشغيل تجاوز نقطة إعادة المحاولة الأخيرة بأمان (5 ثوانٍ) دون فشل
    // جديد — نعتبر أن التعافي نجح فعليًا ونمسح علامة "نفس نقطة الفشل" حتى
    // لا تُستخدَم بالخطأ في مقارنة مستقبلية غير ذات صلة.
    final lastTarget = _lastRetrySeekTarget;
    if (lastTarget != null &&
        value.isPlaying &&
        value.position - lastTarget > const Duration(seconds: 5)) {
      _lastRetrySeekTarget = null;
    }
  }

  void _onSeekStart(double _) {
    _isSeekBarDragging = true;
    _controlsAutoHideTimer?.cancel();
  }

  void _onSeekChanged(double value) {
    setState(() => _position = Duration(milliseconds: value.toInt()));
  }

  void _onSeekEnd(double value) {
    // ── Fix: "Bad state: The video has not been initialized yet." ──
    // seekTo() هي دالة async؛ إن رمت الاستثناء بعد نقطة await داخلية
    // (وهو ما يحدث عندما يسحب المستخدم شريط التقدّم قبل اكتمال تهيئة
    // المشغّل بلحظات)، فإن try/catch متزامن حول الاستدعاء لا يلتقطه إطلاقاً
    // لأن الاستدعاء يُرجع Future فوراً قبل أن يُنفَّذ الجزء اللاحق للـ await.
    // استخدام catchError() على الـ Future المُرجعة يضمن التقاط الخطأ في
    // الحالتين (المتزامنة وغير المتزامنة) بدل أن يتحول إلى كراش قاتل.
    try {
      _betterPlayerController
          ?.seekTo(Duration(milliseconds: value.toInt()))
          .catchError((Object e, StackTrace st) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'Native Player Seekbar Error');
      });
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'Native Player Seekbar Error');
    }
    _isSeekBarDragging = false;
    _resetAutoHideTimer();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _streamsMap = Map<String, String>.from(widget.streams);
    if (widget.initialSpeed != null) {
      _currentSpeed = widget.initialSpeed!;
    }
    _sortQualities();
    _loadUserData();
    _initializeProtection();
    _setupScreen();
  }

  void _sortQualities() {
    _sortedQualities = _streamsMap.keys.toList();
    _sortedQualities.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return numB.compareTo(numA);
    });
    if (_sortedQualities.isNotEmpty) {
      // If we're resuming from the floating player, keep the exact same
      // quality it was playing at instead of falling back to a default.
      final handoffQuality = widget.initialQuality;
      if (handoffQuality != null &&
          _sortedQualities.contains(handoffQuality)) {
        _currentQualityIndex = _sortedQualities.indexOf(handoffQuality);
        _currentQuality = handoffQuality;
        return;
      }

      const priorityOrder = ['360', '480', '240', '720'];
      int chosenIndex = -1;
      for (final p in priorityOrder) {
        final idx = _sortedQualities.indexWhere(
          (q) => q.replaceAll(RegExp(r'[^0-9]'), '') == p,
        );
        if (idx != -1) {
          chosenIndex = idx;
          break;
        }
      }
      _currentQualityIndex =
          chosenIndex != -1 ? chosenIndex : (_sortedQualities.length / 2).floor();
      _currentQuality = _sortedQualities[_currentQualityIndex];
    }
  }

  Future<void> _initializeProtection() async {
    try {
      await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);
      await _protectionService.blockAudioCapture();
      await _protectionService.startMonitoring();
      _recordingSubscription =
          _protectionService.recordingStateStream.listen((isRecording) {
        if (isRecording) _handleRecordingDetected();
      });
      debugPrint("🛡️ Protection Enabled in Native Video Player");
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player Protection Init Error');
    }
  }

  void _handleRecordingDetected() {
    if (!mounted) return;
    setState(() => _isRecordingDetected = true);
    _betterPlayerController?.setVolume(0.0);
    _betterPlayerController?.pause();
    FirebaseCrashlytics.instance.log(
        "🚨 Security: Screen Recording Detected! Native Player Muted & Paused.");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _betterPlayerController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE)
          .catchError((_) {});
      _protectionService.blockAudioCapture();
      if (_isRecordingDetected) {
        _betterPlayerController?.setVolume(0.0);
        _betterPlayerController?.pause();
      }
      // ✅ إعادة تطبيق الـ videoGravity الصحيح على iOS عند العودة من
      // الخلفية: نظام iOS قد يعيد بناء الـ AVPlayerLayer الأصلي عند
      // استئناف التطبيق، وهذا قد يفقد قيمة الـ gravity المضبوطة سابقًا
      // ويعيد الفيديو لسلوك iOS الافتراضي (عريض/مقصوص) دون أي إشعار.
      _forceApplyIOSVideoGravity();
    }
  }

  void _loadUserData() {
    String displayText = '';

    final userData = AppState().userData;
    if (userData != null) {
      displayText = (userData['phone'] as String? ?? '').trim();
      if (displayText.isEmpty) displayText = (userData['name'] as String? ?? '').trim();
      if (displayText.isEmpty) displayText = (userData['email'] as String? ?? '').trim();
      if (displayText.isEmpty) displayText = (userData['username'] as String? ?? '').trim();
    }

    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          final box = Hive.box('auth_box');
          displayText = (box.get('phone') as String? ?? '').trim();
          if (displayText.isEmpty) displayText = (box.get('name') as String? ?? '').trim();
          if (displayText.isEmpty) displayText = (box.get('email') as String? ?? '').trim();
          if (displayText.isEmpty) displayText = (box.get('username') as String? ?? '').trim();
        }
      } catch (_) {}
    }

    _watermarkText = displayText.isNotEmpty ? displayText : 'Unknown User';
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_isDisposing) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {
          final random = Random();
          double x = (random.nextDouble() * 1.6) - 0.8;
          double y = (random.nextDouble() * 1.6) - 0.8;
          _watermarkAlignment = Alignment(x, y);
        });
      }
    });
  }

  Future<void> _setupScreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await WakelockPlus.enable();

      if (_currentQuality.isEmpty || _streamsMap[_currentQuality] == null) {
        throw Exception("No playable stream available");
      }

      _initializePlayer();
      _startWatermarkAnimation();
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Native Player Setup Error');
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "تعذر بدء تشغيل الفيديو.";
          _isInitializing = false;
        });
      }
    }
  }

  bool _isNetworkError(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('sockettimeoutexception') ||
        msg.contains('unknownhostexception') ||
        msg.contains('connectexception') ||
        msg.contains('econnreset') ||
        msg.contains('httpdatasourceexception') ||
        msg.contains('ioexception') ||
        msg.contains('io exception') ||
        msg.contains('unable to connect') ||
        msg.contains('failed to connect') ||
        msg.contains('no address associated with hostname') ||
        msg.contains('behindlivewindowexception') ||
        msg.contains('software caused connection abort') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection reset') ||
        msg.contains('connection refused');
  }

  bool _isCodecError(dynamic e) {
    final msg = e.toString().toLowerCase();
    // ✅ فحص خطأ الشبكة أولًا: ExoPlaybackException هو غلاف عام تستخدمه
    // ExoPlayer لأي نوع فشل (شبكة/مصدر/عرض)، وليس فقط أخطاء الكوديك.
    // عند انقطاع الإنترنت تُلَفّ IOException بداخل ExoPlaybackException،
    // فيبقى نص "ExoPlaybackException" ظاهرًا في رسالة الخطأ ويؤدي إلى
    // تصنيف انقطاع الشبكة خطأً كـ "خطأ كوديك" (ويحاول التطبيق حينها
    // التبديل تلقائيًا لجودة أقل بدل إخبار المستخدم بفحص اتصاله — وهذا
    // التبديل سيفشل أيضًا لأن السبب شبكة وليس كوديك).
    if (_isNetworkError(e)) return false;
    return msg.contains('mediacodec') ||
        msg.contains('video/mp2t') ||
        msg.contains('videorenderer') ||
        msg.contains('codecexception') ||
        msg.contains('decoderinitializationexception') ||
        msg.contains('mediacodecvideorenderererror');
  }

  void _initializePlayer() {
    if (!mounted || _isDisposing) return;

    final initialUrl = _streamsMap[_currentQuality]!;

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      initialUrl,
      headers: _headers,
      videoFormat: BetterPlayerVideoFormat.hls,
      resolutions: _streamsMap,
      cacheConfiguration: const BetterPlayerCacheConfiguration(useCache: false),
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
    );

    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        fit: _videoFit,
        autoPlay: widget.initialAutoPlay,
        looping: false,
        fullScreenByDefault: false,
        allowedScreenSleep: true,
        autoDetectFullscreenDeviceOrientation: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false, // 🔴 تعطيل المتحكمات الافتراضية
          showControlsOnInitialize: false,
          enableFullscreen: false,
          enablePip: false,
          enableQualities: false,
          enableSubtitles: false,
          enableAudioTracks: false,
          enableSkips: false,
          enableMute: true,
          enablePlaybackSpeed: false,
          enableOverflowMenu: false,
          controlBarHeight: 52,
          loadingColor: AppColors.accentYellow,
          progressBarPlayedColor: AppColors.accentYellow,
          progressBarHandleColor: AppColors.accentYellow,
          progressBarBufferedColor: Colors.white24,
          progressBarBackgroundColor: Colors.white10,
          textColor: Colors.white,
        ),
        errorBuilder: (context, errorMessage) {
          return const SizedBox.shrink();
        },
      ),
      betterPlayerDataSource: dataSource,
    );

    controller.addEventsListener(_onPlayerEvent);

    setState(() {
      _betterPlayerController = controller;
      _isInitializing = false;
      _isError = false;
    });
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (!mounted || _isDisposing) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        // ✅ إصلاح: كنا نسجّل فقط النص المُستخرج (errMsg) في Crashlytics،
        // وهو أحيانًا مجرد غلاف عام (مثل "ExoPlaybackException: Source
        // error") لا يوضّح السبب *الفعلي* القادم من خادم بث Bunny (رمز HTTP
        // حقيقي، رسالة الخادم، اسم المضيف...). نحتفظ الآن بالكائن الأصلي
        // (rawCause) كما هو ونمرره لـ recordError مباشرة (بدل .toString())
        // حتى يظهر نوعه وتفاصيله الكاملة في تقرير Crashlytics، مع تسجيل
        // الجودة والمضيف (host) الحاليين في سياق منفصل لتسهيل تتبع أعطال
        // بث Bunny تحديدًا.
        final rawCause =
            event.parameters?['exception'] ?? event.parameters?['error'];
        final errMsg = (rawCause ?? 'Unknown player exception').toString();
        final currentUrl = _streamsMap[_currentQuality] ?? '';
        final currentHost = Uri.tryParse(currentUrl)?.host ?? 'unknown-host';
        FirebaseCrashlytics.instance.log(
          '⚠️ Native Player (Bunny stream) exception: $errMsg | quality=$_currentQuality | host=$currentHost | params=${event.parameters}',
        );
        // ✅ [FIX] لا نمرر rawCause كما هو إلى recordError(). rawCause قد
        // يكون كائناً خاماً قادماً من قناة المنصّة (Map، PlatformException
        // بمحتوى غير قياسي...) — وقد رأينا حالات فعلية كان فيها استدعاء
        // recordError() *نفسه* هو من يرمي أثناء محاولة تحويل rawCause إلى
        // نص، فيتحول خطأ تشغيل غير قاتل إلى Uncaught Error حقيقي يصعد إلى
        // معالج runZonedGuarded العام في main.dart ويُسجَّل هناك كـ
        // fatal:true — أي أن كراش "قاتل" مزعج كان في الأصل مجرد فشل تسجيل
        // خطأ الفيديو العادي. الآن نحوّل rawCause دائماً إلى Exception/نص
        // آمن قبل تمريره.
        Object safeCause;
        try {
          safeCause = (rawCause is Exception || rawCause is Error)
              ? rawCause!
              : Exception(errMsg);
        } catch (_) {
          safeCause = Exception('Unserializable player exception');
        }
        FirebaseCrashlytics.instance.recordError(
          safeCause,
          null,
          reason: 'Native Player Bunny Stream Playback Error ($_currentQuality @ $currentHost)',
          fatal: false,
        );
        _handlePlayerError(errMsg, isCodecRelated: _isCodecError(errMsg));
        break;
      case BetterPlayerEventType.initialized:
        // ✅ نجحت التهيئة: أوقف أي إعادة محاولة تلقائية مجدولة وصفّر عداد
        // محاولات "خطأ الخادم" حتى تُحسَب من جديد بشكل مستقل عند أي فشل لاحق.
        _autoRetryTimer?.cancel();
        _autoRetryAttempt = 0;
        if (_isError) {
          setState(() {
            _isError = false;
          });
        }
        _attachVideoListener(); // 🟢 ربط الـ Listener المخصص
        _applyHandoffStateIfNeeded();
        _applyRetryStateIfNeeded();
        // Sync iOS's native videoGravity with the current fit selection now
        // that the player (and its platform view) actually exists.
        // ✅ إصلاح: الفيديو كان يظهر "عريضًا" (مقصوصًا بلا أشرطة سوداء) على
        // iOS رغم أن "Contain" (16:9) هو الافتراضي المختار دائمًا.
        //
        // السبب: better_player_plus مثبّتة عند الإصدار 1.2.1 تحديدًا (بسبب
        // تعارض بين الحزم كان يمنع الترقية). سجل تغييرات الحزمة نفسها يوضح
        // أن معالجة BoxFit التلقائية والموثوقة على iOS (قيمة افتراضية
        // أصلية = resizeAspect + إعادة محاولة مجدولة لتطبيق الـ gravity) لم
        // تُضَف إلا في إصدار لاحق (1.3.2)، وليست موجودة في 1.2.1 المثبَّتة
        // هنا. لذلك كان تطبيقنا يعتمد على استدعاء واحد فقط لـ
        // _applyIOSVideoGravity() عند حدث "initialized" — وفي 1.2.1 هذا
        // الاستدعاء الوحيد يمكن أن يخسر السباق مع تهيئة الـ AVPlayerLayer
        // الأصلية (مثلاً إذا لم يكن playerView قد أُنشئ بعد فعليًا لحظة
        // وصول الأمر عبر قناة المنصّة)، فيعود الفيديو لسلوك iOS الافتراضي
        // غير المحتوى (عريض/مقصوص) دون أي تنبيه.
        //
        // الحل: بدلاً من استدعاء واحد، نعيد تطبيق الـ gravity الصحيح عدة
        // مرات على فترات متباعدة (فوريًا، ثم بعد إطار واحد، ثم بعد فترات
        // قصيرة متتالية) لضمان أن آخر استدعاء يصل دائمًا بعد أن يكون الـ
        // playerView قد أُنشئ فعليًا — بغض النظر عن أي سباق توقيت في نسخة
        // الحزمة المثبَّتة. هذه العملية رخيصة جدًا (استدعاء قناة منصّة فارغ
        // تقريبًا) ولا تأثير مرئي لها إذا كانت القيمة صحيحة أصلًا.
        _forceApplyIOSVideoGravity();
        break;
      default:
        break;
    }
  }

  void _handlePlayerError(String errorDescription, {required bool isCodecRelated}) {
    if (!mounted || _isDisposing) return;

    // ✅ نحفظ آخر موضع تشغيل معروف (_position يُحدَّث باستمرار من
    // _onVideoValueChanged أثناء التشغيل الطبيعي) لحظة وقوع أي خطأ، بصرف
    // النظر عن نوعه. لو أعاد المستخدم لاحقًا الضغط على "إعادة المحاولة"
    // (_retryCurrentQuality)، سنستخدم هذه القيمة لإعادة التشغيل من نفس
    // النقطة بدل البدء من الصفر.
    if (_position > Duration.zero) {
      _pendingRetryPosition = _position;
    }

    if (isCodecRelated) {
      final nextIndex = _sortedQualities.indexWhere((q) {
        final qNum = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final curNum = int.tryParse(
              _currentQuality.replaceAll(RegExp(r'[^0-9]'), ''),
            ) ??
            0;
        return qNum < curNum;
      });

      if (nextIndex != -1) {
        final fallbackQuality = _sortedQualities[nextIndex];
        final fallbackUrl = _streamsMap[fallbackQuality];

        if (fallbackUrl != null) {
          FirebaseCrashlytics.instance.log(
            '🔄 Codec error on $_currentQuality → auto-fallback to $fallbackQuality',
          );
          setState(() {
            _currentQuality = fallbackQuality;
            _currentQualityIndex = nextIndex;
          });
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (mounted && !_isDisposing) {
              try {
                // ✅ [إصلاح] نحدّث روابط البث الموقّعة أولاً (get-video-id)
                // قبل التبديل للجودة الأدنى — فلو كان سبب فشل الكوديك
                // الحقيقي (أو الفشل الذي سيصادفنا حالاً عند هذه الجودة
                // الأدنى تحديدًا) هو انتهاء صلاحية التوقيع بدل الكوديك فعلاً،
                // فإن استخدام نفس الروابط القديمة سيفشل مجددًا حتمًا. نتجاهل
                // بأمان أي فشل هنا ونكمل بالرابط القديم الموجود أصلاً في
                // _streamsMap تمامًا كالسابق — لا يوجد أي تراجع في السلوك.
                await _refreshStreamUrlsIfPossible();
                if (!mounted || _isDisposing) return;
                final refreshedFallbackUrl =
                    _streamsMap[fallbackQuality] ?? fallbackUrl;

                // ✅ لازم await هنا: setResolution داخليًا async وتستكمل عملها
                // بعد أول await داخلي (إعادة تهيئة الفيديو)، فإن أي استثناء
                // يُرمى في تلك النقطة (مثلاً null-check على متحكم تمت
                // إزالته أثناء إغلاق الشاشة) لا يصل إطلاقًا إلى الـ catch
                // هنا إن لم ننتظر (await) النتيجة — بل يتحول إلى
                // Unhandled Future rejection قاتل يصل لـ Crashlytics مباشرة.
                await _betterPlayerController?.setResolution(refreshedFallbackUrl);
                if (mounted && !_isDisposing) {
                  _reapplySpeedAfterSourceChange();
                }
              } catch (e) {
                FirebaseCrashlytics.instance.recordError(e, null,
                    reason: 'Native Player setResolution fallback error');
              }
            }
          });
          return;
        }
      }

      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage =
              'جهازك لا يدعم فك ترميز هذه الجودة. جرّب اختيار جودة أقل من أيقونة ⚙️ أعلى الشاشة.';
          _isInitializing = false;
        });
      }
      return;
    }

    // ✅ [إصلاح] كل خطأ غير متعلق بالكوديك — سواء طابق نمط شبكة معروف
    // (_isNetworkError) أو كان رسالة ExoPlayer/AVPlayer غامضة لا تطابق أي
    // نمط معروف (مثل "ExoPlaybackException: Source error" التي رصدناها في
    // Crashlytics ولا تحوي أي كلمة من قائمة _isNetworkError) — كان يُعامَل
    // سابقًا بشكل مختلف تمامًا: النمط المعروف فقط هو ما يمرّ عبر
    // _classifyAndHandleNetworkOrServerError (فحص اتصال حقيقي + إعادة محاولة
    // تلقائية بتأخير متزايد مع تحديث رابط البث)، بينما الرسالة غير المعروفة
    // كانت تعرض رسالة ثابتة واحدة وتتوقف تمامًا — تاركة إعادة تحديث رابط
    // البث (get-video-id) رهينة ضغطة يدوية واحدة فقط من المستخدم، بلا أي
    // إعادة محاولة تلقائية ولا أي ضمان لتكرارها لاحقًا.
    //
    // بما أن أخطاء تشغيل Bunny/ExoPlayer الفعلية (بما فيها "Source error"
    // العامة) غالبًا ما تكون بسبب رابط منتهي الصلاحية أو عطل خادم/CDN مؤقت —
    // تمامًا كأخطاء الشبكة المعروفة — فإننا الآن نمرّر كل الأخطاء غير
    // الكوديكية عبر نفس المسار الموحّد (_classifyAndHandleNetworkOrServerError)
    // بصرف النظر عن تطابق نص الرسالة مع نمط شبكة معروف أم لا. هذا يضمن:
    //   • فحص اتصال حقيقي دائمًا (رسالة واضحة لو الجهاز فعلاً بلا إنترنت).
    //   • إعادة محاولة تلقائية بتأخير متزايد (حتى _maxAutoRetries) لأي خطأ
    //     تشغيل آخر أثناء وجود اتصال — وكل محاولة منها تمرّ عبر
    //     _retryCurrentQuality الذي يستدعي get-video-id لتحديث الرابط قبل
    //     إعادة الإنشاء، بدل الاعتماد على ضغطة يدوية واحدة فقط.
    final looksLikeNetworkError = _isNetworkError(errorDescription);
    unawaited(_classifyAndHandleNetworkOrServerError(
      isKnownNetworkPattern: looksLikeNetworkError,
    ));
  }

  /// Handles the "not a codec error" case for *any* non-codec playback
  /// failure — both messages that matched a known network-failure pattern
  /// ([isKnownNetworkPattern] = true) and ones that didn't (e.g. the generic
  /// `ExoPlaybackException: Source error` ExoPlayer sometimes throws with no
  /// further detail). Both are handled identically from here on: uses
  /// connectivity_plus to distinguish "the device is actually offline" (show
  /// a clear message, no point auto-retrying) from "the device has internet
  /// but the stream/server request still failed" (very likely a transient
  /// Bunny CDN/server hiccup, or an expired signed URL — show a
  /// "retrying..." message and auto-retry a few times with increasing
  /// backoff, refreshing the signed stream URL via get-video-id on every
  /// attempt through [_retryCurrentQuality], before falling back to asking
  /// the user to retry manually).
  Future<void> _classifyAndHandleNetworkOrServerError({
    bool isKnownNetworkPattern = true,
  }) async {
    if (!mounted || _isDisposing) return;

    final hasInternet = await _hasInternetConnection();
    if (!mounted || _isDisposing) return;

    if (!hasInternet) {
      _autoRetryTimer?.cancel();
      _autoRetryAttempt = 0;
      setState(() {
        _isError = true;
        _errorMessage = 'لا يوجد اتصال بالإنترنت. تحقق من اتصالك وحاول مرة أخرى.';
        _isInitializing = false;
      });
      return;
    }

    if (_autoRetryAttempt < _maxAutoRetries) {
      final attempt = _autoRetryAttempt + 1;
      _autoRetryAttempt = attempt;
      final delay = Duration(seconds: 2 * attempt); // 2s, 4s, 6s

      setState(() {
        _isError = true;
        _errorMessage = 'حدث خطأ في الخادم، جارٍ إعادة المحاولة... ($attempt/$_maxAutoRetries)';
        _isInitializing = false;
      });

      FirebaseCrashlytics.instance.log(
        '🔁 Native Player auto-retry $attempt/$_maxAutoRetries scheduled in ${delay.inSeconds}s '
        '(${isKnownNetworkPattern ? "network-pattern error" : "unclassified playback error"}, has connectivity)',
      );

      _autoRetryTimer?.cancel();
      _autoRetryTimer = Timer(delay, () {
        if (!mounted || _isDisposing) return;
        // ✅ [إصلاح] _retryCurrentQuality يستدعي get-video-id دائمًا (عبر
        // _refreshStreamUrlsIfPossible) قبل إعادة إنشاء المشغّل — الآن هذا
        // ينطبق على كل إعادة محاولة تلقائية هنا، بغض النظر عن كون الخطأ
        // الأصلي طابق نمط شبكة معروف أم كان رسالة ExoPlayer غامضة.
        _retryCurrentQuality();
      });
    } else {
      _autoRetryTimer?.cancel();
      setState(() {
        _isError = true;
        _errorMessage = 'تعذر تشغيل الفيديو حالياً. تحقق من اتصالك وحاول مرة أخرى لاحقاً.';
        _isInitializing = false;
      });
    }
  }

  /// Best-effort connectivity check via connectivity_plus. If the check
  /// itself throws for any reason, we assume connectivity is fine rather
  /// than blocking retry logic on an unreliable signal.
  Future<bool> _hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.isNotEmpty && !results.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> _switchQuality(String quality) async {
    if (quality == _currentQuality || !_streamsMap.containsKey(quality)) {
      return;
    }
    final newIndex = _sortedQualities.indexOf(quality);
    setState(() {
      _currentQuality = quality;
      if (newIndex != -1) _currentQualityIndex = newIndex;
    });
    try {
      // ✅ await ضروري: بدونه أي استثناء يُرمى بعد أول نقطة انتظار داخلية
      // في setResolution (مثلاً إذا أُغلقت الشاشة أو تمت إزالة الـ
      // controller أثناء تبديل الجودة) يتحول إلى Unhandled Future
      // rejection قاتل ولا يصل إلى الـ catch أدناه إطلاقًا.
      await _betterPlayerController?.setResolution(_streamsMap[quality]!);
      if (mounted && !_isDisposing) {
        _reapplySpeedAfterSourceChange();
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Native Player setResolution Error');
      if (mounted && !_isDisposing) {
        _handlePlayerError(e.toString(), isCodecRelated: _isCodecError(e));
      }
    }
  }

  /// Resumes at the exact position/speed/play-state handed off from the
  /// floating (PiP) player, the first time the video initializes.
  void _applyHandoffStateIfNeeded() {
    if (_handoffApplied || !mounted || _isDisposing) return;
    _handoffApplied = true;

    final pos = widget.initialPosition;
    final speed = widget.initialSpeed;

    if (pos != null && pos > Duration.zero) {
      try {
        _betterPlayerController?.seekTo(pos);
      } catch (_) {}
    }
    if (speed != null && speed != 1.0) {
      // A short delay avoids the seek/speed calls racing the player's own
      // startup on some devices.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted || _isDisposing) return;
        try {
          _betterPlayerController?.setSpeed(speed);
        } catch (_) {}
      });
    }
    if (!widget.initialAutoPlay) {
      try {
        _betterPlayerController?.pause();
      } catch (_) {}
    }
  }

  /// Resumes at the position saved in [_pendingRetryPosition] the first time
  /// the (freshly re-created) player initializes after the user pressed
  /// "retry" in [_retryCurrentQuality]. No-op if there was no pending retry.
  void _applyRetryStateIfNeeded() {
    final pos = _pendingRetryPosition;
    if (pos == null || !mounted || _isDisposing) return;
    // نمسح القيمة فورًا حتى لا تُطبَّق مرة أخرى بالخطأ في تهيئات لاحقة
    // (مثلاً عند تبديل الجودة يدويًا بعد نجاح إعادة المحاولة).
    _pendingRetryPosition = null;
    if (pos <= Duration.zero) return;

    // ✅ إصلاح: لو فشل التشغيل مرة أخرى مباشرة عند (تقريبًا) نفس النقطة التي
    // أعدنا الالتصاق بها في آخر محاولة (_lastRetrySeekTarget)، فإن العودة
    // لنفس تلك النقطة بالضبط مرة أخرى سيعيد على الأرجح نفس الخطأ فورًا
    // (لحظة تالفة في الملف أو حد جزء منتهي الصلاحية عند خادم Bunny تحديدًا
    // عند هذا الـ offset) — فيدخل المستخدم في حلقة "إعادة محاولة ⇽⇾ نفس
    // الخطأ" بلا أي تقدّم فعلي. نتراجع ثانيتين إضافيتين في هذه الحالة
    // تحديدًا بدل الإعادة للنقطة نفسها بالضبط.
    Duration seekTarget = pos;
    final lastTarget = _lastRetrySeekTarget;
    if (lastTarget != null &&
        (pos - lastTarget).abs() <= const Duration(milliseconds: 1500)) {
      final nudged = pos - const Duration(seconds: 2);
      seekTarget = nudged.isNegative ? Duration.zero : nudged;
      FirebaseCrashlytics.instance.log(
        '↩️ Native Player retry landed on same failed position ($pos) — nudging back to $seekTarget',
      );
    }
    _lastRetrySeekTarget = seekTarget;

    try {
      _betterPlayerController?.seekTo(seekTarget);
    } catch (_) {}

    if (_currentSpeed != 1.0) {
      // نفس التأخير القصير المستخدم في handoff، لتجنب تسابق seek/setSpeed مع
      // بدء تشغيل المشغّل نفسه على بعض الأجهزة.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted || _isDisposing) return;
        try {
          _betterPlayerController?.setSpeed(_currentSpeed);
        } catch (_) {}
      });
    }
  }

  void _reapplySpeedAfterSourceChange() {
    if (_currentSpeed == 1.0) return;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _isDisposing) return;
      try {
        _betterPlayerController?.setSpeed(_currentSpeed);
      } catch (_) {}
    });
  }

  void _cycleVideoFit() {
    setState(() {
      _fitIndex = (_fitIndex + 1) % _fitCycle.length;
      _videoFit = _fitCycle[_fitIndex];
    });

    // ✅ إصلاح: أيقونة تغيير أبعاد الفيديو توقفت عن العمل.
    //
    // السبب: _videoFit كان يُمرَّر إلى BetterPlayerConfiguration.fit مرة
    // واحدة فقط عند إنشاء الـ controller في _initializePlayer(). تغييره هنا
    // كان يُحدّث حقل الحالة المحلي فقط ويستدعي setState() الخاص بهذه
    // الشاشة — لكن هذا لا يجعل حزمة better_player_plus تعيد رسم الفيديو
    // بأبعاد جديدة، لأن الحزمة لا "ترى" هذا الحقل إطلاقًا؛ هي تقرأ fit مرة
    // واحدة من التهيئة الأصلية عند الإنشاء ولا تُعيد قراءته بعد ذلك. التعليق
    // القديم أشار إلى وجود "FittedBox" يلتقط BoxFit بشكل تفاعلي، لكن لا يوجد
    // مثل هذا الغلاف في الشجرة — BetterPlayer(controller: ...) هو نقطة
    // الرسم الوحيدة، وليس هناك أي widget آخر يعتمد على _videoFit.
    //
    // الحل: استدعاء BetterPlayerController.setOverriddenFit() الذي توفره
    // الحزمة تحديدًا لهذا الغرض — تغيير أبعاد الفيديو أثناء التشغيل دون
    // إعادة إنشاء الـ controller بالكامل. هذا يعمل على أندرويد (حيث يُطبَّق
    // عبر Flutter مباشرة) وعلى iOS ستبقى الحاجة أيضًا لتحديث الـ
    // videoGravity الأصلي بشكل منفصل كما كان (انظر _applyIOSVideoGravity)
    // لأن AVPlayerLayer يُقصّ/يُحجّم الإطار أصليًا قبل وصوله لِـ Flutter.
    try {
      _betterPlayerController?.setOverriddenFit(_videoFit);
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player setOverriddenFit Error');
    }

    _forceApplyIOSVideoGravity();
  }

  /// Mirrors the current [_videoFit] selection to iOS's native AVPlayerLayer
  /// videoGravity via the platform channel exposed on VideoPlayerController.
  /// Safe to call on any platform — the underlying call is a no-op on Android.
  void _applyIOSVideoGravity() {
    if (!Platform.isIOS) return;
    final vpc = _betterPlayerController?.videoPlayerController;
    if (vpc == null) return;
    // Maps our fit cycle to better_player_plus's iOS gravity strings:
    // 'aspect'  -> AVLayerVideoGravityResizeAspect     (letterboxed, like BoxFit.contain)
    // 'stretch' -> AVLayerVideoGravityResize           (non-uniform stretch, like BoxFit.fill)
    // 'fill'    -> AVLayerVideoGravityResizeAspectFill (crop to fill, closest to BoxFit.fitWidth)
    final String gravity;
    switch (_videoFit) {
      case BoxFit.fill:
        gravity = 'stretch';
        break;
      case BoxFit.fitWidth:
        gravity = 'fill';
        break;
      case BoxFit.contain:
      default:
        gravity = 'aspect';
        break;
    }
    try {
      vpc.setAspectRatio(gravity);
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(
        e,
        null,
        reason: 'Native Player iOS setAspectRatio Error',
      );
    }
  }

  /// Re-applies [_applyIOSVideoGravity] several times over the next
  /// ~1.5 seconds instead of just once.
  ///
  /// better_player_plus is pinned to 1.2.1 here (see comment at the call
  /// site), a version where a single call right after the "initialized"
  /// event can lose a timing race with the native AVPlayerLayer's own
  /// setup and silently fail to letterbox the video. Firing the same
  /// cheap, idempotent call again on the next frame and a few more times
  /// shortly after guarantees the *last* attempt lands after the native
  /// player view genuinely exists, on every device, without needing to
  /// know exactly when that happens.
  void _forceApplyIOSVideoGravity() {
    if (!Platform.isIOS) return;
    _applyIOSVideoGravity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposing) return;
      _applyIOSVideoGravity();
    });
    for (final delay in const [
      Duration(milliseconds: 150),
      Duration(milliseconds: 400),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1500),
    ]) {
      Future.delayed(delay, () {
        if (!mounted || _isDisposing) return;
        _applyIOSVideoGravity();
      });
    }
  }

  void _onHoldStart() {
    if (_betterPlayerController == null || _isDisposing) return;
    _speedBeforeHold = _currentSpeed;
    _isHolding2x = true;
    try {
      _betterPlayerController?.setSpeed(2.0);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _onHoldEnd() {
    if (!_isHolding2x) return;
    _isHolding2x = false;
    try {
      _betterPlayerController?.setSpeed(_speedBeforeHold);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _setSpeed(double speed) {
    setState(() => _currentSpeed = speed);
    try {
      _betterPlayerController?.setSpeed(speed);
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player setSpeed Error');
    }
  }

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final maxSheetHeight = MediaQuery.of(sheetContext).size.height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _speedOptions.length,
                    itemBuilder: (context, index) {
                      final speed = _speedOptions[index];
                      final selected = speed == _currentSpeed;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                          color: selected ? AppColors.accentYellow : Colors.white54,
                        ),
                        title: Text(
                          speed == 1.0 ? 'عادي (×1)' : '×${speed.toString()}',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _setSpeed(speed);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleDoubleTapSeek({required bool forward}) {
    if (_betterPlayerController == null || _isDisposing) return;

    final videoValue = _betterPlayerController!.videoPlayerController?.value;
    final currentPosition = videoValue?.position ?? Duration.zero;
    final duration = videoValue?.duration ?? Duration.zero;
    const stepSeconds = 10;

    final isNewBurst = _pendingSeekDelta == 0 ||
        (forward && _pendingSeekDelta < 0) ||
        (!forward && _pendingSeekDelta > 0);

    if (isNewBurst) {
      _seekBaseline = currentPosition;
      _pendingSeekDelta = forward ? stepSeconds : -stepSeconds;
    } else {
      _pendingSeekDelta += forward ? stepSeconds : -stepSeconds;
    }

    var target = _seekBaseline + Duration(seconds: _pendingSeekDelta);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    try {
      _betterPlayerController?.seekTo(target);
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player Double-Tap Seek Error');
    }

    _seekIndicatorTimer?.cancel();
    setState(() {
      _showSeekIndicator = true;
      _seekIndicatorIsForward = forward;
    });
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _showSeekIndicator = false;
        _pendingSeekDelta = 0;
      });
    });
  }

  Future<void> _retryCurrentQuality() async {
    if (!mounted || _isDisposing) return;
    if (_currentQuality.isEmpty) return;

    // ✅ إصلاح: زر "إعادة المحاولة" كان يتوقف عن العمل بعد أول محاولة فاشلة
    // بسبب انقطاع الشبكة — حتى بعد عودة الإنترنت فعليًا.
    //
    // السبب: كنا نعتمد على retryDataSource() المدمجة في better_player_plus،
    // والتي تعيد استخدام نفس الـ BetterPlayerController/ExoPlayer (أندرويد)
    // أو AVPlayer (iOS) الأصلي بدل إنشاء واحد جديد بالكامل. عندما يفشل أول
    // اتصال فعليًا بسبب انقطاع الشبكة (لا مجرد تقطّع لحظي)، يبقى المشغّل
    // الأصلي أحيانًا عالقًا في حالة داخلية معطوبة بعد تلك المحاولة — فحتى
    // مع عودة الإنترنت، استدعاء retryDataSource() مجددًا على نفس الكائن لا
    // يُطلق محاولة اتصال جديدة فعليًا (لا حدث "initialized" ولا حتى حدث
    // "exception" جديد يصل لاحقًا)، فيبقى الـ Future المنتظر بلا استجابة
    // ويظل زر إعادة المحاولة بلا أي أثر ملحوظ للمستخدم.
    //
    // ✅ [جديد] إضافةً لذلك، إعادة المحاولة كانت تعيد استخدام نفس روابط
    // widget.streams الأصلية دائمًا — وهي روابط Bunny **موقّعة ومحدودة
    // الصلاحية زمنيًا**. لو كان سبب الفشل الفعلي هو انتهاء صلاحية التوقيع
    // (شائع لو ظل المستخدم على الشاشة لفترة طويلة أو كان الجهاز نائمًا)،
    // فإن إعادة المحاولة بنفس الرابط المنتهي كانت ستفشل مجددًا حتمًا مهما
    // أعاد المستخدم الضغط. الحل: قبل إعادة إنشاء المشغّل، نحاول أولاً جلب
    // مجموعة روابط بث جديدة وموقّعة حديثًا لنفس الفصل عبر
    // _refreshStreamUrlsIfPossible() (تتطلب widget.lessonId؛ إن لم يتوفر،
    // أو فشل الجلب لأي سبب، نكمل بأمان بنفس الروابط القديمة الموجودة في
    // _streamsMap تمامًا كالسابق — لا يوجد أي تراجع في السلوك).
    setState(() {
      _isError = false;
      _isInitializing = true;
    });

    await _refreshStreamUrlsIfPossible();
    if (!mounted || _isDisposing) return;

    if (_streamsMap[_currentQuality] == null) {
      // لا يوجد أي رابط صالح لهذه الجودة حتى بعد محاولة تحديث الروابط.
      setState(() {
        _isError = true;
        _errorMessage = 'تعذر العثور على رابط بث صالح لهذا الفيديو.';
        _isInitializing = false;
      });
      return;
    }

    try {
      final oldController = _betterPlayerController;
      // نزيل الـ controller القديم من الحالة فورًا حتى لا يحاول أي كود آخر
      // (مثل مستمعي الفيديو) استخدامه أثناء عملية التخلص منه أدناه.
      _betterPlayerController = null;
      oldController?.removeEventsListener(_onPlayerEvent);
      oldController?.videoPlayerController
          ?.removeListener(_onVideoValueChanged);
      oldController?.dispose(forceDispose: true);
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, null,
          reason: 'Native Player Retry Dispose Error');
    }

    if (!mounted || _isDisposing) return;

    // _initializePlayer() ينشئ BetterPlayerController جديدًا تمامًا بنفس
    // الجودة الحالية (_currentQuality) — والآن بالرابط الجديد إن نجح
    // التحديث أعلاه — وسيستكمل حالة _isInitializing/_isError تلقائيًا لاحقًا
    // عبر أحداث "initialized"/"exception" في _onPlayerEvent — تمامًا كما
    // يحدث في التهيئة الأولى للشاشة.
    _initializePlayer();
  }

  /// Re-fetches fresh, newly-signed stream URLs for the current lesson from
  /// `/api/secure/get-video-id` (the same endpoint used when the video was
  /// first opened — see chapter_contents_screen.dart._fetchAndPlayVideo) and
  /// merges them into [_streamsMap], preserving [_currentQuality] where
  /// possible. Silently does nothing if [NativeVideoPlayerScreen.lessonId]
  /// wasn't provided, or if the request fails for any reason — in both
  /// cases [_retryCurrentQuality] simply falls back to retrying with
  /// whatever URLs are already in [_streamsMap], same as before this fix.
  Future<void> _refreshStreamUrlsIfPossible() async {
    final lessonId = widget.lessonId;
    if (lessonId == null || lessonId.isEmpty) return;

    try {
      final res = await ApiClient.instance.get(
        '${ApiConstants.baseUrl}/api/secure/get-video-id',
        queryParameters: {'lessonId': lessonId},
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );

      if (res.statusCode != 200) return;
      final data = res.data;

      final Map<String, String> freshQualities = {};
      if (data['availableQualities'] != null) {
        for (final q in (data['availableQualities'] as List)) {
          if (q['url'] != null && q['quality'] != null) {
            freshQualities["${q['quality']}p"] = q['url'].toString();
          }
        }
      }
      if (freshQualities.isEmpty && data['url'] != null) {
        freshQualities['Auto'] = data['url'].toString();
      }

      if (freshQualities.isEmpty || !mounted || _isDisposing) return;

      setState(() {
        _streamsMap = freshQualities;
        _sortedQualities = _streamsMap.keys.toList();
        _sortedQualities.sort((a, b) {
          final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return numB.compareTo(numA);
        });
        if (_streamsMap.containsKey(_currentQuality)) {
          _currentQualityIndex = _sortedQualities.indexOf(_currentQuality);
        } else if (_sortedQualities.isNotEmpty) {
          // الجودة الحالية لم تعد متوفرة في الاستجابة الجديدة (نادر جدًا) —
          // نختار أقرب جودة متاحة بدلاً من ترك الشاشة بلا رابط صالح.
          _currentQualityIndex =
              _currentQualityIndex.clamp(0, _sortedQualities.length - 1);
          _currentQuality = _sortedQualities[_currentQualityIndex];
        }
      });

      FirebaseCrashlytics.instance.log(
        '🔄 Native Player retry: refreshed stream URLs for lesson $lessonId (${freshQualities.length} qualities)',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'Native Player Refresh Stream URL Error');
      // نتجاهل الفشل بصمت ونكمل بمحاولة إعادة الاتصال بنفس الروابط القديمة
      // الموجودة أصلاً في _streamsMap — أفضل من عدم فعل أي شيء إطلاقًا.
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final maxSheetHeight = MediaQuery.of(sheetContext).size.height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sortedQualities.length,
                    itemBuilder: (context, index) {
                      final q = _sortedQualities[index];
                      final selected = q == _currentQuality;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                          color: selected ? AppColors.accentYellow : Colors.white54,
                        ),
                        title: Text(q, style: TextStyle(color: AppColors.textPrimary)),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _switchQuality(q);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _retryCurrentQuality,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentYellow,
                foregroundColor: Colors.black,
              ),
              child: const Text("إعادة المحاولة"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetSystemChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    // ✅ استعادة كل الاتجاهات (وليس البورتريه فقط) حتى يتمكن المستخدم من
    // تدوير الجهاز بحرية أثناء استخدام النافذة العائمة، بدلاً من تثبيت
    // الشاشة على الوضع الرأسي فقط.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;
    _isDisposing = true;
    if (mounted) setState(() {});

    try {
      _betterPlayerController?.videoPlayerController?.removeListener(_onVideoValueChanged);
      _controlsAutoHideTimer?.cancel();
      _watermarkTimer?.cancel();
      _seekIndicatorTimer?.cancel();
      _autoRetryTimer?.cancel();
      await _recordingSubscription?.cancel();

      final controllerToDispose = _betterPlayerController;
      _betterPlayerController = null;
      controllerToDispose?.dispose(forceDispose: true);

      await WakelockPlus.disable();
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player Exit Error');
    }

    // ✅ إصلاح (iPhone 11 تحديدًا): النافذة العائمة لا تظهر أثناء انتقال
    // إغلاق الشاشة، وتظهر فقط عند إعادة فتح المشغل.
    //
    // السبب: _resetSystemChrome() كانت تُستدعى هنا بـ await قبل nav.pop()
    // مباشرة. هي بدورها تستدعي SystemChrome.setPreferredOrientations
    // لفتح كل الاتجاهات من جديد — وهذا استدعاء أصلي (native) حقيقي عبر
    // الـ platform channel. على iOS تحديدًا، تغيير قناع الاتجاهات
    // المسموحة يجبر UIKit على إعادة استعلام supportedInterfaceOrientations
    // وقد يُطلق تمريرة إعادة تخطيط (relayout) أصلية على الـ
    // UIViewController المضيف لمحرك Flutter. بما أننا كنا ننتظر (await)
    // اكتمال هذه الرحلة الأصلية *قبل* استدعاء nav.pop()، كان الإطار الذي
    // يُفترض أن يُظهر النافذة العائمة تحت حركة الإغلاق (transition) يتزامن
    // أحيانًا مع هذه العملية الأصلية ويُبتلع، خصوصاً على جهاز أبطأ مثل
    // iPhone 11 (شريحة A13 أقدم مقارنة بالأجهزة الأحدث). لا يوجد مكافئ لهذا
    // على أندرويد، ما يفسّر سبب عمل أندرويد بشكل صحيح دائمًا.
    //
    // الحل: نفّذ nav.pop() فورًا أولاً حتى لا يتنافس مع أي رحلة أصلية، ثم
    // أعد ضبط اتجاهات النظام (والتي لا تحتاج أن تحدث فورًا) بعد ذلك دون
    // انتظارها (fire-and-forget) حتى لا تحجب أي شيء آخر.

    // ✅ نستخدم navigatorKey العام بدلاً من الـ context المحلي للشاشة.
    // السبب: عند تفعيل الفيديو العائم، يتم إدراج FloatingVideoOverlay في
    // Stack عالمي فوق الـ MaterialApp.builder (انظر app.dart)، وهذا قد
    // يترافق مع rebuild لأعلى الشجرة في نفس لحظة إغلاق هذه الشاشة.
    // الاعتماد على context محلي هنا هو ما يسبب خطأ:
    // "Navigator operation requested with a context that does not include
    // a Navigator". navigatorKey.currentState يشير دائمًا مباشرة إلى
    // الـ NavigatorState الجذري المرفق بـ MaterialApp بغض النظر عن حالة أي
    // شجرة فرعية أخرى — نفس النمط المستخدم في
    // FloatingVideoOverlay._expandToFullScreen().
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (mounted && Navigator.of(context).canPop()) {
      // احتياط إضافي نادر إن كان الـ context المحلي هو المتاح فعلاً
      Navigator.of(context).pop();
    }

    // لا ننتظر (no await): لا يجوز لهذا الاستدعاء الأصلي أن يحجب أو
    // يتزامن مع حركة إغلاق الشاشة التي بدأت للتو أعلاه.
    unawaited(_resetSystemChrome());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isDisposing = true;
    
    _betterPlayerController?.videoPlayerController?.removeListener(_onVideoValueChanged);
    _controlsAutoHideTimer?.cancel();
    _watermarkTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _autoRetryTimer?.cancel();
    _recordingSubscription?.cancel();
    _protectionService.stopMonitoring();
    
    final c = _betterPlayerController;
    _betterPlayerController = null;
    c?.dispose(forceDispose: true);
    
    WakelockPlus.disable();
    _resetSystemChrome();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _safeExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_isRecordingDetected)
                _buildSecurityAlert()
              else if (_isError)
                _buildErrorWidget(_errorMessage)
              else if (_isInitializing || _betterPlayerController == null)
                Center(
                  child: CircularProgressIndicator(color: AppColors.accentYellow),
                )
              else
                Positioned.fill(
                  child: BetterPlayer(controller: _betterPlayerController!),
                ),

              // ── Gesture layer ──────────────────────────────────────────
              if (!_isRecordingDetected &&
                  !_isError &&
                  !_isInitializing &&
                  _betterPlayerController != null)
                Positioned.fill(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        // ── Left zone ──────────────────────────────────
                        Expanded(
                          flex: 3,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            onDoubleTap: () => _handleDoubleTapSeek(forward: false),
                            onLongPressStart: (_) => _onHoldStart(),
                            onLongPressEnd: (_) => _onHoldEnd(),
                            onLongPressCancel: _onHoldEnd,
                          ),
                        ),
                        // ── Centre zone ────────────────────────────────
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                          ),
                        ),
                        // ── Right zone ─────────────────────────────────
                        Expanded(
                          flex: 3,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            onDoubleTap: () => _handleDoubleTapSeek(forward: true),
                            onLongPressStart: (_) => _onHoldStart(),
                            onLongPressEnd: (_) => _onHoldEnd(),
                            onLongPressCancel: _onHoldEnd,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              
              // ── Custom Controls Stack ────────────────────────────────────────
              if (!_isRecordingDetected && !_isError && !_isInitializing && _betterPlayerController != null)
                IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Stack(
                      children: [
                        // زر التشغيل والإيقاف في المنتصف
                        Center(
                          child: IconButton(
                            iconSize: 56,
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: AppColors.accentYellow, // 👈 تعديل اللون للأصفر
                              shadows: const [
                                // 👈 إضافة ظل داكن لضمان الوضوح التام على الخلفية البيضاء
                                Shadow(color: Colors.black87, blurRadius: 12),
                              ],
                            ),
                            onPressed: _togglePlayPause,
                          ),
                        ),
                        
                        // الشريط السفلي
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 8,
                          child: SafeArea(
                            child: Container(
                              // 👈 خلفية شبه شفافة تحمي الشريط بالكامل من التداخل مع الفيديو الأبيض
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55), 
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // ✅ نجبر اتجاه هذا الشريط على LTR دائمًا. الـ Slider في فلاتر
                              // يقرأ Directionality.of(context) ليقرر اتجاه الزيادة، فإذا كان
                              // التطبيق بالعربية (RTL) ينعكس اتجاه شريط التقديم تلقائيًا
                              // (اليسار = تقديم بدل الترجيع). شريط تشغيل الفيديو يجب أن يبقى
                              // بنفس الاتجاه دائمًا (يسار = بداية) بغض النظر عن لغة الواجهة،
                              // تمامًا مثل منطقة اللمس للتقديم/الترجيع أعلاه.
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Row(
                                  children: [
                                    Text(
                                      _formatDuration(_position),
                                      // 👈 جعل وقت الفيديو باللون الأصفر
                                      style: TextStyle(color: AppColors.accentYellow, fontSize: 12, decoration: TextDecoration.none),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2.5,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        ),
                                        child: Slider(
                                          value: _position.inMilliseconds
                                              .clamp(0, _videoDuration.inMilliseconds == 0 ? 1 : _videoDuration.inMilliseconds)
                                              .toDouble(),
                                          min: 0,
                                          max: (_videoDuration.inMilliseconds == 0 ? 1 : _videoDuration.inMilliseconds).toDouble(),
                                          activeColor: AppColors.accentYellow,
                                          inactiveColor: Colors.white54,
                                          onChangeStart: _onSeekStart,
                                          onChanged: _onSeekChanged,
                                          onChangeEnd: _onSeekEnd,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(_videoDuration),
                                      // 👈 جعل وقت الفيديو الكلي باللون الأصفر
                                      style: TextStyle(color: AppColors.accentYellow, fontSize: 12, decoration: TextDecoration.none),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── ×2 speed indicator ────────────────────────────────────
              if (_isHolding2x)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fast_forward, color: AppColors.accentYellow, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '×2',
                              style: TextStyle(
                                color: AppColors.accentYellow,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Seek indicator ────────────────────────────────────────
              if (_showSeekIndicator)
                Align(
                  alignment: _seekIndicatorIsForward
                      ? const Alignment(0.85, 0)
                      : const Alignment(-0.85, 0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _showSeekIndicator ? 0.95 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _seekIndicatorIsForward
                                    ? Icons.fast_forward
                                    : Icons.fast_rewind,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_pendingSeekDelta.abs()} ث',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Top bar: back + title + fit + speed + quality + PIP ─────────
              if (!_isRecordingDetected && !_isDisposing)
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: SafeArea(
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: _safeExit,
                            ),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.none,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!_isError && _betterPlayerController != null) ...[
                              IconButton(
                                icon: Icon(
                                  _fitIndex == 0
                                      ? Icons.crop_16_9
                                      : _fitIndex == 1
                                          ? Icons.fit_screen
                                          : Icons.width_full,
                                  color: AppColors.accentYellow,
                                ),
                                onPressed: _cycleVideoFit,
                                tooltip: _fitLabels[_fitIndex],
                              ),
                              IconButton(
                                icon: Icon(Icons.speed, color: AppColors.accentYellow),
                                onPressed: _showSpeedSheet,
                                tooltip: '×$_currentSpeed',
                              ),
                            ],
                            if (_sortedQualities.length > 1 && !_isError)
                              IconButton(
                                icon: Icon(LucideIcons.settings, color: AppColors.accentYellow),
                                onPressed: _showQualitySheet,
                                tooltip: _currentQuality,
                              ),
                            
                            // ── PIP (Floating Video) Button ──
                            if (!_isError && _betterPlayerController != null)
                              IconButton(
                                icon: Icon(Icons.picture_in_picture_alt, color: AppColors.accentYellow),
                                tooltip: 'تشغيل كنافذة عائمة',
                                onPressed: () async {
                                  // 1. التقاط حالة التشغيل الحالية (الموضع/السرعة/الجودة)
                                  //    حتى يستأنف المشغل العائم من نفس النقطة تمامًا.
                                  //    (يجب التقاطها قبل استدعاء _safeExit لأنها
                                  //    ستُصفّر _betterPlayerController).
                                  final currentPosition =
                                      _betterPlayerController
                                              ?.videoPlayerController
                                              ?.value
                                              .position ??
                                          _position;
                                  final wasPlaying = _betterPlayerController
                                          ?.isPlaying() ??
                                      _isPlaying;
                                  final streams = _streamsMap;
                                  final title = widget.title;
                                  final watermarkText = _watermarkText;
                                  final speed = _currentSpeed;
                                  final quality = _currentQuality;
                                  final lessonId = widget.lessonId;

                                  // 2. ✅ فعّل وضع الفيديو العائم أولاً — قبل إغلاق هذه
                                  //    الشاشة، وليس بعده. هذا الاستدعاء لا يفعل أكثر من
                                  //    قلب علم isFloating و notifyListeners()، فيُدرج
                                  //    ListenableBuilder في app.dart النافذة العائمة فورًا
                                  //    في نفس الإطار — بشكل مستقل تمامًا عن أي انتقال
                                  //    (transition) جارٍ حالياً في الـ Navigator الرئيسي.
                                  //
                                  //    ⚠️ سابقًا كنا نستدعي هذا *بعد* _safeExit() + تأخير
                                  //    ثابت 150ms، على افتراض أن كل الأجهزة تُنهي حركة
                                  //    الـ pop وتحرير الـ decoder خلال تلك المدة. على بعض
                                  //    أجهزة iOS الأبطأ (أو تحت Low Power Mode / حرارة
                                  //    مرتفعة) لم تكن 150ms كافية، فكان استدعاء
                                  //    startFloating() يحدث بينما شجرة الودجت العليا لا تزال
                                  //    في خضم معاملة بناء لأجل انتقال الشاشة السابقة —
                                  //    فتُدرَج الـ OverlayEntry دون أن تُرسم فعليًا حتى يأتي
                                  //    إطار إضافي (وهو ما كان يفسّر ظهورها فجأة بعد إعادة
                                  //    فتح المشغل، لأن ذلك يفرض إعادة بناء كاملة).
                                  //    بتقديم هذا الاستدعاء قبل أي إغلاق أو تأخير، تصبح
                                  //    النافذة العائمة مستقلة تمامًا عن سرعة أي جهاز.
                                  FloatingVideoController.instance.startFloating(
                                    streams: streams,
                                    title: title,
                                    watermarkText: watermarkText,
                                    initialPosition: currentPosition,
                                    playbackSpeed: speed,
                                    initialQuality: quality,
                                    wasPlaying: wasPlaying,
                                    lessonId: lessonId,
                                  );

                                  // 3. الآن أغلق المشغل الحالي وحرر الـ decoder/Surface
                                  //    الخاص به. النافذة العائمة الجديدة تنشئ الآن (انظر
                                  //    FloatingVideoOverlay._initPlayer) الـ
                                  //    BetterPlayerController الفعلي الخاص بها بعد تأخير
                                  //    داخلي قصير خاص بها هي — لا علاقة له بظهور الودجت
                                  //    نفسه — وهو ما يحفظ نفس الحماية الأصلية ضد تزاحم
                                  //    فك التشفير (decoder contention) دون المخاطرة بعدم
                                  //    ظهور النافذة العائمة إطلاقًا على بعض الأجهزة.
                                  await _safeExit();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Watermark ─────────────────────────────────────────────
              if (!_isDisposing && !_isError && !_isInitializing)
                AnimatedAlign(
                  alignment: _watermarkAlignment,
                  duration: const Duration(seconds: 2),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _watermarkText,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityAlert() {
    return Container(
      color: Colors.red.shade900,
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.block, color: Colors.white, size: 80),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)?.securityAlertTitle ?? 'SECURITY ALERT',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.screenRecordingDetectedMessage ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _safeExit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(
              AppLocalizations.of(context)?.closePlayer ?? 'Close',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
