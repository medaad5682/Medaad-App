import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// A drop-in replacement for `media_kit_video`'s `MaterialSeekBar`.
///
/// ROOT CAUSE FIXED:
/// The package's internal `MaterialSeekBarState.onPointerMove` /
/// `onPointerUp` read `State.context` without checking `mounted` first.
/// If the widget is disposed mid-drag (user drags then quickly exits the
/// screen, or the player is torn down while a pointer is still down),
/// that access throws "Null check operator used on a null value" as a
/// FATAL, unhandled exception.
///
/// This widget guards every pointer callback with `mounted` / disposal
/// checks before touching anything, and never reads `context` after a
/// gesture callback that could race with dispose(). It talks to the
/// player only through streams + direct method calls (no reliance on
/// package-internal state), so there is no equivalent crash surface.
class SafeSeekBar extends StatefulWidget {
  final Player player;

  /// Called when the user starts dragging / tapping the bar.
  /// Use this to pause auto-hide UI, acquire a seek-lock, etc.
  final VoidCallback? onSeekStart;

  /// Called when the user releases the bar with the final target position.
  final ValueChanged<Duration>? onSeekEnd;

  final Color activeColor;
  final Color inactiveColor;
  final Color bufferedColor;
  final Color thumbColor;

  const SafeSeekBar({
    super.key,
    required this.player,
    this.onSeekStart,
    this.onSeekEnd,
    this.activeColor = Colors.red,
    this.inactiveColor = const Color(0x4DFFFFFF), // white24
    this.bufferedColor = const Color(0x80FFFFFF), // white50
    this.thumbColor = Colors.red,
  });

  @override
  State<SafeSeekBar> createState() => _SafeSeekBarState();
}

class _SafeSeekBarState extends State<SafeSeekBar> {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;

  // Local drag state — never touches `context`.
  bool _dragging = false;
  double _dragFraction = 0.0;

  // Guards against callbacks firing after dispose() during a fast
  // navigate-away-while-dragging sequence (the exact scenario that used
  // to crash MaterialSeekBar).
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _buffered = widget.player.state.buffer;

    _positionSub = widget.player.stream.position.listen((p) {
      if (_disposed || !mounted) return;
      if (_dragging) return; // don't fight the user's finger
      setState(() => _position = p);
    });
    _durationSub = widget.player.stream.duration.listen((d) {
      if (_disposed || !mounted) return;
      setState(() => _duration = d);
    });
    _bufferSub = widget.player.stream.buffer.listen((b) {
      if (_disposed || !mounted) return;
      setState(() => _buffered = b);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    super.dispose();
  }

  double get _totalMs => _duration.inMilliseconds.toDouble();

  double _fractionFromLocalDx(double dx, double width) {
    if (width <= 0) return 0.0;
    return (dx / width).clamp(0.0, 1.0);
  }

  void _handleDragStart(DragStartDetails details, double width) {
    if (_disposed || !mounted || _totalMs <= 0) return;
    _dragging = true;
    _dragFraction =
        _fractionFromLocalDx(details.localPosition.dx, width);
    setState(() {});
    widget.onSeekStart?.call();
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    if (_disposed || !mounted || !_dragging || _totalMs <= 0) return;
    setState(() {
      _dragFraction =
          _fractionFromLocalDx(details.localPosition.dx, width);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_disposed || !mounted) return;
    if (!_dragging) return;
    final target = Duration(
        milliseconds: (_dragFraction * _totalMs).round());
    _dragging = false;
    // Update local position immediately for a snappy feel; the real
    // position stream will confirm it shortly after.
    setState(() => _position = target);
    // Fire-and-forget: player.seek is async but we never await inside
    // a gesture callback tied to widget lifetime.
    widget.player.seek(target).catchError((_) {
      // Swallow — a failed seek here is not worth crashing over or
      // spamming Crashlytics; the position stream will resync.
    });
    widget.onSeekEnd?.call(target);
  }

  void _handleTapUp(TapUpDetails details, double width) {
    if (_disposed || !mounted || _totalMs <= 0) return;
    final fraction = _fractionFromLocalDx(details.localPosition.dx, width);
    final target =
        Duration(milliseconds: (fraction * _totalMs).round());
    widget.onSeekStart?.call();
    setState(() => _position = target);
    widget.player.seek(target).catchError((_) {});
    widget.onSeekEnd?.call(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final playedFraction = _dragging
            ? _dragFraction
            : (_totalMs <= 0
                ? 0.0
                : (_position.inMilliseconds / _totalMs).clamp(0.0, 1.0));
        final bufferedFraction = _totalMs <= 0
            ? 0.0
            : (_buffered.inMilliseconds / _totalMs).clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _handleDragStart(d, width),
          onHorizontalDragUpdate: (d) => _handleDragUpdate(d, width),
          onHorizontalDragEnd: _handleDragEnd,
          onHorizontalDragCancel: () {
            if (_disposed || !mounted) return;
            setState(() => _dragging = false);
          },
          onTapUp: (d) => _handleTapUp(d, width),
          child: SizedBox(
            height: 28,
            width: double.infinity,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // Track (inactive)
                  Container(
                    height: 3,
                    width: width,
                    decoration: BoxDecoration(
                      color: widget.inactiveColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Buffered
                  Container(
                    height: 3,
                    width: width * bufferedFraction,
                    decoration: BoxDecoration(
                      color: widget.bufferedColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Played
                  Container(
                    height: 3,
                    width: width * playedFraction,
                    decoration: BoxDecoration(
                      color: widget.activeColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Thumb
                  Positioned(
                    left: (width * playedFraction - 6).clamp(0.0, width - 12),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: widget.thumbColor,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 3,
                              offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
