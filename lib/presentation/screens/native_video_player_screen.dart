import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// ✅ مكتبات الحماية (نفس المكتبات المستخدمة في المشغل الأساسي)
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import '../../core/services/audio_protection_service.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';

// ===========================================================================
// ✅ [NATIVE PLAYER] مشغل بديل لا يعتمد على media_kit
// ---------------------------------------------------------------------------
// يستخدم حزمة better_player_plus (المبنية فوق video_player الرسمية / ExoPlayer
// على أندرويد و AVPlayer على آيفون) بدلاً من مكتبة media_kit (المبنية على
// libmpv). تدعم better_player_plus روابط MPEG-TS HLS بشكل كامل، وتوفر تبديل
// جودة أصلي (native resolution switching) يحافظ على موضع التشغيل تلقائياً
// دون الحاجة لإعادة بناء المشغل بالكامل في كل مرة.
// الهدف: توفير خيار تشغيل بديل للأجهزة التي تواجه مشاكل في فك التشفير أو
// الاستقرار مع media_kit (شاشة سوداء، تهنيج، تعطل...)، دون التأثير على
// المشغلات الحالية.
//
// يستقبل نفس شكل البيانات الذي يستقبله VideoPlayerScreen: خريطة
// {"360p": "https://...m3u8", "720p": "https://...m3u8", ...} القادمة من
// get-video-id (engine: "bunny_native" في إعدادات المشغلات بالباك إند).
// ===========================================================================

class NativeVideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
  final String title;

  const NativeVideoPlayerScreen({
    super.key,
    required this.streams,
    required this.title,
  });

  @override
  State<NativeVideoPlayerScreen> createState() =>
      _NativeVideoPlayerScreenState();
}

