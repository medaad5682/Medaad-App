import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import '../../core/services/audio_protection_service.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/floating_video_controller.dart'; // إضافة متحكم الفيديو العائم
import '../../main.dart' show navigatorKey;

class NativeVideoPlayerScreen extends StatefulWidget {
  final Map<String, String> streams;
  final String title;

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

  String _currentQuality = "";
  List<String> _sortedQualities = [];

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitializing = true;
  bool _isDisposing = false;

  int _currentQualityIndex = 0;
  bool _handoffApplied = false;

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
  // [FIX] BoxFit.fitWidth was replaced with BoxFit.cover.
  // On iOS, better_player_plus maps BoxFit to native AVLayerVideoGravity,
  // and BOTH BoxFit.contain and BoxFit.fitWidth map to the same 'aspect'
  // gravity — so the resize button looked broken on iOS (2 of 3 taps
  // showed no visual change). BoxFit.cover maps to a distinct 'fill'
  // (crop-to-fill) gravity on iOS, giving 3 genuinely different states
  // on both Android and iOS.
  static const List<BoxFit> _fitCycle = [BoxFit.contain, BoxFit.fill, BoxFit.cover];
  static const List<String> _fitLabels = ['16:9', 'Full', 'Fill'];
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
  }

  void _onSeekStart(double _) {
    _isSeekBarDragging = true;
    _controlsAutoHideTimer?.cancel();
  }

  void _onSeekChanged(double value) {
    setState(() => _position = Duration(milliseconds: value.toInt()));
  }

  void _onSeekEnd(double value) {
    try {
      _betterPlayerController?.seekTo(Duration(milliseconds: value.toInt()));
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, null, reason: 'Native Player Seekbar Error');
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
    if (widget.initialSpeed != null) {
      _currentSpeed = widget.initialSpeed!;
    }
    _sortQualities();
    _loadUserData();
    _initializeProtection();
    _setupScreen();
  }

  void _sortQualities() {
    _sortedQualities = widget.streams.keys.toList();
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

  bool _isCodecError(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('mediacodec') ||
        msg.contains('exoplaybackexception') ||
        msg.contains('video/mp2t') ||
        msg.contains('videorenderer') ||
        msg.contains('codecexception') ||
        msg.contains('mediacodecvideorenderererror');
  }

  void _initializePlayer() {
    if (!mounted || _isDisposing) return;

    final initialUrl = widget.streams[_currentQuality]!;

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      initialUrl,
      headers: _headers,
      videoFormat: BetterPlayerVideoFormat.hls,
      resolutions: widget.streams,
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
        _attachVideoListener(); // 🟢 ربط الـ Listener المخصص
        _applyHandoffStateIfNeeded();
        break;
      default:
        break;
    }
  }

  void _handlePlayerError(String errorDescription, {required bool isCodecRelated}) {
    if (!mounted || _isDisposing) return;

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
        final fallbackUrl = widget.streams[fallbackQuality];

        if (fallbackUrl != null) {
          FirebaseCrashlytics.instance.log(
            '🔄 Codec error on $_currentQuality → auto-fallback to $fallbackQuality',
          );
          setState(() {
            _currentQuality = fallbackQuality;
            _currentQualityIndex = nextIndex;
          });
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

      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage =
              'جهازك لا يدعم فك ترميز هذه الجودة. جرّب اختيار جودة أقل من أيقونة ⚙️ أعلى الشاشة.';
          _isInitializing = false;
        });
      }
    } else {
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
      _betterPlayerController?.setResolution(widget.streams[quality]!);
      _reapplySpeedAfterSourceChange();
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Native Player setResolution Error');
      _handlePlayerError(e.toString(), isCodecRelated: _isCodecError(e));
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
    _betterPlayerController?.setOverriddenFit(_videoFit);
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
      await _recordingSubscription?.cancel();

      final controllerToDispose = _betterPlayerController;
      _betterPlayerController = null;
      controllerToDispose?.dispose(forceDispose: true);

      await WakelockPlus.disable();
      await _resetSystemChrome();
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'Native Player Exit Error');
    }

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isDisposing = true;
    
    _betterPlayerController?.videoPlayerController?.removeListener(_onVideoValueChanged);
    _controlsAutoHideTimer?.cancel();
    _watermarkTimer?.cancel();
    _seekIndicatorTimer?.cancel();
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
                                          : Icons.crop_free,
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
                                  final streams = widget.streams;
                                  final title = widget.title;
                                  final watermarkText = _watermarkText;
                                  final speed = _currentSpeed;
                                  final quality = _currentQuality;

                                  // 2. ✅ أغلق المشغل الحالي أولاً وانتظر تحرره فعليًا
                                  //    (بما فيها dispose() الخاص بـ ExoPlayer على الجانب
                                  //    الأصلي) قبل إنشاء أي مشغل جديد. إنشاء BetterPlayerController
                                  //    ثانٍ (للنافذة العائمة) بينما المشغل الأول لا يزال
                                  //    يحرر الـ MediaCodec/Surface الخاص به هو ما كان يسبب
                                  //    تنافسًا على مورد فك التشفير (decoder) في نفس اللحظة،
                                  //    وينتج عنه تجمّد الواجهة (ANR) بعد نحو ثانية من الضغط
                                  //    على الزر — بالضبط ما كان يظهر كـ "تجمد الشاشة بعد
                                  //    اختفاء النافذة العائمة".
                                  await _safeExit();

                                  // ✅ هامش أمان بسيط يعطي الجانب الأصلي وقتًا كافيًا
                                  // لإتمام تحرير الـ MediaCodec قبل إنشاء مشغل جديد.
                                  await Future.delayed(
                                      const Duration(milliseconds: 150));

                                  // 3. الآن فعّل وضع الفيديو العائم بعد تحرر المشغل القديم
                                  //    بالكامل (الشاشة السابقة أصبحت ظاهرة خلف النافذة
                                  //    العائمة تمامًا كما كان مخططًا).
                                  //    ⚠️ لا نتحقق من mounted هنا: بحلول هذه اللحظة تكون
                                  //    هذه الشاشة قد أُزيلت فعليًا من الشجرة (لأن _safeExit
                                  //    نفّذ الـ pop)، لكن FloatingVideoController هو
                                  //    Singleton مستقل تمامًا عن حالة هذه الشاشة — استدعاؤه
                                  //    بعد التخلص من الشاشة آمن تمامًا ولا يلمس أي context.
                                  FloatingVideoController.instance.startFloating(
                                    streams: streams,
                                    title: title,
                                    watermarkText: watermarkText,
                                    initialPosition: currentPosition,
                                    playbackSpeed: speed,
                                    initialQuality: quality,
                                    wasPlaying: wasPlaying,
                                  );
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
