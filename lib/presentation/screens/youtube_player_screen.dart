import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ✅ مكتبات الحماية
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/services/audio_protection_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';

class YoutubePlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;

  const YoutubePlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
  });

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends State<YoutubePlayerScreen>
    with WidgetsBindingObserver {
  late YoutubePlayerController _controller;

  // ✅ متغيرات الحماية
  final AudioProtectionService _protectionService = AudioProtectionService();

  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;

  // متغيرات العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _userIdText = "";

  // ✅ متغير لحالة الإغلاق لمنع أخطاء اللمس
  bool _isDisposing = false;

  // ─── Pause-frame freeze ─────────────────────────────────────────────

  final GlobalKey _playerKey = GlobalKey();

  // The last captured frame image — updated on EVERY frame while playing.
  ui.Image? _frozenFrame;

  // Whether we are currently in a "user-paused" state.
  bool _isPaused = false;

  // Debounce timer for capture (used only as a fallback).
  Timer? _captureDebounce;

  // Continuous capture timer while playing — grabs a fresh frame every 300 ms
  // so that when the user pauses we already have a very recent frame ready.
  Timer? _rollingCaptureTimer;

  // Track previous playing state to detect transitions.
  bool _wasPlaying = false;

  // ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // ✅ 1. تفعيل وضع ملء الشاشة الأفقي
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 2. تفعيل Wakelock لمنع انطفاء الشاشة
    WakelockPlus.enable();

    // ✅ 3. تفعيل الحماية الأمنية
    _initializeProtection();

    // ✅ 4. جلب رقم الهاتف وبدء التحريك
    _getUserId();
    _startWatermarkAnimation();

    // ✅ 5. إعداد المشغل
    try {
      _controller = YoutubePlayerController(
        initialVideoId: widget.videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          hideControls: false,
          forceHD: false,
          isLive: false,
          loop: false,
          enableCaption: false,
          disableDragSeek: false,
        ),
      )..addListener(_playerListener);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'Youtube Player Init Error',
      );
    }
  }

  // ✅ دالة تفعيل الحماية
  Future<void> _initializeProtection() async {
    try {
      await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );

      await _protectionService.blockAudioCapture();
      await _protectionService.startMonitoring();

      _recordingSubscription = _protectionService.recordingStateStream.listen(
        (isRecording) {
          if (isRecording) {
            _handleRecordingDetected();
          }
        },
      );
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(
        e,
        null,
        reason: 'Protection Init Error',
      );
    }
  }

  // ✅ التعامل مع اكتشاف التسجيل
  void _handleRecordingDetected() {
    if (!mounted) return;

    setState(() => _isRecordingDetected = true);

    _controller.mute();
    _controller.pause();

    FirebaseCrashlytics.instance.log(
      "🚨 Security: Screen Recording Detected on YouTube Player! Muted & Paused.",
    );
  }

  // ✅ إعادة تفعيل الحماية عند العودة للتطبيق
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller.pause();
    } else if (state == AppLifecycleState.resumed) {
      _protectionService.blockAudioCapture();

      if (_isRecordingDetected) {
        _controller.mute();
        _controller.pause();
      }
    }
  }

  // ─── Frame capture helpers ─────────────────────────────────────────

  /// Captures the current rendered frame from the RepaintBoundary.
  /// Pass [storeFrozen] = true to also flip _isPaused = true after capture.
  Future<void> _captureFrame({bool storeFrozen = false}) async {
    if (_isDisposing || !mounted) return;

    try {
      final RenderRepaintBoundary? boundary =
          _playerKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) return;

      // toImage is async — bail if we were disposed while waiting
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);

      if (!mounted || _isDisposing) {
        image.dispose();
        return;
      }

      setState(() {
        _frozenFrame?.dispose();
        _frozenFrame = image;
        if (storeFrozen) _isPaused = true;
      });
    } catch (e) {
      debugPrint("⚠️ Frame capture failed: $e");
    }
  }

  /// Starts a periodic timer that captures a fresh frame every 300 ms
  /// while the video is playing. This ensures _frozenFrame is always
  /// within 300 ms of the actual paused position.
  void _startRollingCapture() {
    _rollingCaptureTimer?.cancel();
    _rollingCaptureTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _captureFrame(),
    );
  }

  void _stopRollingCapture() {
    _rollingCaptureTimer?.cancel();
    _rollingCaptureTimer = null;
  }

  void _playerListener() {
    if (_controller.value.hasError) {
      FirebaseCrashlytics.instance.log(
        "Youtube Player Error: ${_controller.value.errorCode}",
      );
    }

    // ✅ Security guard
    if (_isRecordingDetected && _controller.value.isPlaying) {
      _controller.pause();
      _controller.mute();
    }

    // ─── Detect playing ↔ paused transitions ──────────────────────────

    final isPlaying = _controller.value.isPlaying;

    if (!_wasPlaying && isPlaying) {
      // ── Resumed / started playing ──
      _captureDebounce?.cancel();

      // Hide the frozen overlay immediately so the live video shows through.
      if (mounted) setState(() => _isPaused = false);

      // Begin rolling capture so we always have a fresh frame.
      _startRollingCapture();
    } else if (_wasPlaying && !isPlaying) {
      // ── Just paused ──
      _stopRollingCapture();
      _captureDebounce?.cancel();

      // We already have a frame from the rolling capture that is at most
      // 300 ms old. Show it immediately (storeFrozen = true) so it appears
      // before the YouTube native pause-thumbnail has a chance to render.
      if (_frozenFrame != null && mounted) {
        setState(() => _isPaused = true);
      }

      // Also schedule one more capture after a short delay to get a frame
      // that is as close as possible to the exact pause point.
      _captureDebounce = Timer(
        const Duration(milliseconds: 80),
        () => _captureFrame(storeFrozen: true),
      );
    }

    _wasPlaying = isPlaying;
  }

  // ─────────────────────────────────────────────────────────────────

  void _getUserId() {
    String displayText = '';

    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] == null
          ? AppState().userData!['username'] ?? ''
          : AppState().userData!['phone'] ?? '';
    }

    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          var box = Hive.box('auth_box');
          displayText = box.get('phone') ?? box.get('username') ?? '';
        }
      } catch (e) {
        // ignore
      }
    }

    setState(() {
      _userIdText = displayText.isNotEmpty ? displayText : 'Unknown User';
    });
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(
      const Duration(seconds: 4),
      (timer) {
        if (mounted && !_isDisposing) {
          setState(() {
            final random = Random();
            double x = (random.nextDouble() * 1.8) - 0.9;
            double y = (random.nextDouble() * 1.6) - 0.8;
            _watermarkAlignment = Alignment(x, y);
          });
        }
      },
    );
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;

    if (mounted) setState(() => _isDisposing = true);

    try {
      _watermarkTimer?.cancel();
      _captureDebounce?.cancel();
      _stopRollingCapture();

      _controller.pause();

      await WakelockPlus.disable();

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      await Future.delayed(const Duration(milliseconds: 250));
    } catch (e) {
      debugPrint("⚠️ SafeExit Error: $e");
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void deactivate() {
    _controller.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _recordingSubscription?.cancel();
    _protectionService.stopMonitoring();

    _watermarkTimer?.cancel();
    _captureDebounce?.cancel();
    _stopRollingCapture();

    _frozenFrame?.dispose();

    if (!_isDisposing) {
      WakelockPlus.disable();
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }

    _controller.removeListener(_playerListener);
    _controller.dispose();

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
        body: Stack(
          children: [
            // ── 1. Video player ──────────────────────────────────────

            Center(
              child: IgnorePointer(
                ignoring: _isDisposing,
                child: RepaintBoundary(
                  key: _playerKey,
                  child: YoutubePlayer(
                    controller: _controller,
                    showVideoProgressIndicator: true,
                    progressIndicatorColor: AppColors.accentYellow,
                    progressColors: ProgressBarColors(
                      playedColor: AppColors.accentYellow,
                      handleColor: AppColors.accentYellow,
                    ),
                    bottomActions: [
                      const CurrentPosition(),
                      const SizedBox(width: 10),
                      const ProgressBar(isExpanded: true),
                      const SizedBox(width: 10),
                      const RemainingDuration(),
                      const PlaybackSpeedButton(),
                    ],
                  ),
                ),
              ),
            ),

            // ── 2. Frozen frame overlay ──────────────────────────────
            //
            // KEY FIXES vs the original:
            //
            //  a) We do NOT use IgnorePointer here — the overlay must
            //     intercept all touches so the YouTube player beneath
            //     cannot receive taps that would toggle its pause-thumbnail.
            //
            //  b) The overlay is a full Positioned.fill so it completely
            //     covers the player widget, blocking the native pause UI.
            //
            //  c) We place a transparent GestureDetector on top so that
            //     tapping the frozen frame resumes playback naturally,
            //     exactly like tapping the player normally would.

            if (_isPaused && _frozenFrame != null && !_isDisposing)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque, // absorbs every touch
                  onTap: () {
                    // Resume playback when the user taps the frozen frame.
                    _controller.play();
                  },
                  child: RawImage(
                    image: _frozenFrame,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),

            // ── 3. العلامة المائية ───────────────────────────────────

            if (!_isDisposing)
              AnimatedAlign(
                duration: const Duration(seconds: 2),
                curve: Curves.easeInOut,
                alignment: _watermarkAlignment,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _userIdText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),

            // ── 4. زر الرجوع والعنوان ────────────────────────────────

            Positioned(
              top: 20,
              left: 20,
              child: SafeArea(
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _safeExit,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.arrowLeft,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 5. شاشة التحذير ──────────────────────────────────────

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
                    const Text(
                      "SECURITY ALERT",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Screen Recording Detected.\nPlayback has been disabled.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () => _safeExit(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        "CLOSE PLAYER",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