class _NativeVideoPlayerScreenState extends State<NativeVideoPlayerScreen>
    with WidgetsBindingObserver {
  BetterPlayerController? _betterPlayerController;

  // ✅ خدمة الحماية (كشف تسجيل الشاشة) - نفس الخدمة المستخدمة في المشغل الأساسي
  final AudioProtectionService _protectionService = AudioProtectionService();
  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;

  String _currentQuality = "";
  List<String> _sortedQualities = [];

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitializing = true;
  bool _isDisposing = false;

  // ✅ نتذكر فهرس الجودة الحالية في القائمة المرتبة حتى نستطيع
  // الانتقال تلقائياً للجودة الأقل عند خطأ فك ترميز MediaCodec
  int _currentQualityIndex = 0;

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  // ✅ سرعة التشغيل — من 0.25× إلى 2×
  double _currentSpeed = 1.0;
  static const List<double> _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  // ✅ حالة التقديم/الترجيع التراكمي بالدبل تاب (double-tap) — كل نقرتين
  // متتاليتين على نفس الجهة تضيف 10 ثواني فوق سابقتها بدل عمل seek منفصل
  // في كل مرة، ويظهر مؤشر بصري بالمجموع الكلي (مثل يوتيوب).
  int _pendingSeekDelta = 0; // موجب = تقديم، سالب = ترجيع
  Duration _seekBaseline = Duration.zero;
  Timer? _seekIndicatorTimer;
  bool _showSeekIndicator = false;
  bool _seekIndicatorIsForward = true;

  // ✅ Video fit/size mode: fill (fullscreen crop), contain (16:9 letterbox), cover with black sides
  BoxFit _videoFit = BoxFit.contain; // default: 16:9 with black sides
  static const List<BoxFit> _fitCycle = [BoxFit.contain, BoxFit.fill, BoxFit.fitWidth];
  static const List<String> _fitLabels = ['16:9', 'Full', 'Wide'];
  int _fitIndex = 0;

  // ✅ Hold-to-2× speed: track long-press state
  bool _isHolding2x = false;
  double _speedBeforeHold = 1.0;

  final Map<String, String> _headers = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sortQualities();
    _loadUserData();
    _initializeProtection();
    _setupScreen();
  }

  // ---------------------------------------------------------------------
  // تهيئة أولية
  // ---------------------------------------------------------------------

  void _sortQualities() {
    _sortedQualities = widget.streams.keys.toList();
    // ✅ نرتب من الأعلى جودةً للأقل حتى يظهر للمستخدم الأعلى جودةً أولاً في
    // قائمة الاختيار، لكن عند بدء التشغيل نبدأ من منتصف القائمة (جودة متوسطة)
    // لتجنب خطأ MediaCodecVideoRenderer على الأجهزة الضعيفة بالجودة العالية.
    _sortedQualities.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return numB.compareTo(numA); // من الأعلى جودة للأقل: [720p, 480p, 360p, 240p]
    });
    if (_sortedQualities.isNotEmpty) {
      // ✅ أولوية اختيار الجودة الافتراضية: 360p ثم 480p ثم 240p ثم 720p.
      // نجرب كل جودة بالترتيب ونختار أول واحدة موجودة فعلياً في الستريمز.
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
      // لو مفيش أي من الجودات دي متاحة، ارجع لمنطق منتصف القائمة كاحتياطي آمن
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
      // ✅ FIX: Re-apply FLAG_SECURE every time the screen comes back to foreground.
      // Without this, returning from PiP, external app, or system overlay can
      // drop the secure flag and expose the video in the task switcher.
      FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE)
          .catchError((_) {});
      _protectionService.blockAudioCapture();
      if (_isRecordingDetected) {
        _betterPlayerController?.setVolume(0.0);
        _betterPlayerController?.pause();
      }
    }
  }

  void _loadUserData() {
    String displayText = '';
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] ?? '';
    }
    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          var box = Hive.box('auth_box');
          displayText = box.get('phone') ?? box.get('username') ?? '';
        }
      } catch (_) {}
    }
    _watermarkText = displayText.isNotEmpty
        ? displayText
        : (AppState().userData?['username'] ?? 'Unknown User');
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

      if (_currentQuality.isEmpty || widget.streams[_currentQuality] == null) {
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

  // ---------------------------------------------------------------------
  // تهيئة المشغل (مرة واحدة فقط) وتبديل الجودة عبر setResolution
  // ---------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // هل الخطأ ناتج عن MediaCodec (مشكلة فك ترميز hardware)؟
  // ExoPlaybackException مع "MediaCodecVideoRenderer" أو "video/mp2t"
  // يعني الجهاز لا يستطيع فك تشفير هذه الجودة — نحاول جودة أقل.
  // -----------------------------------------------------------------------
  bool _isCodecError(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('mediacodec') ||
        msg.contains('exoplaybackexception') ||
        msg.contains('video/mp2t') ||
        msg.contains('videorenderer') ||
        msg.contains('codecexception') ||
        msg.contains('mediacodecvideorenderererror');
  }

  // -----------------------------------------------------------------------
  // ينشئ BetterPlayerController مرة واحدة، ويمرر كل الجودات كـ resolutions
  // حتى يستطيع المشغل التبديل بينها داخلياً (setResolution) مع الحفاظ على
  // موضع التشغيل الحالي تلقائياً، دون الحاجة لإعادة بناء المشغل بالكامل.
  // -----------------------------------------------------------------------
  void _initializePlayer() {
    if (!mounted || _isDisposing) return;

    final initialUrl = widget.streams[_currentQuality]!;

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      initialUrl,
      headers: _headers,
      // ✅ formatHint: hls — ضروري لروابط Bunny المُوقَّعة التي لا تنتهي
      // بـ .m3u8 بشكل صريح بسبب query params الطويلة.
      videoFormat: BetterPlayerVideoFormat.hls,
      // ✅ نمرر كل الجودات المتاحة حتى يدعم المشغل التبديل الأصلي بينها
      resolutions: widget.streams,
      cacheConfiguration: const BetterPlayerCacheConfiguration(useCache: false),
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
    );

    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        looping: false,
        // ✅ الشاشة نفسها بتشتغل بملء الشاشة (اتجاه أفقي مثبّت + immersive)
        // فمفيش داعي لفل سكرين خاص بالمشغل نفسه
        fullScreenByDefault: false,
        allowedScreenSleep: true, // بنتحكم في الـ Wakelock يدوياً بالفعل
        autoDetectFullscreenDeviceOrientation: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableFullscreen: false,
          enablePip: false,
          enableQualities: false, // بنستخدم قائمة الجودة المخصصة في الشريط العلوي
          enableSubtitles: false,
          enableAudioTracks: false,
          enableSkips: false, // ✅ removed default 10s skip buttons — double-tap handles seeking
          enableMute: true,
          // ✅ بنستخدم قائمة السرعة المخصصة في الشريط العلوي (0.25× إلى 2×)
          // بدل القائمة الداخلية المحدودة في المكتبة
          enablePlaybackSpeed: false,
          loadingColor: AppColors.accentYellow,
          progressBarPlayedColor: AppColors.accentYellow,
          progressBarHandleColor: AppColors.accentYellow,
          progressBarBufferedColor: Colors.white24,
          progressBarBackgroundColor: Colors.white10,
        ),
        errorBuilder: (context, errorMessage) {
          // ✅ بنتعامل مع الأخطاء بنفس الـ overlay المخصص عبر مستمع الأحداث
          // بدل الاعتماد على واجهة الخطأ الداخلية للمكتبة
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
        final errMsg = (event.parameters?['exception'] ??
                event.parameters?['error'] ??
                'Unknown player exception')
            .toString();
        FirebaseCrashlytics.instance.log(
          '⚠️ Native Player (better_player) exception: $errMsg (quality: $_currentQuality)',
        );
        _handlePlayerError(errMsg, isCodecRelated: _isCodecError(errMsg));
        break;
      case BetterPlayerEventType.initialized:
        if (_isError) {
          setState(() {
            _isError = false;
          });
        }
        break;
      default:
        break;
    }
  }

  // -----------------------------------------------------------------------
  // معالجة الخطأ: إذا كان خطأ codec نحاول الجودة التالية الأقل تلقائياً
  // عبر setResolution، وإذا لم يكن أو نفدت الخيارات نعرض رسالة خطأ واضحة.
  // -----------------------------------------------------------------------
  void _handlePlayerError(String errorDescription, {required bool isCodecRelated}) {
    if (!mounted || _isDisposing) return;

    if (isCodecRelated) {
      // ابحث عن الجودة التالية الأقل في القائمة المرتبة (الفهرس الأكبر = جودة أقل)
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
        final fallbackUrl = widget.streams[fallbackQuality];

        if (fallbackUrl != null) {
          FirebaseCrashlytics.instance.log(
            '🔄 Codec error on $_currentQuality → auto-fallback to $fallbackQuality',
          );
          setState(() {
            _currentQuality = fallbackQuality;
            _currentQualityIndex = nextIndex;
          });
          // إعادة المحاولة بالجودة الأقل بعد تأخير قصير
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDisposing) {
              try {
                _betterPlayerController?.setResolution(fallbackUrl);
                _reapplySpeedAfterSourceChange();
              } catch (e) {
                FirebaseCrashlytics.instance.recordError(e, null,
                    reason: 'Native Player setResolution fallback error');
              }
            }
          });
          return;
        }
      }

      // نفدت الجودات الأقل → أخبر المستخدم بالتبديل يدوياً
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage =
              'جهازك لا يدعم فك ترميز هذه الجودة. جرّب اختيار جودة أقل من أيقونة ⚙️ أعلى الشاشة.';
          _isInitializing = false;
        });
      }
    } else {
      // خطأ شبكة أو خطأ غير معروف
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage =
              'تعذر تشغيل الفيديو. تحقق من اتصال الإنترنت وأعد المحاولة.';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _switchQuality(String quality) async {
    if (quality == _currentQuality || !widget.streams.containsKey(quality)) {
      return;
    }
    final newIndex = _sortedQualities.indexOf(quality);
    setState(() {
      _currentQuality = quality;
      if (newIndex != -1) _currentQualityIndex = newIndex;
    });
    try {
      // ✅ setResolution بيحافظ على موضع التشغيل وحالة التشغيل تلقائياً
      _betterPlayerController?.setResolution(widget.streams[quality]!);
      _reapplySpeedAfterSourceChange();
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Native Player setResolution Error');
      _handlePlayerError(e.toString(), isCodecRelated: _isCodecError(e));
    }
  }

  // -----------------------------------------------------------------------
  // ✅ setResolution بينشئ مصدر فيديو جديد داخلياً فبيرجع السرعة لـ 1× تلقائياً؛
  // فلو المستخدم كان مختار سرعة مختلفة عن الافتراضي، نعيد تطبيقها بعد قصير
  // من تبديل الجودة حتى يكتمل تحميل المصدر الجديد.
  // -----------------------------------------------------------------------
  void _reapplySpeedAfterSourceChange() {
    if (_currentSpeed == 1.0) return;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _isDisposing) return;
      try {
        _betterPlayerController?.setSpeed(_currentSpeed);
      } catch (_) {}
    });
  }

  // -----------------------------------------------------------------------
  // ✅ دورة أحجام الفيديو: 16:9 (contain) → Full (fill) → Wide (fitWidth)
  // -----------------------------------------------------------------------
  void _cycleVideoFit() {
    setState(() {
      _fitIndex = (_fitIndex + 1) % _fitCycle.length;
      _videoFit = _fitCycle[_fitIndex];
    });
  }

  // -----------------------------------------------------------------------
  // ✅ الضغط المطوّل = 2× سرعة مؤقتة؛ رفع الإصبع يعيد السرعة السابقة
  // -----------------------------------------------------------------------
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

  // -----------------------------------------------------------------------
  // ✅ سرعة التشغيل
  // -----------------------------------------------------------------------
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

  // -----------------------------------------------------------------------
  // ✅ التقديم/الترجيع التراكمي بالدبل تاب: نقرتان متتاليتان على يمين
  // الشاشة تقدّم 10 ثواني، وأي نقرتين إضافيتين خلال نفس السلسلة (قبل
  // انتهاء المؤقّت) يضيفوا 10 ثواني تانية فوق نفس نقطة البداية بدل عمل
  // seek منفصل غير مستقر في كل مرة — مطابق لسلوك يوتيوب.
  // -----------------------------------------------------------------------
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
      // بداية سلسلة جديدة أو تغيير الاتجاه: خد الموضع الحالي كنقطة انطلاق
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

  void _retryCurrentQuality() {
    if (_currentQuality.isNotEmpty && widget.streams[_currentQuality] != null) {
      setState(() {
        _isError = false;
      });
      try {
        _betterPlayerController?.retryDataSource();
      } catch (_) {
        try {
          _betterPlayerController?.setResolution(widget.streams[_currentQuality]!);
        } catch (e) {
          FirebaseCrashlytics.instance
              .recordError(e, null, reason: 'Native Player Retry Error');
        }
      }
    }
  }

  // -----------------------------------------------------------------------
  // ✅ قائمة اختيار الجودة — bottom sheet قابل للتمرير (ListView) داخل حاوية
  // بارتفاع محدود (isScrollControlled + ConstrainedBox) بدل Column غير قابل
  // للتمرير. هذا يمنع مشكلة "pixels overflowed" التي كانت تظهر في الوضع
  // الأفقي (landscape) حين يكون ارتفاع الشاشة صغيراً وعدد الجودات كبيراً.
  // -----------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // الخروج والتنظيف
  // ---------------------------------------------------------------------

  Future<void> _resetSystemChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;
    // ✅ نضع _isDisposing = true أولاً قبل أي await لمنع listeners من إطلاق
    // callbacks على متحكمات يتم التخلص منها (مصدر "[Player] has been disposed")
    _isDisposing = true;
    if (mounted) setState(() {});

    try {
      _watermarkTimer?.cancel();
      _seekIndicatorTimer?.cancel();
      await _recordingSubscription?.cancel();

      // ✅ نأخذ مرجعاً محلياً ونُفرغ المتغير الأصلي قبل dispose()
      // حتى لو أُطلق listener أثناء dispose لن يجد شيئاً يستدعيه
      final controllerToDispose = _betterPlayerController;
      _betterPlayerController = null;
      controllerToDispose?.dispose(forceDispose: true);

      await WakelockPlus.disable();
      // ✅ FIX FLAG_SECURE: explicitly clear the flag before popping.
      // This guarantees the parent screen's FLAG_SECURE state (set via
      // FlutterWindowManagerPlus in its own initState) is respected —
      // the native window manager merges flags per-window, so clearing
      // here allows the parent to control its own secure state cleanly.
      try {
        await FlutterWindowManagerPlus.clearFlags(
            FlutterWindowManagerPlus.FLAG_SECURE);
      } catch (_) {}
      await _resetSystemChrome();
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player Exit Error');
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isDisposing = true;
    _watermarkTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _recordingSubscription?.cancel();
    // ✅ نفس النهج: نُفرغ المتغير أولاً ثم نستدعي dispose
    final c = _betterPlayerController;
    _betterPlayerController = null;
    c?.dispose(forceDispose: true);
    WakelockPlus.disable();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // البناء
  // ---------------------------------------------------------------------

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
                // ✅ removed "videoReadyStabilizing" text — show spinner only
                Center(
                  child: CircularProgressIndicator(color: AppColors.accentYellow),
                )
              else
                // ✅ AspectRatio wrapper to support fit modes (16:9, Full, Wide)
                Positioned.fill(
                  child: FittedBox(
                    fit: _videoFit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      // Use 16:9 reference size; ExoPlayer/AVPlayer handles actual ratio internally
                      width: MediaQuery.of(context).size.longestSide,
                      height: MediaQuery.of(context).size.longestSide * 9 / 16,
                      child: BetterPlayer(controller: _betterPlayerController!),
                    ),
                  ),
                ),

              // ── مناطق الدبل تاب + الضغط المطوّل (يمين/يسار) ──────────
              // ✅ RTL FIX: wrap in LTR Directionality so the physical left half
              // is always rewind and physical right half is always forward,
              // regardless of whether the app locale is Arabic (RTL) or English (LTR).
              // Without this, Flutter's Row reverses child order in RTL mode,
              // making the Arabic user tap right to rewind and left to forward —
              // the opposite of every video player convention.
              if (!_isRecordingDetected &&
                  !_isError &&
                  !_isInitializing &&
                  _betterPlayerController != null)
                Positioned.fill(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        // Physical left zone → rewind (same in Arabic & English)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onDoubleTap: () => _handleDoubleTapSeek(forward: false),
                            onLongPressStart: (_) => _onHoldStart(),
                            onLongPressEnd: (_) => _onHoldEnd(),
                            onLongPressCancel: _onHoldEnd,
                          ),
                        ),
                        // Physical right zone → forward (same in Arabic & English)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
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

              // ── مؤشر الضغط المطوّل 2× ──────────────────────────────────
              if (_isHolding2x)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.fast_forward, color: Colors.white, size: 22),
                            SizedBox(width: 6),
                            Text(
                              '×2',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── مؤشر التقديم/الترجيع التراكمي ──────────────────────────
              // ✅ RTL FIX: use absolute Alignment(x, 0) instead of
              // Alignment.centerRight/Left — the named alignments are
              // direction-aware and would flip in Arabic, showing the
              // forward indicator on the left and rewind on the right.
              if (_showSeekIndicator)
                Align(
                  alignment: _seekIndicatorIsForward
                      ? const Alignment(0.85, 0)
                      : const Alignment(-0.85, 0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _showSeekIndicator ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _seekIndicatorIsForward
                                    ? Icons.fast_forward
                                    : Icons.fast_rewind,
                                color: Colors.white,
                                size: 28,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_pendingSeekDelta.abs()} ث',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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

              // ── شريط علوي: رجوع + عنوان + زر السرعة + زر الجودة ──────
              if (!_isRecordingDetected && !_isDisposing)
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: SafeArea(
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
                          // ✅ Video size / fit mode toggle button
                          IconButton(
                            icon: Icon(
                              _fitIndex == 0
                                  ? Icons.crop_16_9
                                  : _fitIndex == 1
                                      ? Icons.fit_screen
                                      : Icons.width_full,
                              color: Colors.white,
                            ),
                            onPressed: _cycleVideoFit,
                            tooltip: _fitLabels[_fitIndex],
                          ),
                          IconButton(
                            icon: const Icon(Icons.speed, color: Colors.white),
                            onPressed: _showSpeedSheet,
                            tooltip: '×$_currentSpeed',
                          ),
                        ],
                        if (_sortedQualities.length > 1 && !_isError)
                          IconButton(
                            icon: const Icon(LucideIcons.settings, color: Colors.white),
                            onPressed: _showQualitySheet,
                            tooltip: _currentQuality,
                          ),
                      ],
                    ),
                  ),
                ),

              // ── العلامة المائية ────────────────────────────────────────
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
