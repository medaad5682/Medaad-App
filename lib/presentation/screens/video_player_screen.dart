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
  late final Player _player;
  late final VideoController _controller;

  final LocalProxyService _proxyService = LocalProxyService();
  final AudioProtectionService _protectionService = AudioProtectionService();

  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;

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

  // ✅ [FIX-SEEKBAR-CRASH] When true, the seek bar and all pointer input
  // are absorbed so that in-flight pointer events (onPointerMove /
  // onPointerUp) cannot reach MaterialSeekBar after the widget is disposed.
  bool _blockInput = false;

  // ✅ [FIX-NETWORK-ERROR] Tracks whether the last error was a transient
  // network issue so we can avoid spamming Firebase with expected errors.
  bool _isNetworkError = false;

  // ✅ [FIX] Prevents the buffering listener from calling play() while
  // _playVideo() is still in the middle of setting up the source.
  bool _isLoadingNewSource = false;

  // ✅ [FIX] Prevents repeated buffering=false events mid-stream (network
  // hiccup, demuxer restart after setAudioTrack) from re-triggering play()
  // and jumping back to position 0.
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
  // _seekLockReleaseTimer removed — lock now uses Future.delayed per-call
  // so overlapping acquires each release independently (see _acquireSeekLock)

  // ✅ [DOUBLE-TAP SEEK]
  int _leftTapCount = 0;
  int _rightTapCount = 0;
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  bool _showLeftTapOverlay = false;
  bool _showRightTapOverlay = false;

  // ✅ [LONG-PRESS SPEED]
  bool _isLongPressActive = false;

  Timer? _leftTapInhibitTimer;
  Timer? _rightTapInhibitTimer;
  int _leftRawTapCount = 0;
  int _rightRawTapCount = 0;

  // ✅ [RIPPLE ANIMATION]
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

      // ── Error stream ────────────────────────────────────────────────────
      _player.stream.error.listen((error) {
        final errorString = error.toString().toLowerCase();

        // ✅ [FIX-NETWORK-ERROR] These are all expected transient network
        // failures. We show a retry UI but do NOT call recordError() since
        // they are user-environment issues, not code bugs — logging them
        // floods Firebase with non-actionable non-fatal events.
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
            // Save position BEFORE pausing so retry resumes from same spot.
            final currentPos = _player.state.position;
            setState(() {
              _isError = true;
              _isNetworkError = true;
              // Only update _errorPosition if we actually played past 0,
              // so a pre-playback error doesn't resume from Duration.zero
              // on a source that never started.
              if (currentPos > Duration.zero) {
                _errorPosition = currentPos;
              }
              _errorMessage =
                  "حدثت مشكلة في الاتصال بالشبكة.\nيرجى التأكد من استقرار الإنترنت وإعادة المحاولة.";
              _isVideoLoading = false;
            });
            _player.pause();
            // Log as a breadcrumb only — not a recordError.
            FirebaseCrashlytics.instance.log(
                "⚠️ Network error (non-fatal, expected): $errorString");
          }
          return; // ← Don't fall through to recordError below
        }

        // Real unexpected errors — log to Firebase.
        if (!errorString.contains("failed to open")) {
          FirebaseCrashlytics.instance
              .recordError(error, null, reason: 'MediaKit Stream Error');
        }
      });

      // ── Buffering stream ────────────────────────────────────────────────
      // ✅ [FIX] Two guards added:
      //
      //   1. _isLoadingNewSource — true while _playVideo() hasn't finished
      //      attaching the audio track and seeking to startAt. Prevents the
      //      very first buffering=false (fired right after open()) from
      //      calling play() before the audio track is ready, which caused
      //      mpv to restart the demuxer and jump back to position 0.
      //
      //   2. _hasStartedPlayback — latches to true after the first valid
      //      play() call for this source. Prevents a second buffering=false
      //      (caused by the demuxer restart that follows setAudioTrack())
      //      from calling play() a second time, which was the main reason
      //      the video visibly reset to 0 on mid-range / weak devices.
      _player.stream.buffering.listen((buffering) {
        if (!buffering &&
            _isVideoLoading &&
            !_isLoadingNewSource &&
            !_hasStartedPlayback) {
          // Latch immediately so any subsequent buffering=false is ignored.
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
    if (_isDisposing) return;

    // ✅ [FIX] Raise the loading-source flag BEFORE anything else so the
    // buffering listener cannot sneak in a play() call while we are still
    // setting up the source. Also reset the playback-started latch so the
    // listener will fire exactly once for this new source.
    _isLoadingNewSource = true;
    _hasStartedPlayback = false;

    setState(() {
      _isVideoLoading = true;
      _stabilizingCountdown = 0;
    });
    _countdownTimer?.cancel();

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

      await _player.stop();

      final bool isYoutubeSource = playUrl.contains('googlevideo.com');
      final headers = isYoutubeSource ? _youtubeHeaders : _serverHeaders;

      await _player.open(Media(playUrl, httpHeaders: headers), play: false);

      if (_isRecordingDetected) {
        await _player.setVolume(0.0);
        // ✅ [FIX] Always clear the flag before every early return so the
        // listener is not permanently blocked on the next source load.
        _isLoadingNewSource = false;
        return;
      }

      // ── Audio track attachment ──────────────────────────────────────────
      // ✅ [FIX] The audio track is attached here, INSIDE the loading guard.
      // mpv restarts the demuxer when a second audio stream is added, which
      // fires an extra buffering=false event. Because _isLoadingNewSource is
      // still true at that point, the buffering listener ignores that event
      // and does NOT call play() prematurely or reset position to 0.
      if (audioUrl != null) {
        if (_isWeakDevice) {
          // Wait for the first buffering=false before attaching on weak
          // devices to give the video demuxer time to become ready.
          // We use a one-shot completer so we don't rely on a fixed delay.
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
          // On capable devices a short delay is sufficient; the demuxer is
          // ready well within 500 ms.
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

        // ✅ [FIX] After setAudioTrack(), mpv fires one more demuxer-restart
        // buffering cycle. We wait for it to settle before releasing the
        // loading guard, so the buffering listener only sees the final stable
        // buffering=false and calls play() exactly once.
        final settleCompleter = Completer<void>();
        StreamSubscription? settleSub;
        final settleTimeout = Timer(const Duration(seconds: 5), () {
          if (!settleCompleter.isCompleted) settleCompleter.complete();
        });
        settleSub = _player.stream.buffering.listen((buffering) {
          if (!buffering && !settleCompleter.isCompleted) {
            settleCompleter.complete();
          }
        });
        await settleCompleter.future;
        settleTimeout.cancel();
        await settleSub.cancel();
      }

      // ── Seek to resume position ─────────────────────────────────────────
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
    } finally {
      // ✅ [FIX] Always release the loading guard here — whether we succeeded,
      // failed, or returned early. The buffering listener is now free to call
      // play() on the next buffering=false event it receives.
      _isLoadingNewSource = false;
    }
  }

  Future<void> _seekRelative(Duration amount) async {
    if (_isRecordingDetected) return;

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
    // ✅ [FIX-SEEK-LOCK] Each caller gets its own delayed decrement.
    // We no longer cancel the previous timer, so overlapping calls each
    // correctly release their own hold and _seekLockCount always reaches 0.
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
                        ? Icon(LucideIcons.check,
                            color: AppColors.accentYellow)
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
        // ✅ [FIX-NULL-CRASH] Use ?. instead of !. here — userData may have
        // become null between the check above and this setState call,
        // especially on slow devices where async gaps are longer.
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

    // ✅ [FIX-SEEKBAR-CRASH] Block ALL pointer input immediately before
    // anything is disposed. This prevents in-flight onPointerMove /
    // onPointerUp events from reaching MaterialSeekBar after its State's
    // context has been unmounted, which caused the fatal null-check crash:
    //   MaterialSeekBarState.onPointerMove → State.context → NPE
    //   MaterialSeekBarState.onPointerUp   → State.context → NPE
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

    // ✅ [FIX-DOUBLE-DISPOSE] If _safeExit() was NOT called (e.g. Flutter
    // removes the widget directly without a back-button press), we do the
    // cleanup here. We do NOT call Navigator.pop() because the widget is
    // already being removed from the tree — calling pop() here would cause
    // a double-pop and corrupt the navigation stack.
    if (!_isDisposing) {
      _seekDebounceTimer?.cancel();
      _watermarkTimer?.cancel();
      _countdownTimer?.cancel();
      _leftTapTimer?.cancel();
      _rightTapTimer?.cancel();
      _leftTapInhibitTimer?.cancel();
      _rightTapInhibitTimer?.cancel();
      try { _leftRippleController.dispose(); } catch (_) {}
      try { _rightRippleController.dispose(); } catch (_) {}
      try { _player.stop(); } catch (_) {}
      try { _player.dispose(); } catch (_) {}
      WakelockPlus.disable();
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
            // ✅ [FIX-SEEKBAR-CRASH] Absorb all pointer events when we are
            // shutting down. This prevents onPointerMove / onPointerUp
            // inside MaterialSeekBar from accessing a disposed State context.
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
                          // ✅ [FIX-NETWORK-ERROR] Reset both error flags
                          // and use _errorPosition (which was safely captured
                          // before the error) so playback resumes correctly.
                          setState(() {
                            _isError = false;
                            _isNetworkError = false;
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
