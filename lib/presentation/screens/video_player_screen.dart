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
  bool _isRecovering = false; // ✅ [RECOVERY-FIX] منع ظهور العد التنازلي أثناء الاسترداد الصامت

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _seekDebounceTimer;
  Duration _accumulatedSeekAmount = Duration.zero;

  // ✅ [SYNC-FIX] متغيرات مراقبة ومزامنة الصوت والصورة في وضع أوف لاين
  Timer? _syncWatchdogTimer;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _videoParamsSubscription;
  Duration _lastKnownPosition = Duration.zero;
  int _frozenFrameCount = 0;
  static const int _frozenFrameThreshold = 8; // عدد الثوانٍ قبل اعتبار الصورة متجمدة
  bool _isSeeking = false; // حارس لمنع تشغيل Watchdog أثناء عمليات Seek

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

        // ✅ [OFFLINE-FIX] البروكسي المحلي يعمل على 127.0.0.1 — أي خطأ شبكي منه
        // هو بالضرورة ناتج عن مشكلة داخلية (انتهاء صلاحية HMAC أو طلب Range خاطئ)
        // وليس انقطاعاً في الإنترنت. نتجاهله هنا تماماً لأن Watchdog سيتولى الاسترداد.
        if (_isOfflineMode) {
          // سجّل في Crashlytics للتشخيص دون إظهار شاشة الخطأ للمستخدم
          if (!errorString.contains("failed to open")) {
            FirebaseCrashlytics.instance
                .recordError(error, null, reason: '[Offline] Proxy Stream Error');
          }

          // ✅ حالة خاصة: إذا انتهت صلاحية رابط HMAC (مرّت أكثر من ساعتين)
          // أعد توليد الروابط الموقّعة وأعد التشغيل من نفس الموضع بهدوء
          if (errorString.contains('403') ||
              errorString.contains('forbidden') ||
              errorString.contains('access denied') ||
              errorString.contains('link expired')) {
            if (mounted && !_isDisposing && !_isSeeking) {
              final currentPos = _player.state.position;
              FirebaseCrashlytics.instance
                  .log("🔑 [OFFLINE-FIX] HMAC link expired at $currentPos — refreshing silently.");
              _recoverVideoSync(currentPos);
            }
          }
          return; // توقف هنا ولا تُظهر شاشة خطأ الشبكة أبداً في وضع أوف لاين
        }

        // وضع أونلاين: نفس المنطق الأصلي لمشاكل الشبكة الحقيقية
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
              // ✅ [RECOVERY-FIX] أثناء الاسترداد الصامت (Watchdog)، لا تُشغّل العد التنازلي
              // ابدأ التشغيل مباشرة وأعد تشغيل Watchdog دون أن يلاحظ المستخدم شيئاً
              if (_isRecovering) {
                _player.play();
                _startSyncWatchdog();
              } else {
                _startCountdown();
              }
            } else {
              _player.play();
              // ✅ [SYNC-FIX] ابدأ مراقبة المزامنة للمحتوى الأونلاين بعد التشغيل
              _startSyncWatchdog();
            }
          }
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

    // ✅ [SYNC-FIX] إيقاف Watchdog وإعادة تعيين حالة المزامنة قبل أي تشغيل جديد
    _stopSyncWatchdog();
    _frozenFrameCount = 0;
    _lastKnownPosition = Duration.zero;
    _isSeeking = false;

    setState(() {
      _isVideoLoading = true;
      _stabilizingCountdown = 0;
    });
    _countdownTimer?.cancel();

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
        // ✅ [SYNC-FIX] في وضع أوف لاين، انتظر حتى يصبح الفيديو جاهزاً فعلاً (video-params)
        // قبل إرفاق المسار الصوتي، لضمان أن كلا المسارين يبدآن من نفس اللحظة.
        if (_isOfflineMode) {
          try {
            await _player.stream.videoParams
                .firstWhere((p) => p.w != null && p.w! > 0)
                .timeout(const Duration(seconds: 8));
          } catch (_) {
            // إذا انقضى الوقت، نكمل على أي حال لتجنب التجمد
          }
        } else {
          int delayMs = _isWeakDevice ? 2500 : 500;
          await Future.delayed(Duration(milliseconds: delayMs));
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

      if (startAt != null && startAt != Duration.zero) {
        // ✅ [SYNC-FIX] بعد Seek يجب إعادة مزامنة الصورة مع الصوت
        _isSeeking = true;
        await _player.seek(startAt);
        // أعطِ المشغل لحظة لتحديث الإطار بعد الانتقال
        await Future.delayed(const Duration(milliseconds: 200));
        _isSeeking = false;
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

    _seekDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final duration = _player.state.duration;
        // تأكد من أن مدة الفيديو صالحة
        if (duration == Duration.zero) return;

        final currentPos = _player.state.position;
        var targetPos = currentPos + _accumulatedSeekAmount;

        // ✅ إصلاح مشكلة الرجوع: إذا كان الناتج أقل من صفر، اجعله صفر (بداية الفيديو)
        if (targetPos < Duration.zero) {
          targetPos = Duration.zero;
        }

        // ✅ إصلاح مشكلة التقديم: إذا كان الناتج أكبر من مدة الفيديو، اجعله في النهاية
        if (targetPos > duration) {
          targetPos = duration;
        }

        // ✅ [SYNC-FIX] تعليم حالة Seeking لإيقاف Watchdog مؤقتاً
        _isSeeking = true;
        _frozenFrameCount = 0; // إعادة تعيين عداد التجمد

        await _player.seek(targetPos);

        // ✅ [SYNC-FIX] في وضع أوف لاين، أعطِ المشغل مهلة لتحديث إطار الفيديو
        // ثم أعد التشغيل إذا كان متوقفاً بسبب الـ Seek (يحل مشكلة تجمد الصورة)
        if (_isOfflineMode) {
          await Future.delayed(const Duration(milliseconds: 150));
          final wasPlaying = _player.state.playing;
          if (wasPlaying) {
            // إجبار المشغل على تحديث buffer بعد الانتقال
            await _player.pause();
            await Future.delayed(const Duration(milliseconds: 80));
            await _player.play();
          }
        }

        _isSeeking = false;
      } catch (e) {
        _isSeeking = false;
        FirebaseCrashlytics.instance.recordError(e, null, reason: 'Seek Error');
      } finally {
        _accumulatedSeekAmount = Duration.zero;
      }
    });
  }

  // =========================================================================
  // ✅ [SYNC-FIX] Watchdog: مراقبة مستمرة للمزامنة بين الصوت والصورة
  // يعالج: (1) تجمد الصورة، (2) إعادة الفيديو لـ 0:00، (3) تجمد بعد Seek
  // =========================================================================

  void _startSyncWatchdog() {
    _syncWatchdogTimer?.cancel();
    _frozenFrameCount = 0;
    _lastKnownPosition = _player.state.position;

    _syncWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isDisposing || !mounted) {
        timer.cancel();
        return;
      }

      // لا تعمل أثناء التحميل أو الإيقاف المؤقت أو عمليات Seek أو التسجيل
      if (_isVideoLoading || !_player.state.playing || _isSeeking || _isRecordingDetected) {
        _frozenFrameCount = 0;
        _lastKnownPosition = _player.state.position;
        return;
      }

      final currentPos = _player.state.position;

      // ✅ حالة 1: الفيديو رجع إلى الصفر (0:00) بينما الصوت يكمل
      // يحدث عندما يُعيد المشغل buffer الفيديو من البداية بسبب خلل في الـ Demuxer
      if (currentPos < const Duration(seconds: 2) &&
          _lastKnownPosition > const Duration(seconds: 10)) {
        FirebaseCrashlytics.instance
            .log("🔄 [SYNC-FIX] Video reset to 0 detected! Restoring to: $_lastKnownPosition");
        timer.cancel();
        _frozenFrameCount = 0;
        await _recoverVideoSync(_lastKnownPosition);
        return;
      }

      // ✅ حالة 2: الصورة متجمدة (Position لا تتقدم رغم التشغيل)
      final diff = (currentPos - _lastKnownPosition).abs();
      if (diff < const Duration(milliseconds: 200)) {
        _frozenFrameCount++;
        if (_frozenFrameCount >= _frozenFrameThreshold) {
          FirebaseCrashlytics.instance
              .log("🔄 [SYNC-FIX] Frozen frame detected after $_frozenFrameCount sec at $currentPos. Recovering...");
          timer.cancel();
          _frozenFrameCount = 0;
          await _recoverVideoSync(currentPos);
          return;
        }
      } else {
        // التقدم طبيعي، أعد العداد
        _frozenFrameCount = 0;
        _lastKnownPosition = currentPos;
      }
    });
  }

  void _stopSyncWatchdog() {
    _syncWatchdogTimer?.cancel();
    _syncWatchdogTimer = null;
    _frozenFrameCount = 0;
  }

  /// ✅ [SYNC-FIX] دالة الاسترداد: تعيد بناء الجسر بين مسار الصوت والصورة
  /// عن طريق إعادة فتح نفس الملف من الموضع الحالي بدون مقاطعة المستخدم
  Future<void> _recoverVideoSync(Duration position) async {
    if (_isDisposing || !mounted) return;

    FirebaseCrashlytics.instance.log("🛠️ [SYNC-FIX] Starting recovery at position: $position");

    try {
      final currentQualityUrl = widget.streams[_currentQuality];
      if (currentQualityUrl == null) return;

      // احفظ حالة التشغيل الحالية
      final wasPlaying = _player.state.playing;

      // ✅ [RECOVERY-FIX] علّم حالة الاسترداد لمنع العد التنازلي في buffering listener
      _isRecovering = true;

      // أعد تشغيل الفيديو من الموضع المحفوظ (سيعيد ربط مسار الصوت أيضاً)
      await _playVideo(currentQualityUrl, startAt: position);

      // إذا لم يكن التشغيل جارياً، لا تبدأه تلقائياً
      if (!wasPlaying && mounted) {
        await _player.pause();
      }

      FirebaseCrashlytics.instance.log("✅ [SYNC-FIX] Recovery successful at: $position");
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'SyncWatchdog Recovery Failed');
    } finally {
      // ✅ [RECOVERY-FIX] أعد تعيين العلامة دائماً حتى في حالة الخطأ
      _isRecovering = false;
    }
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
            // ✅ [SYNC-FIX] ابدأ مراقبة المزامنة بعد انتهاء العد التنازلي (وضع أوف لاين)
            _startSyncWatchdog();
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
      _stopSyncWatchdog(); // ✅ [SYNC-FIX] إيقاف Watchdog قبل إيقاف المشغل
      _positionSubscription?.cancel();
      _videoParamsSubscription?.cancel();
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
    _positionSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _stopSyncWatchdog(); // ✅ [SYNC-FIX]
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
        const Expanded(child: MaterialSeekBar()),
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

            if (!_isDisposing && !_isError && _isInitialized)
              AnimatedAlign(
                duration: const Duration(seconds: 2),
                curve: Curves.easeInOut,
                alignment: _watermarkAlignment,
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
