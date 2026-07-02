import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/floating_video_controller.dart';

// ============================================================
// 🎬 FloatingVideoOverlay
//
// A draggable, resizable Picture-in-Picture (PiP) video player.
// Drop this widget inside the Stack of any screen that should
// support floating video (e.g. PdfViewerScreen).
//
// Security contract
// ─────────────────
// • FLAG_SECURE is applied at the Android window level by
//   FlutterWindowManagerPlus.  That flag belongs to the *Activity*
//   (window), not individual widgets, so it remains active for the
//   entire app once set — the floating overlay simply inherits it.
// • This widget never calls removeFlags, so security is preserved.
// • The FLAG is re-asserted in initState as a belt-and-braces guard.
// ============================================================

class FloatingVideoOverlay extends StatefulWidget {
  /// Initial position offset from the bottom-right corner.
  final Offset initialOffset;

  const FloatingVideoOverlay({
    super.key,
    this.initialOffset = const Offset(16, 100),
  });

  @override
  State<FloatingVideoOverlay> createState() => _FloatingVideoOverlayState();
}

class _FloatingVideoOverlayState extends State<FloatingVideoOverlay>
    with WidgetsBindingObserver {
  // ── Geometry ────────────────────────────────────────────────
  static const double _minW = 180.0;
  static const double _maxW = 340.0;
  static const double _aspectRatio = 16 / 9;

  double _width = 240.0;
  double get _height => _width / _aspectRatio;

  late Offset _position; // top-left of the floating window
  bool _isDragging = false;

  // ── Player ──────────────────────────────────────────────────
  BetterPlayerController? _controller;
  bool _isPlaying = false;
  bool _isInitializing = true;
  bool _isError = false;
  String _currentQuality = '';
  List<String> _sortedQualities = [];

  // ── Watermark ───────────────────────────────────────────────
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;

  // ── Controls visibility ─────────────────────────────────────
  bool _controlsVisible = false;
  Timer? _controlsTimer;

  final FloatingVideoController _fvc = FloatingVideoController.instance;

  @override
  void initState() {
    super.initState();
    // Default position: bottom-right corner (adjusted in first build)
    _position = const Offset(16, 400);
    _assertFlagSecure();
    _initPlayer();
    _startWatermark();
    WidgetsBinding.instance.addObserver(this);
    _fvc.addListener(_onControllerChanged);
  }

  // ── Security ────────────────────────────────────────────────

  Future<void> _assertFlagSecure() async {
    try {
      await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _assertFlagSecure();
    }
    if (state == AppLifecycleState.paused) {
      _controller?.pause();
    }
  }

  // ── FloatingVideoController listener ────────────────────────

  void _onControllerChanged() {
    if (!_fvc.isFloating) {
      // Floating was stopped externally — dispose player
      _disposePlayer();
    }
  }

  // ── Player init ─────────────────────────────────────────────

  void _initPlayer() {
    final state = _fvc.videoState;
    if (state == null) return;

    _sortedQualities = state.streams.keys.toList();
    _sortedQualities.sort((a, b) {
      final nA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final nB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return nA.compareTo(nB); // ascending: start with lowest for PiP
    });

    // Choose a modest default quality for PiP (360p preferred)
    const preferred = ['360', '240', '480', '720'];
    int chosenIdx = 0;
    for (final p in preferred) {
      final idx = _sortedQualities
          .indexWhere((q) => q.replaceAll(RegExp(r'[^0-9]'), '') == p);
      if (idx != -1) {
        chosenIdx = idx;
        break;
      }
    }
    _currentQuality = _sortedQualities[chosenIdx];

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      state.streams[_currentQuality]!,
      headers: const {'User-Agent': 'ExoPlayerLib/2.18.1 (Linux; Android 12)'},
      videoFormat: BetterPlayerVideoFormat.hls,
      resolutions: state.streams,
      cacheConfiguration:
          const BetterPlayerCacheConfiguration(useCache: false),
      notificationConfiguration:
          const BetterPlayerNotificationConfiguration(showNotification: false),
    );

    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        fit: BoxFit.contain,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        autoDetectFullscreenDeviceOrientation: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
          showControlsOnInitialize: false,
          enableFullscreen: false,
          enablePip: false,
          enableQualities: false,
          enableSubtitles: false,
          enableSkips: false,
          enableMute: true,
          enablePlaybackSpeed: false,
          enableOverflowMenu: false,
          loadingColor: AppColors.accentYellow,
        ),
        errorBuilder: (context, _) => const SizedBox.shrink(),
      ),
      betterPlayerDataSource: dataSource,
    );

    controller.addEventsListener(_onPlayerEvent);

    setState(() {
      _controller = controller;
      _isInitializing = false;
    });
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (!mounted) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _attachVideoListener();
        break;
      case BetterPlayerEventType.exception:
        setState(() => _isError = true);
        FirebaseCrashlytics.instance.log(
          '⚠️ FloatingVideo exception: ${event.parameters}',
        );
        break;
      default:
        break;
    }
  }

  void _attachVideoListener() {
    _controller?.videoPlayerController
        ?.removeListener(_onVideoValueChanged);
    _controller?.videoPlayerController
        ?.addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _onVideoValueChanged() {
    if (!mounted) return;
    final v = _controller?.videoPlayerController?.value;
    if (v == null) return;
    setState(() => _isPlaying = v.isPlaying);
  }

  // ── Controls auto-hide ───────────────────────────────────────

  void _showControls() {
    _controlsTimer?.cancel();
    setState(() => _controlsVisible = true);
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  // ── Watermark ────────────────────────────────────────────────

  void _startWatermark() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final r = Random();
      setState(() {
        _watermarkAlignment = Alignment(
          (r.nextDouble() * 1.6) - 0.8,
          (r.nextDouble() * 1.6) - 0.8,
        );
      });
    });
  }

  // ── Dispose ──────────────────────────────────────────────────

  void _disposePlayer() {
    _controller?.videoPlayerController
        ?.removeListener(_onVideoValueChanged);
    _controlsTimer?.cancel();
    _watermarkTimer?.cancel();
    final c = _controller;
    _controller = null;
    c?.dispose(forceDispose: true);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fvc.removeListener(_onControllerChanged);
    _disposePlayer();
    super.dispose();
  }

  // ── Clamp position to screen bounds ─────────────────────────

  Offset _clampPosition(Offset pos, Size screen) {
    final maxX = screen.width - _width;
    final maxY = screen.height - _height - 24; // avoid nav bar
    return Offset(
      pos.dx.clamp(0.0, maxX),
      pos.dy.clamp(0.0, maxY),
    );
  }

  // ── Quality picker ───────────────────────────────────────────

  void _switchQuality(String q) {
    final url = _fvc.videoState?.streams[q];
    if (url == null || q == _currentQuality) return;
    setState(() => _currentQuality = q);
    try {
      _controller?.setResolution(url);
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, null, reason: 'FloatingVideo setResolution');
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    // On first build, snap to bottom-right
    if (_position == const Offset(16, 400)) {
      _position = Offset(
        screen.width - _width - widget.initialOffset.dx,
        screen.height - _height - widget.initialOffset.dy,
      );
    }

    return AnimatedPositioned(
      duration: _isDragging
          ? Duration.zero
          : const Duration(milliseconds: 120),
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        // ── Drag ──────────────────────────────────────────────
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (d) {
          setState(() {
            _position = _clampPosition(
              _position + d.delta,
              screen,
            );
          });
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        // ── Tap to toggle controls ────────────────────────────
        onTap: _showControls,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
              border: Border.all(
                color: AppColors.accentYellow.withOpacity(0.4),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // ── Video ────────────────────────────────────
                if (_controller != null && !_isError)
                  Positioned.fill(
                    child: BetterPlayer(controller: _controller!),
                  )
                else if (_isInitializing)
                  Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: AppColors.accentYellow,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else
                  Center(
                    child: Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 28),
                  ),

                // ── Watermark ────────────────────────────────
                if (_controller != null && !_isError)
                  Positioned.fill(
                    child: AnimatedAlign(
                      alignment: _watermarkAlignment,
                      duration: const Duration(seconds: 2),
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _fvc.videoState?.watermarkText ?? '',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Controls overlay ─────────────────────────
                if (_controlsVisible)
                  _buildControls(screen),

                // ── Resize handle (bottom-right) ──────────────
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        _width = (_width + d.delta.dx)
                            .clamp(_minW, _maxW);
                        // Re-clamp position so we don't go off-screen
                        _position =
                            _clampPosition(_position, screen);
                      });
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(10),
                        ),
                      ),
                      child: const Icon(
                        Icons.open_in_full,
                        color: Colors.white54,
                        size: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(Size screen) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
        ),
        child: Stack(
          children: [
            // ── Close button (top-right) ─────────────────────
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  _disposePlayer();
                  _fvc.stopFloating();
                },
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 14),
                ),
              ),
            ),

            // ── Title (top-left) ─────────────────────────────
            Positioned(
              top: 6,
              left: 6,
              right: 28,
              child: Text(
                _fvc.videoState?.title ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
            ),

            // ── Play / Pause ─────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: () {
                  if (_controller?.isPlaying() ?? false) {
                    _controller?.pause();
                  } else {
                    _controller?.play();
                  }
                  _showControls();
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),

            // ── Quality badge (bottom-left) ───────────────────
            if (_sortedQualities.length > 1)
              Positioned(
                bottom: 4,
                left: 4,
                child: GestureDetector(
                  onTap: () => _showQualityPicker(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppColors.accentYellow.withOpacity(0.5),
                          width: 0.8),
                    ),
                    child: Text(
                      _currentQuality,
                      style: TextStyle(
                        color: AppColors.accentYellow,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showQualityPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 3,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            ..._sortedQualities.map((q) => ListTile(
                  dense: true,
                  leading: Icon(
                    q == _currentQuality
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: q == _currentQuality
                        ? AppColors.accentYellow
                        : Colors.white54,
                    size: 18,
                  ),
                  title: Text(q,
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    _switchQuality(q);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
