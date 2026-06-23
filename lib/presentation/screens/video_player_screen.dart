import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:device_info_plus/device_info_plus.dart';
// ✅ مكتبات الحماية
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import '../../core/services/audio_protection_service.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/local_proxy.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
  final String title;
  final String? preReadyAudioUrl;

  const VideoPlayerScreen({
    super.key,
    required this.streams,
    required this.title,
    this.preReadyAudioUrl,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;

  final LocalProxyService _proxyService = LocalProxyService();

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

  bool _isVideoLoading = true;
  bool _isOfflineMode = false;

  bool _isWeakDevice = false;

  int _stabilizingCountdown = 0;
  Timer? _countdownTimer;

  bool _isDisposing = false;

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _seekDebounceTimer;
  Duration _accumulatedSeekAmount = Duration.zero;

  // ✅ [AV-SYNC] متغيرات مزامنة الصوت والصورة
  // آخر موضع تم تسجيله للفيديو (video position)
  Duration _lastKnownPosition = Duration.zero;
  // الوقت الحقيقي الذي سُجّل فيه هذا الموضع
  DateTime _lastPositionTimestamp = DateTime.now();
  // مؤقت دوري لرصد الإطارات المجمّدة أو التقدّم المفاجئ للخلف
  Timer? _avSyncTimer;
  // علامة: هل نحن في منتصف seek مقصود من المستخدم؟
  bool _isUserSeeking = false;
  // علامة: هل يجري الآن resync تلقائي (لمنع التكرار)؟
  bool _isAutoResyncing = false;

  // ✅ [DOUBLE-TAP SEEK] متغيرات النقر المزدوج للتقديم/الرجوع
  // عدد النقرات المتراكمة على اليسار (رجوع) وعلى اليمين (تقديم)
  int _leftTapCount = 0;
  int _rightTapCount = 0;
  // مؤقت لإخفاء الـ overlay بعد توقف النقر
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  // هل يظهر الـ overlay الآن؟
  bool _showLeftTapOverlay = false;
  bool _showRightTapOverlay = false;

  // ✅ [LONG-PRESS SPEED] متغيرات الضغط المطوّل لتسريع ×2
  bool _isLongPressActive = false;

  final Map<String, String> _serverHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)',
  };
  final Map<String, String> _youtubeHeaders = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeProtection(); // ✅ تفعيل الحماية أولاً
    _initializePlayerScreen();
  }

  // ✅ 1. دالة تفعيل الحماية والاستماع للتسجيل
  Future<void> _initializeProtection() async {
    try {
      // منع لقطات الشاشة وتسجيل الفيديو (يظهر شاشة سوداء)
      await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);

      // منع التقاط الصوت الداخلي
      await _protectionService.blockAudioCapture();

      // بدء مراقبة التطبيقات التي تسجل الصوت
      await _protectionService.startMonitoring();

      // الاستماع للتنبيهات
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

  // ✅ 2. دالة التعامل الصارم مع اكتشاف التسجيل (كتم الصوت + إيقاف)
  void _handleRecordingDetected() {
    if (!mounted) return;

    setState(() => _isRecordingDetected = true);

    // 🛑 الإجراء الحاسم: كتم الصوت تماماً وإيقاف المشغل
    _player.setVolume(0.0);
    _player.pause();

    FirebaseCrashlytics.instance
        .log("🚨 Security: Screen Recording Detected! Player Muted & Paused.");
  }

  // ✅ 3. مراقبة حالة التطبيق عند الخروج والعودة
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.pause();
    } else if (state == AppLifecycleState.resumed) {
      _protectionService.blockAudioCapture();
      // إعادة التحقق: إذا كان هناك تسجيل، تأكد من كتم الصوت مجدداً
      if (_isRecordingDetected) {
        _player.setVolume(0.0);
        _player.pause();
      }
    }
  }

  Future<void> _initializePlayerScreen() async {
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
          bufferSize: _isWeakDevice ? 3 * 1024 * 1024 : 32 * 1024 * 1024,
          vo: 'gpu',
        ),
      );

      if (forceSoftwareDecoding) {
        await (_player.platform as dynamic).setProperty('hwdec', 'no');
        await (_player.platform as dynamic).setProperty('vd-lavc-threads', '4');
        await (_player.platform as dynamic)
            .setProperty('sws-scaler', 'fast-bilinear');
      } else {
        await (_player.platform as dynamic).setProperty('hwdec', 'auto');
      }

      // ✅ [CACHE-PAUSE-WAIT] انتظر 3 ثوانٍ من البيانات قبل استئناف التشغيل
      // بدلاً من الاستئناف فور وصول أي بيانات، يضمن هذا حصانة ضد الاهتزاز المتكرر
      // على الشبكات البطيئة أو المتقطعة.
      await (_player.platform as dynamic)
          .setProperty('cache-pause-wait', '3');

      // ✅ [AV-SYNC] إعدادات إضافية لتحسين مزامنة الصوت والصورة
      // اجعل mpv يتسامح مع انجراف بسيط بين المسارين قبل أن يعيد المزامنة
      await (_player.platform as dynamic)
          .setProperty('audio-desync-correction', 'yes');

      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: !forceSoftwareDecoding,
          androidAttachSurfaceAfterVideoParameters: !_isWeakDevice,
        ),
      );

      // ✅ التعديل الأول (حل مشكلة الاتصال): اكتشاف انقطاع الإنترنت وإبلاغ المستخدم وحفظ مكان التوقف
      _player.stream.error.listen((error) {
        final errorString = error.toString().toLowerCase();

        if (errorString.contains('tcp') ||
            errorString.contains('timeout') ||
            errorString.contains('ffurl_read') ||
            errorString.contains('resolve hostname') ||
            errorString.contains('route to host') ||
            errorString.contains('decoding audio')) {
          
          if (mounted && !_isDisposing) {
            final currentPos = _player.state.position; // حفظ مكان التوقف بدقة
            setState(() {
              _isError = true;
              _errorPosition = currentPos;
              _errorMessage = "حدثت مشكلة في الاتصال بالشبكة.\nيرجى التأكد من استقرار الإنترنت وإعادة المحاولة.";
              _isVideoLoading = false;
            });
            _player.pause(); // إيقاف المشغل لمنع التخبط
          }
        }

        if (!errorString.contains("failed to open")) {
          FirebaseCrashlytics.instance
              .recordError(error, null, reason: 'MediaKit Stream Error');
        }
      });

      // ✅ 4. منع التشغيل التلقائي عند انتهاء التحميل إذا كان هناك تسجيل
      _player.stream.buffering.listen((buffering) {
        if (!buffering && _isVideoLoading) {
          if (mounted) {
            setState(() => _isVideoLoading = false);

            // 🛑 حارس الأمان: لا تشغل إذا تم اكتشاف تسجيل
            if (_isRecordingDetected) {
              _player.setVolume(0.0);
              _player.pause();
              return;
            }

            if (_isOfflineMode) {
              _startCountdown();
            } else {
              _player.play();
            }
          }
        }
      });

      // ✅ [AV-SYNC] تسجيل الموضع الحقيقي للفيديو باستمرار لرصد التقدّم الخاطئ للخلف
      _player.stream.position.listen((pos) {
        // فقط عندما يكون الفيديو قيد التشغيل الفعلي (غير متوقف وغير في حالة خطأ)
        if (!_isDisposing && !_isError && !_isAutoResyncing) {
          _lastKnownPosition = pos;
          _lastPositionTimestamp = DateTime.now();
        }
      });

      // ✅ [AV-SYNC] مراقب دوري: يكتشف تجمّد الإطارات والرجوع الخاطئ للخلف
      _startAvSyncWatchdog();

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
          _errorMessage = "فشل في تهيئة المشغل: $e";
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

    setState(() {
      _isVideoLoading = true;
      _stabilizingCountdown = 0;
    });
    _countdownTimer?.cancel();

    // ✅ [AV-SYNC] إعادة تعيين حالة المراقب عند بدء تحميل فيديو جديد
    // لمنع أي تدخّل خاطئ أثناء مرحلة التحميل
    _isUserSeeking = true; // اعتبر مرحلة التحميل كـ seek مقصود
    _isAutoResyncing = false;
    _lastKnownPosition = startAt ?? Duration.zero;
    _lastPositionTimestamp = DateTime.now();
    // سيُزال _isUserSeeking بعد ثانيتين من بدء التشغيل الفعلي (في stream.position)
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isDisposing) _isUserSeeking = false;
    });

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
        
        // ✅ [FIX F-08] استخدام الرابط الموقّع بشكل ديناميكي (HMAC)
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
                // ✅ [FIX F-08] استخدام الرابط الموقّع للملف الصوتي أيضاً
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

      // ✅ 5. حارس أمان إضافي عند فتح الميديا
      if (_isRecordingDetected) {
        await _player.setVolume(0.0);
        return;
      }

      if (audioUrl != null) {
        int delayMs = _isWeakDevice ? 2500 : 500;
        await Future.delayed(Duration(milliseconds: delayMs));

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

      if (startAt != null && startAt != Duration.zero) {
        await _player.seek(startAt);
      }

      if (_currentSpeed != 1.0) {
        await _player.setRate(_currentSpeed);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'PlayVideo Function Failed');
      if (mounted && !_isDisposing) {
        setState(() {
          _isError = true;
          _errorMessage = "فشل في تحميل الفيديو.";
          _isVideoLoading = false;
        });
      }
    }
  }

  Future<void> _seekRelative(Duration amount) async {
    // منع التنقل إذا كان هناك تسجيل
    if (_isRecordingDetected) return;

    _accumulatedSeekAmount += amount;
    if (_seekDebounceTimer?.isActive ?? false) _seekDebounceTimer!.cancel();

    // ✅ [CASE-2] علّم الـ watchdog بأن ما سيأتي هو seek مقصود من المستخدم
    _isUserSeeking = true;

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
        // أعطِ mpv ثانية لتستقر ثم أزل علامة الـ user-seek
        // حتى يعود الـ watchdog للمراقبة الطبيعية
        Future.delayed(const Duration(seconds: 1), () {
          _isUserSeeking = false;
        });
      }
    });
  }

  // ✅ [AV-SYNC] الدالة الرئيسية للمراقبة الدورية لمزامنة الصوت والصورة
  void _startAvSyncWatchdog() {
    _avSyncTimer?.cancel();

    // فحص كل ثانية واحدة
    _avSyncTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposing) {
        timer.cancel();
        return;
      }
      // لا تفحص في هذه الحالات:
      // - يتم التهيئة أو الإغلاق
      // - يوجد خطأ
      // - الفيديو محمّل (loading)
      // - الفيديو متوقف (paused) - لا يوجد تقدّم متوقع
      // - المستخدم يقوم بـ seek
      // - يجري resync الآن
      if (!_isInitialized ||
          _isError ||
          _isVideoLoading ||
          _isRecordingDetected ||
          _isUserSeeking ||
          _isAutoResyncing) return;

      final isPlaying = _player.state.playing;
      if (!isPlaying) return; // الفيديو متوقف بشكل مقصود

      final currentPos = _player.state.position;
      final duration = _player.state.duration;

      // تجاهل إذا كانت المدة غير معروفة بعد
      if (duration == Duration.zero) return;

      // ──────────────────────────────────────────────────────────────
      // [CASE-1A] رصد الرجوع المفاجئ للخلف أثناء التشغيل
      //
      // السيناريو: المستخدم كان عند 1:36 ↔ موضع الصورة رجع فجأة إلى ~00:00
      // بينما الصوت يستمر بشكل طبيعي.
      //
      // المنطق: إذا انخفض الموضع الحالي بأكثر من 5 ثوانٍ عن آخر موضع
      // مسجَّل (وكان آخر موضع قد تم تسجيله منذ أقل من 3 ثوانٍ)،
      // فهذا يعني أن الصورة قفزت للخلف بشكل غير مقصود.
      // ──────────────────────────────────────────────────────────────
      final timeSinceLastRecord =
          DateTime.now().difference(_lastPositionTimestamp).inMilliseconds;

      if (timeSinceLastRecord < 3000 && // الموضع الأخير حديث
          _lastKnownPosition.inSeconds > 5 && // لم نكن في البداية
          currentPos < _lastKnownPosition - const Duration(seconds: 5)) {
        // الصورة رجعت للخلف بأكثر من 5 ثوانٍ دون طلب المستخدم
        debugPrint(
            "⚠️ [AV-SYNC] Video jumped back! was=${_lastKnownPosition.inSeconds}s now=${currentPos.inSeconds}s → resyncing silently");
        FirebaseCrashlytics.instance.log(
            "⚠️ AV-SYNC: Unexpected jump back from ${_lastKnownPosition.inSeconds}s to ${currentPos.inSeconds}s");
        _silentResync(_lastKnownPosition);
        return;
      }

      // ──────────────────────────────────────────────────────────────
      // [CASE-1B] رصد تجمّد الإطارات (frozen video)
      //
      // السيناريو: الفيديو "يلعب" لكن الموضع لا يتقدم لأكثر من 4 ثوانٍ.
      // الصوت يستمر لكن الصورة ثابتة.
      //
      // المنطق: إذا مرّت 4+ ثوانٍ وموضع الصورة لم يتغير بما يكفي،
      // نعيد المزامنة للموضع الصحيح بصمت.
      // ──────────────────────────────────────────────────────────────
      if (timeSinceLastRecord > 4000) {
        // مرّت أكثر من 4 ثوانٍ بدون تحديث للموضع رغم أن الفيديو "يشتغل"
        // → الصورة مجمّدة
        final expectedPos =
            _lastKnownPosition + Duration(milliseconds: timeSinceLastRecord);

        // إذا كان الموضع المتوقع أقل من نهاية الفيديو بثانيتين (أي لم ننتهِ)
        if (expectedPos < duration - const Duration(seconds: 2) &&
            currentPos < expectedPos - const Duration(seconds: 3)) {
          debugPrint(
              "⚠️ [AV-SYNC] Video frozen at ${currentPos.inSeconds}s, expected ~${expectedPos.inSeconds}s → resyncing silently");
          FirebaseCrashlytics.instance.log(
              "⚠️ AV-SYNC: Frozen frame at ${currentPos.inSeconds}s for ${timeSinceLastRecord}ms");
          _silentResync(expectedPos);
        }
      }
    });
  }

  // ✅ [AV-SYNC] إعادة المزامنة بصمت: نقل الصورة للموضع الصحيح دون مقاطعة الصوت
  Future<void> _silentResync(Duration targetPosition) async {
    if (_isAutoResyncing || _isDisposing || _isError) return;

    _isAutoResyncing = true;
    try {
      final duration = _player.state.duration;
      // تأكد أن الهدف منطقي
      if (duration == Duration.zero || targetPosition > duration) {
        _isAutoResyncing = false;
        return;
      }

      // اجعل الهدف في حدود الفيديو مع هامش أمان 0.5 ثانية
      final safeTarget = targetPosition < Duration.zero
          ? Duration.zero
          : (targetPosition > duration - const Duration(milliseconds: 500)
              ? duration - const Duration(milliseconds: 500)
              : targetPosition);

      await _player.seek(safeTarget);

      // انتظر ثانية لتستقر الصورة ثم أعد التسجيل
      await Future.delayed(const Duration(seconds: 1));

      if (!_isDisposing) {
        _lastKnownPosition = _player.state.position;
        _lastPositionTimestamp = DateTime.now();
      }
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'AV-Sync Silent Resync Error');
    } finally {
      _isAutoResyncing = false;
    }
  }

  // ✅ [DOUBLE-TAP SEEK] معالج النقر المزدوج على اليسار
  // 1 نقرة = لا شيء | 2 نقرة = 10s | 3 نقرات = 20s | ...
  void _onDoubleTapLeft() {
    if (_isRecordingDetected || _isDisposing || _isError) return;

    _leftTapCount++;
    // الثانية الأولى = نقرة واحدة (لا seek) → نبدأ العدّ من النقرة الثانية
    // 2 نقرات = (2-1)*10 = 10s | 3 نقرات = (3-1)*10 = 20s
    final totalSeconds = (_leftTapCount - 1) * 10;

    _leftTapTimer?.cancel();
    _leftTapTimer = Timer(const Duration(milliseconds: 400), () {
      // نقرة فردية فقط: تجاهل — يمرّر الحدث للمشغّل
      if (_leftTapCount == 1) {
        if (mounted) setState(() { _showLeftTapOverlay = false; _leftTapCount = 0; });
        return;
      }
      _seekRelative(Duration(seconds: -totalSeconds));
      if (mounted) setState(() { _showLeftTapOverlay = false; _leftTapCount = 0; });
    });

    // أظهر الـ overlay فقط من النقرة الثانية فصاعداً
    if (_leftTapCount >= 2 && mounted) setState(() => _showLeftTapOverlay = true);
  }

  // ✅ [DOUBLE-TAP SEEK] معالج النقر المزدوج على اليمين
  // 1 نقرة = لا شيء | 2 نقرة = 10s | 3 نقرات = 20s | ...
  void _onDoubleTapRight() {
    if (_isRecordingDetected || _isDisposing || _isError) return;

    _rightTapCount++;
    final totalSeconds = (_rightTapCount - 1) * 10;

    _rightTapTimer?.cancel();
    _rightTapTimer = Timer(const Duration(milliseconds: 400), () {
      if (_rightTapCount == 1) {
        if (mounted) setState(() { _showRightTapOverlay = false; _rightTapCount = 0; });
        return;
      }
      _seekRelative(Duration(seconds: totalSeconds));
      if (mounted) setState(() { _showRightTapOverlay = false; _rightTapCount = 0; });
    });

    if (_rightTapCount >= 2 && mounted) setState(() => _showRightTapOverlay = true);
  }

  // ✅ [LONG-PRESS SPEED] تفعيل سرعة ×2 عند الضغط المطوّل
  void _onLongPressStart() {
    if (_isRecordingDetected || _isDisposing || _isError) return;
    if (mounted) setState(() => _isLongPressActive = true);
    _player.setRate(2.0);
  }

  // ✅ [LONG-PRESS SPEED] العودة للسرعة الأصلية عند رفع الإصبع
  void _onLongPressEnd() {
    if (_isDisposing) return;
    if (mounted) setState(() => _isLongPressActive = false);
    _player.setRate(_currentSpeed); // العودة للسرعة التي اختارها المستخدم
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
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text("الإعدادات",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold))),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(LucideIcons.monitor, color: Colors.white),
              title: Text("الجودة: $_currentQuality",
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showQualitySelection();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.gauge, color: Colors.white),
              title: Text("السرعة: ${_currentSpeed}x",
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
                        _playVideo(widget.streams[q]!, startAt: currentPos);
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

          // ✅ 6. حارس الأمان للعد التنازلي
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
    if (widget.streams.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "لا يوجد مصادر متاحة لهذا الفيديو.";
        _isVideoLoading = false;
      });
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    // ترتيب الجودات تصاعدياً (مثلاً 360p ثم 480p ثم 720p)
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    // اختيار الجودة الأولية: 480p ثم 360p ثم 720p ثم أعلى جودة متاحة
    if (_sortedQualities.contains("480p")) {
      _currentQuality = "480p";
    } else if (_sortedQualities.contains("360p")) {
      _currentQuality = "360p";
    } else if (_sortedQualities.contains("720p")) {
      _currentQuality = "720p";
    } else if (_sortedQualities.isNotEmpty) {
      _currentQuality = _sortedQualities.last; // آخر عنصر في الترتيب التصاعدي هو الأعلى
    } else {
      _currentQuality = "";
    }

    if (_currentQuality.isNotEmpty) {
      _playVideo(widget.streams[_currentQuality]!);
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

  // ✅ التعديل الثاني (حل مشكلة أبعاد الشاشة والمربع الأسود عند الخروج): 
  // فرض العودة للوضع الطولي وإعطاء النظام مهلة لإعادة رسم الواجهة قبل الرجوع
  Future<void> _resetSystemChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await Future.delayed(const Duration(milliseconds: 250)); // مهلة الرسم
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;

    if (mounted) setState(() => _isDisposing = true);

    try {
      _seekDebounceTimer?.cancel();
      _watermarkTimer?.cancel();
      _countdownTimer?.cancel();
      _avSyncTimer?.cancel(); // ✅ [AV-SYNC] إيقاف مراقب المزامنة
      _leftTapTimer?.cancel();  // ✅ [DOUBLE-TAP] إيقاف مؤقتات النقر
      _rightTapTimer?.cancel();
      await _player.stop();
      await _player.dispose();
      await WakelockPlus.disable();
      
      // التأكد من استدعاء إرجاع الأبعاد بشكل صحيح ومزامنتها قبل الخروج
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

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewPadding;

    final controlsTheme = MaterialVideoControlsThemeData(
      displaySeekBar: false,
      padding: EdgeInsets.only(
          top: padding.top > 0 ? padding.top : 20,
          bottom: padding.bottom > 0 ? padding.bottom : 20,
          left: 20,
          right: 20),
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const SizedBox(width: 10),
        // ✅ [CASE-2] تمييز السحب على شريط التقدم كـ seek مقصود من المستخدم
        // لمنع الـ AV-Sync watchdog من التدخل أثناء أو بعد السحب مباشرةً
        Expanded(
          child: GestureDetector(
            onHorizontalDragStart: (_) {
              _isUserSeeking = true;
            },
            onHorizontalDragEnd: (_) {
              // أعطِ mpv ثانية ونصف لتستقر بعد الـ seek
              Future.delayed(const Duration(milliseconds: 1500), () {
                _isUserSeeking = false;
              });
            },
            onTapDown: (_) {
              // النقر المباشر على الشريط أيضاً يُعدّ seek مقصود
              _isUserSeeking = true;
            },
            onTapUp: (_) {
              Future.delayed(const Duration(milliseconds: 1500), () {
                _isUserSeeking = false;
              });
            },
            behavior: HitTestBehavior.translucent,
            child: const MaterialSeekBar(),
          ),
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
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Text(widget.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
      primaryButtonBar: [
        const Spacer(flex: 2),
        MaterialCustomButton(
          onPressed: () => _seekRelative(const Duration(seconds: -10)),
          icon: const Icon(Icons.replay_10, size: 36, color: Colors.white),
        ),
        const SizedBox(width: 24),
        const MaterialPlayOrPauseButton(iconSize: 56),
        const SizedBox(width: 24),
        MaterialCustomButton(
          onPressed: () => _seekRelative(const Duration(seconds: 10)),
          icon: const Icon(Icons.forward_10, size: 36, color: Colors.white),
        ),
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
            if (_isDisposing || !_isInitialized)
              Center(
                  child:
                      CircularProgressIndicator(color: AppColors.accentYellow))
            else if (_isError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 64),
                      const SizedBox(height: 16),
                      Text(_errorMessage,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, color: Colors.black),
                        onPressed: () {
                          FirebaseCrashlytics.instance
                              .log("🔄 User clicked Retry on network error");
                          setState(() => _isError = false);
                          // ✅ تمرير وقت التوقف (errorPosition) ليعود لنفس الدقيقة
                          _playVideo(widget.streams[_currentQuality]!, startAt: _errorPosition);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentYellow,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                        label: const Text("إعادة المحاولة",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      )
                    ],
                  ),
                ),
              )
            else
              Center(
                // ✅ التعديل الثالث (حل مشكلة انهيار شريط التقديم Null Check):
                // نمنع لمس المشغل والشريط بالكامل إذا كان هناك خطأ أو يتم إغلاق الشاشة
                child: IgnorePointer(
                  ignoring: _isDisposing || _isError,
                  child: MaterialVideoControlsTheme(
                    normal: controlsTheme,
                    fullscreen: controlsTheme,
                    child: Video(controller: _controller, fit: BoxFit.contain),
                  ),
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
                          "Starting in $_stabilizingCountdown",
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
                          const Padding(
                            padding: EdgeInsets.only(top: 12.0),
                            child: Text("Video Ready - Stabilizing Stream...",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ]
                    ],
                  ),
                ),
              ),

            // ✅ [DOUBLE-TAP + LONG-PRESS] طبقة الإيماءات فوق المشغّل مباشرةً
            // مقسّمة إلى نصفين: يسار (رجوع) ويمين (تقديم)
            // يجب أن تكون فوق الفيديو وتحت الـ overlay المرئي ليظهر عليها
            if (!_isDisposing && !_isError && _isInitialized && !_isRecordingDetected)
              Positioned.fill(
                child: Row(
                  children: [
                    // ─── النصف الأيسر: رجوع ─10s بالنقر المزدوج + ×2 بالضغط المطوّل ───
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _onDoubleTapLeft,
                        onLongPressStart: (_) => _onLongPressStart(),
                        onLongPressEnd: (_) => _onLongPressEnd(),
                        onLongPressCancel: _onLongPressEnd,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    // ─── النصف الأيمن: تقديم +10s بالنقر المزدوج + ×2 بالضغط المطوّل ───
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _onDoubleTapRight,
                        onLongPressStart: (_) => _onLongPressStart(),
                        onLongPressEnd: (_) => _onLongPressEnd(),
                        onLongPressCancel: _onLongPressEnd,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

            // ✅ [DOUBLE-TAP OVERLAY] مؤشر مرئي للنقر المزدوج على اليسار
            if (_showLeftTapOverlay && !_isDisposing && !_isRecordingDetected)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: MediaQuery.of(context).size.width * 0.35,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showLeftTapOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withOpacity(0.15),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(80),
                          bottomRight: Radius.circular(80),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.replay, color: Colors.white, size: 32),
                            const SizedBox(height: 4),
                            Text(
                              '${(_leftTapCount - 1) * 10}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
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

            // ✅ [DOUBLE-TAP OVERLAY] مؤشر مرئي للنقر المزدوج على اليمين
            if (_showRightTapOverlay && !_isDisposing && !_isRecordingDetected)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: MediaQuery.of(context).size.width * 0.35,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showRightTapOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.white.withOpacity(0.15),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(80),
                          bottomLeft: Radius.circular(80),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.forward, color: Colors.white, size: 32),
                            const SizedBox(height: 4),
                            Text(
                              '${(_rightTapCount - 1) * 10}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
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

            // ✅ [LONG-PRESS SPEED] مؤشر مرئي للتسريع ×2 عند الضغط المطوّل
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
                            'speed×2',
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

            if (!_isDisposing && !_isError && _isInitialized)
              AnimatedAlign(
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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

            // ✅ 7. شاشة التحذير الحمراء مع التهديد
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
                    const Text("SECURITY ALERT",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 16),
                    const Text(
                        "Screen Recording Detected.\nPlayback has been disabled.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 32),
                    // ⚠️ صندوق التهديد
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.yellow, width: 2),
                      ),
                      child: const Column(
                        children: [
                          Text("⚠️ تحذير نهائي",
                              style: TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(
                              "تسجيل المحتوى مخالف لشروط الاستخدام.\nتكرار هذا الأمر سيؤدي إلى حظر حسابك نهائياً وحذف جميع بياناتك.",
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14),
                              textDirection: TextDirection.rtl),
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
                      child: const Text("CLOSE PLAYER",
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
