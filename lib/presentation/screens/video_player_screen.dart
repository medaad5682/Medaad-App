import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
// ✅ مكتبات الحماية
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import '../../core/services/audio_protection_service.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../core/services/app_state.dart';
import '../../core/services/local_proxy.dart';
import '../../core/services/video_screenshot_service.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
import 'package:Medaad/presentation/widgets/safe_seek_bar.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
  final String title;
  final String? preReadyAudioUrl;

  /// Lesson/video ID used to re-fetch a fresh signed stream URL from
  /// `/api/secure/get-video-id` when the user retries after a playback
  /// error. Optional so screens that don't have an ID handy (e.g. offline
  /// downloads, or the Explode direct-play path) still work — retry then
  /// simply reuses the original (possibly stale/expired) URLs, same as
  /// before this fix. Mirrors NativeVideoPlayerScreen.lessonId.
  final String? lessonId;

  const VideoPlayerScreen({
    super.key,
    required this.streams,
    required this.title,
    this.preReadyAudioUrl,
    this.lessonId,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final Player _player;
  // ── Fix: "[Player] has been disposed" assertion in NativePlayer.seek/play ──
  // هذه الاشتراكات (error/buffering/position) كانت تُنشأ بـ .listen(...) دون
  // حفظها، أي أنها تبقى فعّالة حتى بعد _player.dispose(). عند مغادرة
  // الشاشة، إن أطلق أي من هذه الـ streams حدثاً أخيراً أثناء stop()/dispose()
  // (وهو أمر شائع لهذه الأنواع من الـ streams)، كان الـ listener يستدعي
  // _player.seek()/play()/pause() على مشغّل تم التخلص منه بالفعل فيرمي هذا
  // الخطأ ويُسقط التطبيق. حفظ الاشتراكات هنا وإلغاؤها أولاً في _safeExit()
  // (قبل stop()/dispose()) يمنع وصول أي حدث متأخر لهذه الاستدعاءات إطلاقاً.
  StreamSubscription? _playerErrorSubscription;
  StreamSubscription? _playerBufferingSubscription;
  StreamSubscription? _playerPositionSubscription;
  late final VideoController _controller;

  final LocalProxyService _proxyService = LocalProxyService();

  // ✅ نسخة قابلة للتعديل من widget.streams. تبدأ بنفس القيم الممرَّرة من
  // الشاشة السابقة، لكن _refreshStreamUrlsIfPossible() (تُستدعى عند إعادة
  // المحاولة بعد خطأ) قد تستبدلها بروابط جديدة موقّعة حديثًا بدل الاعتماد
  // إلى الأبد على نفس الخريطة الأصلية التي قد تحتوي روابط منتهية الصلاحية.
  // نفس الفكرة المطبَّقة في NativeVideoPlayerScreen._streamsMap.
  late Map<String, String> _streamsMap;

  // ✅ خدمة الحماية الخاصة
  final AudioProtectionService _protectionService = AudioProtectionService();
  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;

  String _currentQuality = "";
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitialized = false;
  
  // ✅ متغير لحفظ مكان توقف الفيديو عند انقطاع الشبكة
  Duration _errorPosition = Duration.zero;

  // ✅ [RETRY-SEEK-FIX] آخر موضع تشغيل معروف — يُحدَّث باستمرار من مستمع
  // position أثناء التشغيل الطبيعي. عند وقوع خطأ شبكة، قد يُعيد MediaKit
  // _player.state.position إلى صفر قبل وصول callback الخطأ، لذا نحفظ
  // القيمة هنا بشكل مستقل حتى لا تضيع.
  Duration _lastKnownPosition = Duration.zero;

  bool _isVideoLoading = true;
  bool _isOfflineMode = false;

  // ✅ [QUALITY-SWITCH RESUME FIX] موضع الاستئناف المطلوب بعد فتح مصدر
  // جديد (مثلاً عند تغيير الجودة). لا نستدعي seek() مباشرة بعد open() لأن
  // مصدر الشبكة (خصوصاً قائمة HLS جديدة بالكامل عند تبديل الجودة) لا يملك
  // بعد نطاقاً قابلاً للـ seek عند تلك اللحظة، فتُتجاهل الحركة بصمت.
  // بدلاً من ذلك نخزّن الهدف هنا، وننفذ الـ seek فعلياً داخل مستمع
  // buffering أدناه بمجرد انتهاء التخزين المؤقت وقبل استئناف التشغيل.
  Duration? _pendingResumePosition;

  bool _isWeakDevice = false;

  int _stabilizingCountdown = 0;
  Timer? _countdownTimer;

  bool _isDisposing = false;

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  // ── ميزة "لقطة الفيديو" (Video Frame Screenshot) ──────────────────────
  // ✅ نفس آلية NativeVideoPlayerScreen: RepaintBoundary يلف الفيديو +
  // العلامة المائية، ثم تشفير فوري قبل أي كتابة على القرص.
  // ⚠️ ملاحظة: هنا يلف الـ RepaintBoundary أيضاً عناصر تحكم media_kit
  // الافتراضية (شريط التقدم/زر التشغيل) لأنها مرسومة داخل نفس شجرة
  // ودجت Video نفسها (على عكس NativeVideoPlayerScreen حيث الأزرار طبقة
  // منفصلة تماماً) — إن كانت هذه العناصر ظاهرة لحظة الالتقاط فستظهر في
  // اللقطة. عملياً تختفي تلقائياً بعد ثوانٍ من عدم التفاعل.
  final GlobalKey _screenshotBoundaryKey = GlobalKey();
  bool _isCapturingScreenshot = false;

  Timer? _seekDebounceTimer;
  Duration _accumulatedSeekAmount = Duration.zero;

  // ✅ [SEEK-LOCK] Replaces the AV-sync watchdog.
  // Every intentional seek increments this counter; the position listener
  // ignores transient backward jumps while it is > 0.
  int _seekLockCount = 0;
  Timer? _seekLockReleaseTimer;

  // ✅ [DOUBLE-TAP SEEK] متغيرات النقر المزدوج للتقديم/الرجوع
  int _leftTapCount = 0;
  int _rightTapCount = 0;
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  bool _showLeftTapOverlay = false;
  bool _showRightTapOverlay = false;

  // ✅ [LONG-PRESS SPEED] متغيرات الضغط المطوّل لتسريع ×2
  bool _isLongPressActive = false;

  // ✅ [TAP-INTERCEPT] مؤقت لاكتشاف ما إذا كانت النقرة جزءاً من نقر مزدوج
  Timer? _leftTapInhibitTimer;
  Timer? _rightTapInhibitTimer;
  int _leftRawTapCount = 0;
  int _rightRawTapCount = 0;

  // ✅ [RIPPLE ANIMATION] متحكمات الأنيميشن للدوائر المتموجة
  late AnimationController _leftRippleController;
  late AnimationController _rightRippleController;
  late Animation<double> _leftRippleAnim;
  late Animation<double> _rightRippleAnim;

  final Map<String, String> _serverHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)',
  };
  final Map<String, String> _youtubeHeaders = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ [RIPPLE] تهيئة متحكمات أنيميشن الدوائر المتموجة
    _leftRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _rightRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _leftRippleAnim = CurvedAnimation(
      parent: _leftRippleController,
      curve: Curves.easeOut,
    );
    _rightRippleAnim = CurvedAnimation(
      parent: _rightRippleController,
      curve: Curves.easeOut,
    );

    _initializeProtection();
    _initializePlayerScreen();
  }

  Future<void> _initializeProtection() async {
    try {
      await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);
      await _protectionService.blockAudioCapture();
      await _protectionService.startMonitoring();
      _recordingSubscription =
          _protectionService.recordingStateStream.listen((isRecording) {
        if (isRecording) {
          _handleRecordingDetected();
        }
      });
      debugPrint("🛡️ Protection Enabled in Video Player");
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Protection Init Error');
    }
  }

  void _handleRecordingDetected() {
    if (!mounted) return;
    setState(() => _isRecordingDetected = true);
    _player.setVolume(0.0);
    _player.pause();
    FirebaseCrashlytics.instance
        .log("🚨 Security: Screen Recording Detected! Player Muted & Paused.");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.pause();
    } else if (state == AppLifecycleState.resumed) {
      _protectionService.blockAudioCapture();
      if (_isRecordingDetected) {
        _player.setVolume(0.0);
        _player.pause();
      }
    }
  }

  Future<void> _initializePlayerScreen() async {
    _streamsMap = Map<String, String>.from(widget.streams);

    FirebaseCrashlytics.instance
        .log("🎬 MediaKit: Optimized Init for '${widget.title}'");
    await FirebaseCrashlytics.instance
        .setCustomKey('video_title', widget.title);

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await WakelockPlus.enable();
      await _startProxyServer();

      bool forceSoftwareDecoding = false;
      if (Platform.isAndroid) {
        try {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          if (androidInfo.version.sdkInt <= 28) {
            _isWeakDevice = true;
            forceSoftwareDecoding = true;
          }
        } catch (_) {
          _isWeakDevice = true;
          forceSoftwareDecoding = true;
        }
      }

      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: _isWeakDevice ? 8 * 1024 * 1024 : 32 * 1024 * 1024,
          vo: 'gpu',
        ),
      );

      if (forceSoftwareDecoding) {
        await (_player.platform as dynamic).setProperty('hwdec', 'no');
        await (_player.platform as dynamic).setProperty('vd-lavc-threads', '4');
        await (_player.platform as dynamic)
            .setProperty('sws-scaler', 'fast-bilinear');
        // ✅ [ROOT-FIX] For weak/offline devices: pre-buffer enough frames
        // before the first decode so the video decoder never falls behind
        // the audio track during the critical first ~60 seconds.
        await (_player.platform as dynamic).setProperty('cache-secs', '8');
        await (_player.platform as dynamic).setProperty('demuxer-readahead-secs', '8');
        // Keep video/audio tightly coupled; if video lags mpv drops frames
        // rather than letting the position pointer jump backward.
        await (_player.platform as dynamic).setProperty('video-sync', 'audio');
        await (_player.platform as dynamic).setProperty('framedrop', 'vo');
      } else {
        await (_player.platform as dynamic).setProperty('hwdec', 'auto');
        await (_player.platform as dynamic).setProperty('video-sync', 'audio');
        await (_player.platform as dynamic).setProperty('framedrop', 'vo');
      }

      await (_player.platform as dynamic)
          .setProperty('cache-pause-wait', '3');
      await (_player.platform as dynamic)
          .setProperty('audio-desync-correction', 'yes');

      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: !forceSoftwareDecoding,
          androidAttachSurfaceAfterVideoParameters: !_isWeakDevice,
        ),
      );

      _playerErrorSubscription = _player.stream.error.listen((error) {
        final errorString = error.toString().toLowerCase();

        // ✅ [CONSOLE-CLEANUP] Errors that are expected/transient on real
        // mobile networks (dropped wifi, weak signal, DNS blips, CDN
        // hiccups). These are handled gracefully in the UI below, so they
        // are NOT real crashes — logging them via recordError() just fills
        // the Crashlytics console with noise and can bury genuine bugs.
        final isTransientNetworkError = errorString.contains('tcp') ||
            errorString.contains('timeout') ||
            errorString.contains('ffurl_read') ||
            errorString.contains('resolve hostname') ||
            errorString.contains('route to host') ||
            errorString.contains('handshake') ||
            errorString.contains('connection terminated') ||
            errorString.contains('decoding audio');

        final isExpectedNonError = errorString.contains('failed to open');

        if (isTransientNetworkError) {
          if (mounted && !_isDisposing) {
            // ✅ [RETRY-SEEK-FIX] نستخدم _lastKnownPosition بدلاً من
            // _player.state.position لأن MediaKit قد يُصفّر الموضع
            // الداخلي قبل وصول هذا الـ callback عند انقطاع الشبكة.
            setState(() {
              _isError = true;
              _errorPosition = _lastKnownPosition;
              _errorMessage = AppLocalizations.of(context)!.networkConnectionProblemMessage;
              _isVideoLoading = false;
            });
            _player.pause();
          }
          // Breadcrumb only — shows up attached to any *later* fatal event
          // for context, but doesn't create its own console entry.
          FirebaseCrashlytics.instance
              .log('ℹ️ Transient network/stream error (handled): $error');
          return;
        }

        if (isExpectedNonError) {
          FirebaseCrashlytics.instance
              .log('ℹ️ Media "failed to open" (expected, handled): $error');
          return;
        }

        // Anything else is a genuinely unexpected player error — worth
        // keeping in Crashlytics so it's actually visible.
        FirebaseCrashlytics.instance
            .recordError(error, null, reason: 'MediaKit Stream Error', fatal: false);
      });

      _playerBufferingSubscription = _player.stream.buffering.listen((buffering) {
        if (!buffering && _isVideoLoading) {
          // ✅ Fix: نفس فحص _isDisposing المستخدم بالفعل في مستمع الأخطاء
          // أعلاه — mounted وحده لا يكفي لأن _isDisposing يُضبط بـ setState
          // في بداية _safeExit() بينما تبقى الشاشة mounted حتى Navigator.pop()
          // في النهاية، أي أن حدث buffering متأخر أثناء stop()/dispose() كان
          // يجتاز فحص mounted فقط ثم يستدعي seek()/play() على مشغّل يُتخلّص
          // منه في تلك اللحظة بالضبط.
          if (mounted && !_isDisposing) {
            setState(() => _isVideoLoading = false);
            if (_isRecordingDetected) {
              _player.setVolume(0.0);
              _player.pause();
              return;
            }
            // ✅ [QUALITY-SWITCH RESUME FIX] الآن — وليس فور open() — أصبح
            // للمصدر نطاق قابل للـ seek فعلياً، لذا ننفذ موضع الاستئناف
            // المخزّن هنا قبل استئناف التشغيل أو بدء العد التنازلي.
            final resumeAt = _pendingResumePosition;
            _pendingResumePosition = null;
            if (resumeAt != null && resumeAt != Duration.zero) {
              _acquireSeekLock(const Duration(seconds: 2));
              _player.seek(resumeAt);
            }
            if (_isOfflineMode) {
              _startCountdown();
            } else {
              _player.play();
            }
          }
        }
      });

      _playerPositionSubscription = _player.stream.position.listen((pos) {
        // ✅ [RETRY-SEEK-FIX] نحفظ آخر موضع حقيقي هنا باستمرار.
        // عند وقوع خطأ شبكة قد يُصفَّر _player.state.position قبل
        // وصول callback الخطأ، فنستخدم هذه القيمة بدلاً منه.
        if (pos > Duration.zero && !_isError) {
          _lastKnownPosition = pos;
        }
      });

      _loadUserData();
      _startWatermarkAnimation();

      if (mounted) {
        setState(() => _isInitialized = true);
        _parseQualities();
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: "Initialization Failed");
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = AppLocalizations.of(context)!.playerInitFailedMessage(e.toString());
          _isVideoLoading = false;
        });
      }
    }
  }

  Future<void> _startProxyServer() async {
    try {
      await _proxyService.start();
    } catch (e, s) {
      FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'Proxy Start Error');
    }
  }

  Future<void> _playVideo(String url, {Duration? startAt}) async {
    if (_isDisposing) return;

    // ✅ [QUALITY-SWITCH RESUME FIX] نخزّن الهدف هنا فقط. الـ seek الفعلي
    // يحدث لاحقًا داخل مستمع buffering أعلاه، بعد أن يصبح المصدر الجديد
    // قابلاً للـ seek فعلياً — انظر الشرح هناك.
    _pendingResumePosition =
        (startAt != null && startAt != Duration.zero) ? startAt : null;

    // ✅ [RETRY-SEEK-FIX] نصفّر آخر موضع معروف فقط عند بدء مصدر جديد من الصفر
    // (لا عند الاستئناف بعد خطأ شبكة) حتى لا تُلوَّث القيمة بموضع مصدر سابق.
    if (startAt == null || startAt == Duration.zero) {
      _lastKnownPosition = Duration.zero;
    }

    setState(() {
      _isVideoLoading = true;
      _stabilizingCountdown = 0;
    });
    _countdownTimer?.cancel();

    // ✅ [SEEK-LOCK] Acquire a lock so any position events during load
    // are ignored. Released automatically after playback is stable.
    _acquireSeekLock(const Duration(seconds: 4));

    try {
      String playUrl = url;
      String? audioUrl;

      _isOfflineMode = false;

      if (url.contains('|')) {
        final parts = url.split('|');
        playUrl = parts[0];
        if (parts.length > 1) audioUrl = parts[1];
      }

      if (!playUrl.startsWith('http')) {
        _isOfflineMode = true;
        final file = File(playUrl);
        if (!await file.exists()) throw Exception("Offline file missing");
        
        playUrl = _proxyService.getSignedUrl(file.path, isAudio: false);

        if (audioUrl == null && Hive.isBoxOpen('downloads_box')) {
          final box = Hive.box('downloads_box');
          try {
            final absoluteVideoPath = file.absolute.path;
            final downloadItem = box.values.firstWhere(
                (item) =>
                    item['path'] != null &&
                    File(item['path']).absolute.path == absoluteVideoPath,
                orElse: () => null);
            if (downloadItem != null && downloadItem['audioPath'] != null) {
              final audioPath = downloadItem['audioPath'];
              if (await File(audioPath).exists()) {
                audioUrl = _proxyService.getSignedUrl(audioPath, isAudio: true);
              }
            }
          } catch (_) {}
        }
      } else {
        if (audioUrl == null && widget.preReadyAudioUrl != null) {
          audioUrl = widget.preReadyAudioUrl;
        }
      }

      await _player.stop();

      final bool isYoutubeSource = playUrl.contains('googlevideo.com');
      final headers = isYoutubeSource ? _youtubeHeaders : _serverHeaders;

      await _player.open(Media(playUrl, httpHeaders: headers), play: false);

      if (_isRecordingDetected) {
        await _player.setVolume(0.0);
        return;
      }

      if (audioUrl != null) {
        // ✅ [ROOT-FIX] Wait for the demuxer to be ready before attaching the
        // external audio track. On weak devices the previous 2500 ms fixed
        // delay was not enough when the CPU was under load; we now wait for
        // the first buffering=false event (i.e. the player has received enough
        // data) instead, with a generous timeout fallback.
        if (_isWeakDevice) {
          final readyCompleter = Completer<void>();
          StreamSubscription? sub;
          final timeout = Timer(const Duration(seconds: 6), () {
            if (!readyCompleter.isCompleted) readyCompleter.complete();
          });
          sub = _player.stream.buffering.listen((buffering) {
            if (!buffering && !readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
          });
          await readyCompleter.future;
          timeout.cancel();
          await sub.cancel();
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        try {
          await _player.setAudioTrack(
              AudioTrack.uri(audioUrl, title: "HQ Audio", language: "en"));
        } catch (e) {
          await Future.delayed(const Duration(seconds: 2));
          try {
            await _player.setAudioTrack(
                AudioTrack.uri(audioUrl, title: "HQ Audio", language: "en"));
          } catch (_) {}
        }
      }

      // ✅ [QUALITY-SWITCH RESUME FIX] لا نستدعي seek() هنا بعد الآن — انظر
      // _pendingResumePosition ومستمع buffering أعلاه.

      if (_currentSpeed != 1.0) {
        await _player.setRate(_currentSpeed);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'PlayVideo Function Failed');
      if (mounted && !_isDisposing) {
        setState(() {
          _isError = true;
          _errorMessage = AppLocalizations.of(context)!.videoLoadFailedMessage;
          _isVideoLoading = false;
        });
      }
    }
  }

  /// Handles the "Retry" button after a playback error.
  ///
  /// ✅ [جديد] قبل الآن كانت إعادة المحاولة تعيد استخدام نفس رابط
  /// widget.streams الأصلي دائمًا — وهو رابط Bunny **موقّع ومحدود الصلاحية
  /// زمنيًا**. لو كان سبب الفشل الفعلي هو انتهاء صلاحية التوقيع (شائع لو ظل
  /// المستخدم على الشاشة لفترة طويلة أو كان الجهاز نائمًا)، فإن إعادة
  /// المحاولة بنفس الرابط المنتهي كانت ستفشل مجددًا حتمًا مهما أعاد المستخدم
  /// الضغط. الحل: قبل استدعاء _playVideo مجددًا، نحاول أولاً جلب رابط بث
  /// جديد وموقّع حديثًا لنفس الجودة عبر _refreshStreamUrlsIfPossible()
  /// (تتطلب widget.lessonId؛ إن لم يتوفر، أو فشل الجلب لأي سبب، نكمل بأمان
  /// بنفس الرابط القديم الموجود أصلاً في _streamsMap تمامًا كالسابق — لا
  /// يوجد أي تراجع في السلوك). نفس المنطق المطبَّق في
  /// NativeVideoPlayerScreen._retryCurrentQuality.
  Future<void> _retryPlayback() async {
    if (!mounted || _isDisposing) return;
    if (_currentQuality.isEmpty) return;

    setState(() => _isError = false);

    await _refreshStreamUrlsIfPossible();
    if (!mounted || _isDisposing) return;

    final url = _streamsMap[_currentQuality];
    if (url == null) {
      setState(() {
        _isError = true;
        _errorMessage = AppLocalizations.of(context)!.noSourcesAvailableMessage;
      });
      return;
    }

    _playVideo(url, startAt: _errorPosition);
  }

  /// Re-fetches fresh, newly-signed stream URLs for the current lesson from
  /// `/api/secure/get-video-id` (the same endpoint used when the video was
  /// first opened — see chapter_contents_screen.dart._fetchAndPlayVideo) and
  /// merges them into [_streamsMap], preserving [_currentQuality] where
  /// possible. Silently does nothing if [VideoPlayerScreen.lessonId] wasn't
  /// provided, or if the request fails for any reason — in both cases
  /// [_retryPlayback] simply falls back to retrying with whatever URL is
  /// already in [_streamsMap], same as before this fix.
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
          return numA.compareTo(numB);
        });
        if (!_streamsMap.containsKey(_currentQuality) &&
            _sortedQualities.isNotEmpty) {
          // الجودة الحالية لم تعد متوفرة في الاستجابة الجديدة (نادر جدًا) —
          // نختار أقرب جودة متاحة بدلاً من ترك الشاشة بلا رابط صالح.
          _currentQuality = _sortedQualities.last;
        }
      });

      FirebaseCrashlytics.instance.log(
        '🔄 MediaKit Player retry: refreshed stream URLs for lesson $lessonId (${freshQualities.length} qualities)',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'MediaKit Player Refresh Stream URL Error');
      // نتجاهل الفشل بصمت ونكمل بمحاولة إعادة الاتصال بنفس الرابط القديم
      // الموجود أصلاً في _streamsMap — أفضل من عدم فعل أي شيء إطلاقًا.
    }
  }

  Future<void> _seekRelative(Duration amount) async {
    if (_isRecordingDetected) return;

    _accumulatedSeekAmount += amount;
    if (_seekDebounceTimer?.isActive ?? false) _seekDebounceTimer!.cancel();

    // ✅ [SEEK-LOCK] Acquire lock before the debounce fires so any
    // AV-sync interruption that was pending is blocked.
    _acquireSeekLock(const Duration(seconds: 2));

    _seekDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final duration = _player.state.duration;
        if (duration == Duration.zero) return;

        final currentPos = _player.state.position;
        var targetPos = currentPos + _accumulatedSeekAmount;

        if (targetPos < Duration.zero) targetPos = Duration.zero;
        if (targetPos > duration) targetPos = duration;

        await _player.seek(targetPos);
      } catch (e) {
        FirebaseCrashlytics.instance.recordError(e, null, reason: 'Seek Error');
      } finally {
        _accumulatedSeekAmount = Duration.zero;
      }
    });
  }

  // ✅ [SEEK-LOCK] Increment the lock counter and schedule a release.
  // Multiple overlapping callers each get their own release timer so
  // the lock is only fully dropped when all of them have expired.
  void _acquireSeekLock(Duration holdFor) {
    _seekLockCount++;
    _seekLockReleaseTimer?.cancel();
    _seekLockReleaseTimer = Timer(holdFor, () {
      if (_seekLockCount > 0) _seekLockCount--;
    });
  }

  bool get _isSeekLocked => _seekLockCount > 0;

  void _onDoubleTapLeft() {
    if (_isRecordingDetected || _isDisposing || _isError) return;

    _leftTapCount++;
    _leftRippleController.forward(from: 0.0);

    if (mounted) setState(() => _showLeftTapOverlay = true);

    _leftTapTimer?.cancel();
    _leftTapTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final totalSeconds = _leftTapCount * 10;
      _seekRelative(Duration(seconds: -totalSeconds));
      setState(() {
        _showLeftTapOverlay = false;
        _leftTapCount = 0;
        _leftRawTapCount = 0;
      });
    });
  }

  void _onDoubleTapRight() {
    if (_isRecordingDetected || _isDisposing || _isError) return;

    _rightTapCount++;
    _rightRippleController.forward(from: 0.0);

    if (mounted) setState(() => _showRightTapOverlay = true);

    _rightTapTimer?.cancel();
    _rightTapTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final totalSeconds = _rightTapCount * 10;
      _seekRelative(Duration(seconds: totalSeconds));
      setState(() {
        _showRightTapOverlay = false;
        _rightTapCount = 0;
        _rightRawTapCount = 0;
      });
    });
  }

  void _onLongPressStart() {
    if (_isRecordingDetected || _isDisposing || _isError) return;
    if (mounted) setState(() => _isLongPressActive = true);
    _player.setRate(2.0);
  }

  void _onLongPressEnd() {
    if (_isDisposing) return;
    if (mounted) setState(() => _isLongPressActive = false);
    _player.setRate(_currentSpeed);
  }

  void _showSettingsSheet() {
    if (!mounted || _isRecordingDetected) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppLocalizations.of(context)!.settingsTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold))),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(LucideIcons.monitor, color: Colors.white),
              title: Text(AppLocalizations.of(context)!.qualityLabel(_currentQuality),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showQualitySelection();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.gauge, color: Colors.white),
              title: Text(AppLocalizations.of(context)!.speedLabel(_currentSpeed.toString()),
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showSpeedSelection();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQualitySelection() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _sortedQualities.reversed
              .map((q) => ListTile(
                    title: Text(q,
                        style: TextStyle(
                            color: q == _currentQuality
                                ? AppColors.accentYellow
                                : Colors.white)),
                    trailing: q == _currentQuality
                        ? Icon(LucideIcons.check, color: AppColors.accentYellow)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (q != _currentQuality) {
                        final currentPos = _player.state.position;
                        setState(() {
                          _currentQuality = q;
                          _isError = false;
                        });
                        _playVideo(_streamsMap[q]!, startAt: currentPos);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showSpeedSelection() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: speeds
              .map((s) => ListTile(
                    title: Text("${s}x",
                        style: TextStyle(
                            color: s == _currentSpeed
                                ? AppColors.accentYellow
                                : Colors.white)),
                    trailing: s == _currentSpeed
                        ? Icon(LucideIcons.check, color: AppColors.accentYellow)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _currentSpeed = s);
                      _player.setRate(s);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _startCountdown() {
    setState(() => _stabilizingCountdown = _isWeakDevice ? 6 : 10);
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposing) {
        timer.cancel();
        return;
      }

      if (_stabilizingCountdown <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _stabilizingCountdown = 0);
          if (!_isRecordingDetected) {
            _player.play();
          } else {
            _player.setVolume(0.0);
            _player.pause();
          }
        }
      } else {
        if (mounted) setState(() => _stabilizingCountdown--);
      }
    });
  }

  void _parseQualities() {
    if (_streamsMap.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = AppLocalizations.of(context)!.noSourcesAvailableMessage;
        _isVideoLoading = false;
      });
      return;
    }

    _sortedQualities = _streamsMap.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    if (_sortedQualities.contains("360p")) {
      _currentQuality = "360p";
    } else if (_sortedQualities.contains("480p")) {
      _currentQuality = "480p";
    } else if (_sortedQualities.contains("720p")) {
      _currentQuality = "720p";
    } else if (_sortedQualities.isNotEmpty) {
      _currentQuality = _sortedQualities.last;
    } else {
      _currentQuality = "";
    }

    if (_currentQuality.isNotEmpty) {
      _playVideo(_streamsMap[_currentQuality]!);
    }
  }

  void _loadUserData() {
    String displayText = '';
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] != null
          ? AppState().userData!['phone']
          : '';
    }
    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          var box = Hive.box('auth_box');
          displayText = box.get('phone') ?? box.get('username') ?? '';
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _watermarkText = displayText.isNotEmpty
            ? displayText
            : AppState().userData!['username'] ?? 'Unknown User';
      });
    }
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

  Future<void> _resetSystemChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    // ✅ استعادة كل الاتجاهات (رأسي وأفقي) بدلاً من تثبيت الشاشة على
    // الوضع الرأسي فقط عند الخروج من مشغل الفيديو.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await Future.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;

    if (mounted) setState(() => _isDisposing = true);

    try {
      // ✅ Fix: إلغاء اشتراكات الـ streams أولاً — قبل stop()/dispose() —
      // حتى لا يصل أي حدث متأخر منها لاستدعاء seek()/play()/pause() على
      // المشغّل أثناء أو بعد التخلص منه (راجع تعليق الحقول أعلاه).
      _playerErrorSubscription?.cancel();
      _playerBufferingSubscription?.cancel();
      _playerPositionSubscription?.cancel();
      _seekDebounceTimer?.cancel();
      _watermarkTimer?.cancel();
      _countdownTimer?.cancel();
      _seekLockReleaseTimer?.cancel();
      _leftTapTimer?.cancel();
      _rightTapTimer?.cancel();
      _leftTapInhibitTimer?.cancel();
      _rightTapInhibitTimer?.cancel();
      _leftRippleController.dispose();
      _rightRippleController.dispose();
      await _player.stop();
      await _player.dispose();
      await WakelockPlus.disable();
      await _resetSystemChrome();
    } catch (e) {
      debugPrint("⚠️ SafeExit Error: $e");
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingSubscription?.cancel();
    _protectionService.stopMonitoring();

    if (!_isDisposing) _safeExit();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: builds one symmetric seek overlay (left rewind / right forward)
  //
  // [isLeft]        true  → rewind chevrons pointing left
  //                 false → forward chevrons pointing right
  // [tapCount]      number of accumulated double-taps so far
  // [rippleAnim]    the Animation<double> for the expanding ripple ring
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSeekOverlay({
    required bool isLeft,
    required int tapCount,
    required Animation<double> rippleAnim,
  }) {
    // ── Icon choice ──────────────────────────────────────────────────────
    // Both sides use the same "double chevron" family so they are
    // mirror images of each other — not two completely different metaphors.
    final IconData seekIcon = isLeft
        ? Icons.keyboard_double_arrow_left_rounded
        : Icons.keyboard_double_arrow_right_rounded;

    // ── Gradient runs inward from the tapped edge → transparent centre ───
    final gradient = LinearGradient(
      begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        Colors.black.withOpacity(0.28),
        Colors.transparent,
      ],
    );

    // ── Rounded corner on the inward edge only ────────────────────────────
    final borderRadius = isLeft
        ? const BorderRadius.only(
            topRight: Radius.circular(999),
            bottomRight: Radius.circular(999),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(999),
            bottomLeft: Radius.circular(999),
          );

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 120),
        child: Stack(
          children: [
            // ── Background gradient ────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: borderRadius,
              ),
            ),

            // ── Expanding ripple ring ──────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: rippleAnim,
                builder: (_, __) {
                  final size = 72.0 + rippleAnim.value * 36.0;
                  return Opacity(
                    opacity: (1.0 - rippleAnim.value) * 0.35,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Main circle with icon + label ──────────────────────────
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.45),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Seek direction icon ──────────────────────────
                    Icon(seekIcon, color: Colors.white, size: 28),
                    const SizedBox(height: 2),
                    // ── Dynamic seconds label (10s, 20s, 30s …) ─────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween<double>(begin: 0.6, end: 1.0).animate(
                          CurvedAnimation(
                              parent: anim, curve: Curves.easeOutBack),
                        ),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        '${tapCount * 10}s',
                        key: ValueKey(tapCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// يلتقط الإطار الحالي للفيديو + العلامة المائية عبر RepaintBoundary
  /// ويحفظه مشفَّراً فوراً — لا بايتات صورة غير مشفّرة تُكتب على القرص
  /// في أي لحظة. راجع VideoScreenshotService.saveEncrypted والتعليق أعلى
  /// _screenshotBoundaryKey لملاحظة عناصر التحكم.
  Future<void> _captureCurrentFrame() async {
    if (_isCapturingScreenshot) return;
    if (_isError || !_isInitialized) return;

    setState(() => _isCapturingScreenshot = true);

    try {
      await Future.delayed(const Duration(milliseconds: 20));

      final boundary = _screenshotBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception("Screenshot boundary not found in render tree");
      }

      final dpr = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: dpr);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        throw Exception("Failed to encode captured frame to PNG");
      }

      final pngBytes = byteData.buffer.asUint8List();

      await VideoScreenshotService.saveEncrypted(
        pngBytes: pngBytes,
        lessonId: widget.lessonId ?? widget.title,
        videoTitle: widget.title,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.videoScreenshotSaved ??
                'Screenshot saved',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'VideoPlayerScreen._captureCurrentFrame failed',
        fatal: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.videoScreenshotFailed ??
                'Failed to save screenshot',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCapturingScreenshot = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewPadding;

    // ─────────────────────────────────────────────────────────────────────
    // Controls theme
    // • Seek buttons (replay_10 / forward_10) removed from primaryButtonBar.
    //   Seeking is now exclusively via left/right double-tap gestures.
    // • The progress bar + position indicator remain in the bottom bar.
    // ─────────────────────────────────────────────────────────────────────
    // ✅ [CRASH-FIX] `_player` is a `late final` field only assigned inside
    // the async `_initializePlayerScreen()` after several `await`s. Since
    // `initState()` doesn't await that method, the very first build() calls
    // can happen before `_player` exists. Building `controlsTheme` (which
    // reads `_player` via SafeSeekBar) unconditionally used to throw
    // LateInitializationError on those early frames. Guard it so we only
    // construct it once the player is actually ready.
    final controlsTheme = !_isInitialized
        ? null
        : MaterialVideoControlsThemeData(
      displaySeekBar: false,
      padding: EdgeInsets.only(
          top: padding.top > 0 ? padding.top : 20,
          bottom: padding.bottom > 0 ? padding.bottom : 20,
          left: 20,
          right: 20),
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const SizedBox(width: 10),
        // ✅ [CRASH-FIX] Replaced media_kit_video's MaterialSeekBar with
        // SafeSeekBar. The package widget's internal onPointerMove/onPointerUp
        // read State.context without a `mounted` check, which threw a FATAL
        // "Null check operator used on a null value" if the screen was
        // disposed mid-drag. SafeSeekBar guards every callback against
        // dispose/unmount and never touches context after a gesture.
        Expanded(
          child: SafeSeekBar(
            player: _player,
            onSeekStart: () => _acquireSeekLock(const Duration(seconds: 2)),
            onSeekEnd: (_) =>
                _acquireSeekLock(const Duration(milliseconds: 1500)),
            activeColor: AppColors.accentYellow,
            thumbColor: AppColors.accentYellow,
          ),
        ),
        const SizedBox(width: 10),
        MaterialCustomButton(
          // ✅ [BUILD-FIX] MaterialCustomButton.onPressed (media_kit_video) is
          // a non-nullable `void Function()`, unlike Flutter's IconButton —
          // it can't accept `null` to "disable" the button, and a bare async
          // tear-off (`Future<void> Function()`) inside a nullable ternary
          // doesn't satisfy it either. Re-entrance is already guarded inside
          // _captureCurrentFrame() itself, so just fire-and-forget it here,
          // matching the _safeExit() pattern used by the other buttons above.
          onPressed: () => _captureCurrentFrame(),
          icon: _isCapturingScreenshot
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(LucideIcons.camera, color: Colors.white),
        ),
        const SizedBox(width: 10),
        MaterialCustomButton(
          onPressed: _showSettingsSheet,
          icon: const Icon(LucideIcons.settings, color: Colors.white),
        ),
        const SizedBox(width: 10),
        MaterialCustomButton(
          onPressed: () => _safeExit(),
          icon: const Icon(LucideIcons.minimize, color: Colors.white),
        ),
      ],
      topButtonBar: [
        MaterialCustomButton(
          onPressed: () => _safeExit(),
          icon: DirectionalFlip(child: Icon(LucideIcons.arrowLeft, color: Colors.white)),
        ),
        const SizedBox(width: 14),
        Text(widget.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
      // ── Only play/pause remains in the centre — no seek buttons ──────
      primaryButtonBar: [
        const Spacer(flex: 2),
        const MaterialPlayOrPauseButton(iconSize: 56),
        const Spacer(flex: 2),
      ],
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _safeExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        primary: false,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Capturable layer (video + controls + watermark) ─────────
            // ✅ ملفوفة بـ RepaintBoundary(key: _screenshotBoundaryKey)
            // لميزة "لقطة الفيديو" — راجع التعليق فوق _screenshotBoundaryKey
            // بخصوص عناصر التحكم الافتراضية لـ media_kit.
            RepaintBoundary(
              key: _screenshotBoundaryKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_isDisposing || !_isInitialized)
                    Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentYellow))
                  else if (_isError)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                color: AppColors.error, size: 64),
                            const SizedBox(height: 16),
                            Text(_errorMessage,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh,
                                  color: Colors.black),
                              onPressed: () {
                                FirebaseCrashlytics.instance.log(
                                    "🔄 User clicked Retry on network error");
                                _retryPlayback();
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accentYellow,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12)),
                              label: Text(AppLocalizations.of(context)!.retry,
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            )
                          ],
                        ),
                      ),
                    )
                  else
                    Center(
                      child: IgnorePointer(
                        ignoring: _isDisposing || _isError,
                        // ✅ مشغل الفيديو وأدوات التحكم (شريط التقدم/الوقت) تبقى دائماً
                        // باتجاه LTR بشكل متعمد، حتى داخل واجهة عربية RTL، لأن أشرطة
                        // التقدم الزمني والأرقام تقرأ تقليدياً من اليسار لليمين.
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: MaterialVideoControlsTheme(
                            // Safe: this branch only renders when _isInitialized
                            // is true (see the enclosing if/else above), which is
                            // exactly when controlsTheme is non-null.
                            normal: controlsTheme!,
                            fullscreen: controlsTheme,
                            child: Video(
                                controller: _controller, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),

                  // ── Watermark ───────────────────────────────────────────
                  // ✅ نُقلت إلى داخل نفس الطبقة القابلة للالتقاط.
                  if (!_isDisposing && !_isError && _isInitialized)
                    AnimatedAlign(
                      alignment: _watermarkAlignment,
                      duration: const Duration(seconds: 2),
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(_watermarkText,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  decoration: TextDecoration.none)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            if (!_isDisposing &&
                !_isError &&
                (_isVideoLoading ||
                    !_isInitialized ||
                    _stabilizingCountdown > 0))
              Container(
                color: Colors.black.withOpacity(0.6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isVideoLoading || !_isInitialized)
                        CircularProgressIndicator(
                            color: AppColors.accentYellow),
                      if (_stabilizingCountdown > 0) ...[
                        const SizedBox(height: 24),
                        Text(
                          AppLocalizations.of(context)!.startingInCountdown(_stabilizingCountdown.toString()),
                          style: TextStyle(
                              color: AppColors.accentYellow,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                              letterSpacing: 2.0,
                              shadows: [
                                Shadow(
                                    blurRadius: 10,
                                    color: Colors.black,
                                    offset: Offset(2, 2))
                              ]),
                        ),
                        if (!_isVideoLoading)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Text(AppLocalizations.of(context)!.videoReadyStabilizing,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ]
                    ],
                  ),
                ),
              ),

            // ── Gesture layer: left half (rewind) + right half (forward) ──
            if (!_isDisposing && !_isError && _isInitialized && !_isRecordingDetected)
              Positioned(
                top: 70,
                bottom: 70,
                left: 0,
                right: 0,
                child: Row(
                  // ✅ نُثبت اتجاه هذا الصف على LTR عمداً، تماماً مثل أدوات
                  // التحكم بالفيديو، حتى يبقى النصف الفعلي الأيسر من الشاشة
                  // دائماً هو "الترجيع للخلف" والنصف الأيمن "التقديم للأمام"
                  // بغض النظر عن لغة الواجهة (عربي/إنجليزي).
                  textDirection: TextDirection.ltr,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _showLeftTapOverlay ? _onDoubleTapLeft : null,
                        onDoubleTap: _onDoubleTapLeft,
                        onLongPressStart: (_) => _onLongPressStart(),
                        onLongPressEnd: (_) => _onLongPressEnd(),
                        onLongPressCancel: _onLongPressEnd,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _showRightTapOverlay ? _onDoubleTapRight : null,
                        onDoubleTap: _onDoubleTapRight,
                        onLongPressStart: (_) => _onLongPressStart(),
                        onLongPressEnd: (_) => _onLongPressEnd(),
                        onLongPressCancel: _onLongPressEnd,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Left seek overlay ─────────────────────────────────────────
            if (_showLeftTapOverlay && !_isDisposing && !_isRecordingDetected)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: MediaQuery.of(context).size.width * 0.45,
                child: _buildSeekOverlay(
                  isLeft: true,
                  tapCount: _leftTapCount,
                  rippleAnim: _leftRippleAnim,
                ),
              ),

            // ── Right seek overlay ────────────────────────────────────────
            if (_showRightTapOverlay && !_isDisposing && !_isRecordingDetected)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: MediaQuery.of(context).size.width * 0.45,
                child: _buildSeekOverlay(
                  isLeft: false,
                  tapCount: _rightTapCount,
                  rippleAnim: _rightRippleAnim,
                ),
              ),

            // ── Long-press ×2 speed indicator ─────────────────────────────
            if (_isLongPressActive && !_isDisposing && !_isRecordingDetected)
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.accentYellow.withOpacity(0.8),
                            width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fast_forward,
                              color: AppColors.accentYellow, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.of(context)!.doubleSpeedLabel,
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Security alert overlay ────────────────────────────────────
            if (_isRecordingDetected)
              Container(
                color: Colors.red.shade900,
                width: double.infinity,
                height: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block, color: Colors.white, size: 80),
                    const SizedBox(height: 24),
                    Text(AppLocalizations.of(context)!.securityAlertTitle,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 16),
                    Text(
                        AppLocalizations.of(context)!.screenRecordingDetectedMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 32),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.yellow, width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(AppLocalizations.of(context)!.finalWarningTitle,
                              style: const TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                              AppLocalizations.of(context)!.contentRecordingViolationMessage,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(color: Colors.white, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () => _safeExit(),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red.shade900,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12)),
                      child: Text(AppLocalizations.of(context)!.closePlayer,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
