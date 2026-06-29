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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── FIX #2: Guard late fields with an init flag so dispose() never
  // touches them if initState()'s async body never completed.
  bool _isPlayerInitialized = false;
  late final Player _player;
  late final VideoController _controller;

  final LocalProxyService _proxyService = LocalProxyService();
  final AudioProtectionService _protectionService = AudioProtectionService();

  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;

  // ── FIX #1: Store media_kit stream subscriptions so they can be cancelled.
  StreamSubscription? _errorStreamSub;
  StreamSubscription? _bufferingStreamSub;

  String _currentQuality = "";
  List<String> _sortedQualities = [];
  double _currentSpeed = 1.0;

  bool _isError = false;
  String _errorMessage = "";
  bool _isInitialized = false;

  Duration _errorPosition = Duration.zero;

  bool _isVideoLoading = true;
  bool _isOfflineMode = false;
  bool _isWeakDevice = false;

  bool _blockInput = false;

  // ── FIX #3: Token-based cancellation for concurrent _playVideo calls.
  // Each call increments this counter; a call that finds its token stale
  // knows it has been superseded and bails out early.
  int _playToken = 0;

  bool _isLoadingNewSource = false;
  bool _hasStartedPlayback = false;

  int _stabilizingCountdown = 0;
  Timer? _countdownTimer;

  bool _isDisposing = false;

  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _watermarkText = "";

  Timer? _seekDebounceTimer;
  Duration _accumulatedSeekAmount = Duration.zero;

  int _seekLockCount = 0;

  // ✅ [DOUBLE-TAP SEEK]
  int _leftTapCount = 0;
  int _rightTapCount = 0;
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  bool _showLeftTapOverlay = false;
  bool _showRightTapOverlay = false;

  // ✅ [LONG-PRESS SPEED]
  bool _isLongPressActive = false;

  // ── FIX #10: Removed dead _leftRawTapCount / _rightRawTapCount fields.
  Timer? _leftTapInhibitTimer;
  Timer? _rightTapInhibitTimer;

  // ✅ [RIPPLE ANIMATION]
  late AnimationController _leftRippleController;
  late AnimationController _rightRippleController;
  late Animation<double> _leftRippleAnim;
  late Animation<double> _rightRippleAnim;

  // ── FIX #5: Track whether animation controllers have been initialised so
  // dispose() never tries to tear them down before init completed.
  bool _animControllersInitialized = false;

  final Map<String, String> _serverHeaders = {
    'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)',
  };
  final Map<String, String> _youtubeHeaders = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
    _animControllersInitialized = true;

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
    if (_isPlayerInitialized) {
      _player.setVolume(0.0);
      _player.pause();
    }
    FirebaseCrashlytics.instance
        .log("🚨 Security: Screen Recording Detected! Player Muted & Paused.");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isPlayerInitialized) return;
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

      // ── FIX #12: Removed explicit vo: 'gpu' — media_kit picks the best VO
      // automatically per platform. Forcing 'gpu' can conflict with
      // androidAttachSurfaceAfterVideoParameters and cause black screens on
      // Android 10 devices.
      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: _isWeakDevice ? 8 * 1024 * 1024 : 32 * 1024 * 1024,
        ),
      );

      // ── FIX #2: Mark player as ready before any await that could let
      // dispose() run first.
      _isPlayerInitialized = true;

      if (forceSoftwareDecoding) {
        await (_player.platform as dynamic).setProperty('hwdec', 'no');
        await (_player.platform as dynamic).setProperty('vd-lavc-threads', '4');
        await (_player.platform as dynamic)
            .setProperty('sws-scaler', 'fast-bilinear');
        await (_player.platform as dynamic).setProperty('cache-secs', '8');
        await (_player.platform as dynamic)
            .setProperty('demuxer-readahead-secs', '8');
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

      // ── FIX #1: Store subscriptions so they are cancelled on dispose. ──

      // ── Error stream ──────────────────────────────────────────────────────
      _errorStreamSub = _player.stream.error.listen((error) {
        final errorString = error.toString().toLowerCase();

        final bool isNetworkError = errorString.contains('tcp') ||
            errorString.contains('timeout') ||
            errorString.contains('ffurl_read') ||
            errorString.contains('resolve hostname') ||
            errorString.contains('route to host') ||
            errorString.contains('decoding audio') ||
            errorString.contains('0xffffff92') ||
            errorString.contains('0xffffff8e');

        if (isNetworkError) {
          if (mounted && !_isDisposing) {
            final currentPos = _player.state.position;
            setState(() {
              _isError = true;
              // ── FIX #11: _isNetworkError removed — it was set but never
              // read anywhere. The bool was dead code.
              _errorMessage =
                  "حدثت مشكلة في الاتصال بالشبكة.\nيرجى التأكد من استقرار الإنترنت وإعادة المحاولة.";
              // ── FIX #8: Always clear the loading flag on any error path
              // so the spinner doesn't stay over the error UI.
              _isVideoLoading = false;
              if (currentPos > Duration.zero) {
                _errorPosition = currentPos;
              }
            });
            _player.pause();
            FirebaseCrashlytics.instance.log(
                "⚠️ Network error (non-fatal, expected): $errorString");
          }
          return;
        }

        // Real unexpected errors.
        if (!errorString.contains("failed to open")) {
          FirebaseCrashlytics.instance
              .recordError(error, null, reason: 'MediaKit Stream Error');
        }

        // ── FIX #8: Set _isVideoLoading = false on the non-network error
        // path too, so the loading overlay doesn't block the error UI.
        if (mounted && !_isDisposing) {
          setState(() {
            _isError = true;
            _errorMessage = "حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.";
            _isVideoLoading = false;
          });
          _player.pause();
        }
      });

      // ── Buffering stream ──────────────────────────────────────────────────
      _bufferingStreamSub = _player.stream.buffering.listen((buffering) {
        if (!buffering &&
            _isVideoLoading &&
            !_isLoadingNewSource &&
            !_hasStartedPlayback) {
          _hasStartedPlayback = true;

          if (mounted) {
            setState(() => _isVideoLoading = false);

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
    if (_isDisposing || !_isPlayerInitialized) return;

    // ── FIX #3: Grab a unique token for this invocation. If a newer call
    // starts before we finish, our token will be stale and we bail out at
    // each checkpoint, preventing races on _isLoadingNewSource and
    // _hasStartedPlayback.
    final int myToken = ++_playToken;

    _isLoadingNewSource = true;

    // ── FIX #9: Reset _hasStartedPlayback here — BEFORE any await — so
    // even if an exception is thrown very early the buffering listener is
    // not permanently blocked on the next load.
    _hasStartedPlayback = false;

    setState(() {
      _isVideoLoading = true;
      _stabilizingCountdown = 0;
    });
    _countdownTimer?.cancel();

    _acquireSeekLock(const Duration(seconds: 4));

    try {
      // ── Token check: bail if superseded. ──────────────────────────────
      if (myToken != _playToken) return;

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
                audioUrl =
                    _proxyService.getSignedUrl(audioPath, isAudio: true);
              }
            }
          } catch (_) {}
        }
      } else {
        if (audioUrl == null && widget.preReadyAudioUrl != null) {
          audioUrl = widget.preReadyAudioUrl;
        }
      }

      // ── Token check ──────────────────────────────────────────────────
      if (myToken != _playToken) return;

      await _player.stop();

      // ── Token check ──────────────────────────────────────────────────
      if (myToken != _playToken) return;

      final bool isYoutubeSource = playUrl.contains('googlevideo.com');
      final headers = isYoutubeSource ? _youtubeHeaders : _serverHeaders;

      await _player.open(Media(playUrl, httpHeaders: headers), play: false);

      if (_isRecordingDetected) {
        await _player.setVolume(0.0);
        return;
      }

      // ── Token check ──────────────────────────────────────────────────
      if (myToken != _playToken) return;

      // ── Audio track attachment ────────────────────────────────────────
      if (audioUrl != null) {
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

        // ── Token check ────────────────────────────────────────────────
        if (myToken != _playToken) return;

        try {
          await _player.setAudioTrack(
              AudioTrack.uri(audioUrl, title: "HQ Audio", language: "en"));
        } catch (e) {
          await Future.delayed(const Duration(seconds: 2));
          // ── Token check ──────────────────────────────────────────────
          if (myToken != _playToken) return;
          try {
            await _player.setAudioTrack(
                AudioTrack.uri(audioUrl, title: "HQ Audio", language: "en"));
          } catch (_) {}
        }

        // ── FIX #13: Keep a reference to the settle subscription so it
        // can be cancelled if this call is superseded before settling.
        StreamSubscription? settleSub;
        final settleCompleter = Completer<void>();
        final settleTimeout = Timer(const Duration(seconds: 5), () {
          if (!settleCompleter.isCompleted) settleCompleter.complete();
        });
        settleSub = _player.stream.buffering.listen((buffering) {
          if (!buffering && !settleCompleter.isCompleted) {
            settleCompleter.complete();
          }
        });

        // Race: settle vs token invalidation.
        await Future.any([
          settleCompleter.future,
          Future.doWhile(() async {
            await Future.delayed(const Duration(milliseconds: 100));
            return myToken == _playToken && !settleCompleter.isCompleted;
          }),
        ]);

        settleTimeout.cancel();
        await settleSub.cancel();

        // ── Token check after settle ──────────────────────────────────
        if (myToken != _playToken) return;
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
          // ── FIX #8: Ensure loading overlay is cleared on exception too.
          _isVideoLoading = false;
        });
      }
    } finally {
      // Only release the guard if this call is still the active one.
      // A superseded call must NOT clear the flag for the newer call.
      if (myToken == _playToken) {
        _isLoadingNewSource = false;
      }
    }
  }

  Future<void> _seekRelative(Duration amount) async {
    if (_isRecordingDetected || !_isPlayerInitialized) return;

    _accumulatedSeekAmount += amount;
    if (_seekDebounceTimer?.isActive ?? false) _seekDebounceTimer!.cancel();

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

  void _acquireSeekLock(Duration holdFor) {
    _seekLockCount++;
    Future.delayed(holdFor, () {
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
      });
    });
  }

  void _onLongPressStart() {
    if (_isRecordingDetected || _isDisposing || _isError || !_isPlayerInitialized) return;
    if (mounted) setState(() => _isLongPressActive = true);
    _player.setRate(2.0);
  }

  void _onLongPressEnd() {
    if (_isDisposing || !_isPlayerInitialized) return;
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
                        ? Icon(LucideIcons.check,
                            color: AppColors.accentYellow)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (q != _currentQuality) {
                        final currentPos = _isPlayerInitialized
                            ? _player.state.position
                            : Duration.zero;
                        setState(() {
                          _currentQuality = q;
                          _isError = false;
                          // ── FIX #7: Clear the error position on quality
                          // switch so retries on the new stream don't seek
                          // to the old stream's error position.
                          _errorPosition = Duration.zero;
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
                        ? Icon(LucideIcons.check,
                            color: AppColors.accentYellow)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _currentSpeed = s);
                      if (_isPlayerInitialized) _player.setRate(s);
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
        if (mounted && _isPlayerInitialized) {
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
    if (widget.streams.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "لا يوجد مصادر متاحة لهذا الفيديو.";
        _isVideoLoading = false;
      });
      return;
    }

    _sortedQualities = widget.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      int valA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int valB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return valA.compareTo(valB);
    });

    if (_sortedQualities.contains("480p")) {
      _currentQuality = "480p";
    } else if (_sortedQualities.contains("360p")) {
      _currentQuality = "360p";
    } else if (_sortedQualities.contains("720p")) {
      _currentQuality = "720p";
    } else if (_sortedQualities.isNotEmpty) {
      _currentQuality = _sortedQualities.last;
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
            : AppState().userData?['username'] ?? 'Unknown User';
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
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await Future.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _safeExit() async {
    if (_isDisposing) return;

    if (mounted) setState(() {
      _blockInput = true;
      _isDisposing = true;
    });

    try {
      _seekDebounceTimer?.cancel();
      _watermarkTimer?.cancel();
      _countdownTimer?.cancel();
      _leftTapTimer?.cancel();
      _rightTapTimer?.cancel();
      _leftTapInhibitTimer?.cancel();
      _rightTapInhibitTimer?.cancel();

      // ── FIX #1: Cancel media_kit stream subscriptions. ──────────────
      await _errorStreamSub?.cancel();
      await _bufferingStreamSub?.cancel();

      // ── FIX #5: Animation controllers are disposed only in dispose()
      // (after the widget is removed from the tree), not here, to avoid
      // driving a disposed controller during the remaining build phase
      // between this point and Navigator.pop().
      // (Removed _leftRippleController.dispose() / _rightRippleController.dispose()
      //  from here — they now live exclusively in dispose().)

      // ── FIX #4: Stop the local proxy server. ────────────────────────
      try { await _proxyService.stop(); } catch (_) {}

      if (_isPlayerInitialized) {
        await _player.stop();
        await _player.dispose();
      }
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

    if (!_isDisposing) {
      // _safeExit() was NOT called (Flutter removed the widget directly).
      _seekDebounceTimer?.cancel();
      _watermarkTimer?.cancel();
      _countdownTimer?.cancel();
      _leftTapTimer?.cancel();
      _rightTapTimer?.cancel();
      _leftTapInhibitTimer?.cancel();
      _rightTapInhibitTimer?.cancel();

      // ── FIX #1: Cancel media_kit stream subscriptions. ──────────────
      _errorStreamSub?.cancel();
      _bufferingStreamSub?.cancel();

      // ── FIX #4: Stop proxy. ─────────────────────────────────────────
      try { _proxyService.stop(); } catch (_) {}

      // ── FIX #2: Only touch the player if it was successfully created.
      if (_isPlayerInitialized) {
        try { _player.stop(); } catch (_) {}
        try { _player.dispose(); } catch (_) {}
      }
      WakelockPlus.disable();
    }

    // ── FIX #5 & #6: Dispose animation controllers here and only here,
    // after the widget is fully removed from the tree. The try/catch is
    // narrowed to a real exception log instead of silent swallowing so
    // real double-dispose bugs surface during development.
    if (_animControllersInitialized) {
      try {
        _leftRippleController.dispose();
        _rightRippleController.dispose();
      } catch (e) {
        debugPrint("⚠️ AnimationController dispose error: $e");
      }
    }

    super.dispose();
  }

  Widget _buildSeekOverlay({
    required bool isLeft,
    required int tapCount,
    required Animation<double> rippleAnim,
  }) {
    final IconData seekIcon = isLeft
        ? Icons.keyboard_double_arrow_left_rounded
        : Icons.keyboard_double_arrow_right_rounded;

    final gradient = LinearGradient(
      begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        Colors.black.withOpacity(0.28),
        Colors.transparent,
      ],
    );

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
            Container(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: borderRadius,
              ),
            ),
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
                    Icon(seekIcon, color: Colors.white, size: 28),
                    const SizedBox(height: 2),
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
        Expanded(
          child: AbsorbPointer(
            absorbing: _blockInput || _isDisposing,
            child: GestureDetector(
              onHorizontalDragStart: (_) {
                _acquireSeekLock(const Duration(seconds: 2));
              },
              onHorizontalDragEnd: (_) {
                _acquireSeekLock(const Duration(milliseconds: 1500));
              },
              onTapDown: (_) {
                _acquireSeekLock(const Duration(seconds: 2));
              },
              onTapUp: (_) {
                _acquireSeekLock(const Duration(milliseconds: 1500));
              },
              behavior: HitTestBehavior.translucent,
              child: const MaterialSeekBar(),
            ),
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
            // ── Player / Error / Init state ───────────────────────────────
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
                        icon:
                            const Icon(Icons.refresh, color: Colors.black),
                        onPressed: () {
                          FirebaseCrashlytics.instance.log(
                              "🔄 User clicked Retry on network error");
                          setState(() {
                            _isError = false;
                          });
                          _playVideo(widget.streams[_currentQuality]!,
                              startAt: _errorPosition);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentYellow,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12)),
                        label: const Text("إعادة المحاولة",
                            style: TextStyle(
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
                  child: MaterialVideoControlsTheme(
                    normal: controlsTheme,
                    fullscreen: controlsTheme,
                    child:
                        Video(controller: _controller, fit: BoxFit.contain),
                  ),
                ),
              ),

            // ── Loading / stabilizing overlay ─────────────────────────────
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
                              shadows: const [
                                Shadow(
                                    blurRadius: 10,
                                    color: Colors.black,
                                    offset: Offset(2, 2))
                              ]),
                        ),
                        if (!_isVideoLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 12.0),
                            child: Text(
                                "Video Ready - Stabilizing Stream...",
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

            // ── Gesture layer ─────────────────────────────────────────────
            if (!_isDisposing &&
                !_isError &&
                _isInitialized &&
                !_isRecordingDetected)
              Positioned(
                top: 70,
                bottom: 70,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _showLeftTapOverlay
                            ? _onDoubleTapLeft
                            : null,
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
                        onTap: _showRightTapOverlay
                            ? _onDoubleTapRight
                            : null,
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
            if (_showLeftTapOverlay &&
                !_isDisposing &&
                !_isRecordingDetected)
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
            if (_showRightTapOverlay &&
                !_isDisposing &&
                !_isRecordingDetected)
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
            if (_isLongPressActive &&
                !_isDisposing &&
                !_isRecordingDetected)
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

            // ── Watermark ─────────────────────────────────────────────────
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
                        style:
                            TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 32),
                    Container(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.yellow, width: 2),
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
                              style: TextStyle(
                                  color: Colors.white, fontSize: 14),
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
                          style:
                              TextStyle(fontWeight: FontWeight.bold)),
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
