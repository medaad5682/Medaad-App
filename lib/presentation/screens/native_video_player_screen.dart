import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
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
// يستخدم حزمة video_player الرسمية من Flutter (ExoPlayer على أندرويد و
// AVPlayer على آيفون) بدلاً من مكتبة media_kit (المبنية على libmpv).
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
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

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

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

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
    _sortedQualities.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return numB.compareTo(numA); // من الأعلى جودة للأقل
    });
    if (_sortedQualities.isNotEmpty) {
      _currentQuality = _sortedQualities.first;
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
    _videoController?.setVolume(0.0);
    _videoController?.pause();
    FirebaseCrashlytics.instance.log(
        "🚨 Security: Screen Recording Detected! Native Player Muted & Paused.");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _videoController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _protectionService.blockAudioCapture();
      if (_isRecordingDetected) {
        _videoController?.setVolume(0.0);
        _videoController?.pause();
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

      await _initializePlayer(widget.streams[_currentQuality]!);
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
  // تهيئة/تبديل المشغل
  // ---------------------------------------------------------------------

  Future<void> _initializePlayer(String url, {Duration? startAt}) async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _isError = false;
    });

    final oldController = _videoController;
    final oldChewie = _chewieController;

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: _headers,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      if (startAt != null) {
        await controller.seekTo(startAt);
      }
      await controller.play();

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: false,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.accentYellow,
          handleColor: AppColors.accentYellow,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white10,
        ),
        errorBuilder: (context, errorMessage) => _buildErrorWidget(errorMessage),
      );

      if (!mounted) {
        chewie.dispose();
        controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _isInitializing = false;
      });

      // نتخلص من المتحكمات القديمة (إن وُجدت) بعد نجاح التبديل بأمان
      oldChewie?.dispose();
      await oldController?.dispose();
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Native Player Init Error: $url');
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = "تعذر تشغيل الفيديو. تحقق من اتصال الإنترنت.";
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _switchQuality(String quality) async {
    if (quality == _currentQuality || !widget.streams.containsKey(quality)) {
      return;
    }
    final position = _videoController?.value.position ?? Duration.zero;
    setState(() => _currentQuality = quality);
    await _initializePlayer(widget.streams[quality]!, startAt: position);
  }

  void _retryCurrentQuality() {
    if (_currentQuality.isNotEmpty && widget.streams[_currentQuality] != null) {
      _initializePlayer(widget.streams[_currentQuality]!);
    }
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _sortedQualities.map((q) {
              final selected = q == _currentQuality;
              return ListTile(
                leading: Icon(
                  selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                  color: selected ? AppColors.accentYellow : Colors.white54,
                ),
                title: Text(q, style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _switchQuality(q);
                },
              );
            }).toList(),
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
    if (mounted) setState(() => _isDisposing = true);

    try {
      _watermarkTimer?.cancel();
      await _recordingSubscription?.cancel();
      _chewieController?.dispose();
      await _videoController?.dispose();
      await WakelockPlus.disable();
      await FlutterWindowManagerPlus.clearFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);
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
    _watermarkTimer?.cancel();
    _recordingSubscription?.cancel();
    _chewieController?.dispose();
    _videoController?.dispose();
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
              else if (_isInitializing || _chewieController == null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.accentYellow),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.of(context)?.videoReadyStabilizing ??
                            'جاري التحميل...',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                )
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio == 0
                        ? 16 / 9
                        : _videoController!.value.aspectRatio,
                    child: Chewie(controller: _chewieController!),
                  ),
                ),

              // ── شريط علوي: رجوع + عنوان + زر الجودة ──────────────────
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
