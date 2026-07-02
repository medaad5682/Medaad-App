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

  // -----------------------------------------------------------------------
  // FIX: Delegate all controls show/hide to BetterPlayer's built-in system.
  // toggleControlsVisibility() handles:
  //   - First tap  → fade controls in, start the 3s auto-hide timer
  //   - Second tap → hide controls immediately
  // No manual state, no competing Timer — one system owns the lifecycle.
  // -----------------------------------------------------------------------
  // 1. أعد إضافة هذا المتغير البسيط لتتبع حالة الأزرار
  bool _controlsVisible = false;

  // -----------------------------------------------------------------------
  // FIX: Delegate all controls show/hide to BetterPlayer's built-in system.
  // -----------------------------------------------------------------------
  void _toggleControls() {
    if (_betterPlayerController == null || _isDisposing) return;

    // 2. عكس الحالة مع كل نقرة
    _controlsVisible = !_controlsVisible; 

    // 3. تمرير الحالة الجديدة للدالة (هذا ما كان ينقص الكود ويسبب الخطأ)
    _betterPlayerController?.toggleControlsVisibility(_controlsVisible);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        autoPlay: true,
        looping: false,
        fullScreenByDefault: false,
        allowedScreenSleep: true,
        autoDetectFullscreenDeviceOrientation: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
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
          // BetterPlayer owns the hide timer — 3s after controls appear they
          // auto-hide. toggleControlsVisibility() resets this timer on each tap.
          controlsHideTime: const Duration(seconds: 3),
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
      break;

    // NEW: keep our local flag in sync with what BetterPlayer is actually
    // doing internally (including its own 3s auto-hide timer).
    case BetterPlayerEventType.controlsVisible:
      _controlsVisible = true;
      break;
    case BetterPlayerEventType.controlsHiddenStart:
      _controlsVisible = false;
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
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;
    _isDisposing = true;
    if (mounted) setState(() {});

    try {
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

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isDisposing = true;
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
              // All three zones use HitTestBehavior.translucent so
              // BetterPlayer's seek-bar drag still fires through.
              //
              // Single tap ANYWHERE → _toggleControls() which calls
              // toggleControlsVisibility(). BetterPlayer shows controls
              // immediately with a smooth fade, starts its own 3s hide
              // timer, and hides on a second tap. No manual timer needed.
              //
              // Double tap left/right → seek ±10s.
              // Long press left/right → ×2 hold speed.
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
                          children: const [
                            Icon(Icons.fast_forward, color: Colors.white70, size: 14),
                            SizedBox(width: 4),
                            Text(
                              '×2',
                              style: TextStyle(
                                color: Colors.white70,
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
                        opacity: _showSeekIndicator ? 0.55 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _seekIndicatorIsForward
                                    ? Icons.fast_forward
                                    : Icons.fast_rewind,
                                color: Colors.white.withOpacity(0.75),
                                size: 18,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_pendingSeekDelta.abs()} ث',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
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

              // ── Top bar: back + title + fit + speed + quality ─────────
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
