import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ============================================================
// 🎬 FloatingVideoController — Singleton
// Manages the floating video player state across all screens.
// The video stream data is passed once from NativeVideoPlayerScreen
// and consumed by FloatingVideoOverlay wherever it is mounted.
// ============================================================

class FloatingVideoState {
  final Map<String, String> streams;
  final String title;
  final String watermarkText;

  /// Lesson/video ID for the current stream, if known. Threaded through so
  /// the full-screen player can re-fetch a fresh signed stream URL on retry
  /// after expanding back from the floating (PiP) player — see
  /// NativeVideoPlayerScreen.lessonId.
  final String? lessonId;

  /// Playback handoff info — lets the floating player (or the full-screen
  /// player) resume exactly where the other one left off, at the same
  /// speed and quality, instead of restarting from scratch.
  final Duration initialPosition;
  final double playbackSpeed;
  final String? initialQuality;
  final bool wasPlaying;

  const FloatingVideoState({
    required this.streams,
    required this.title,
    required this.watermarkText,
    this.lessonId,
    this.initialPosition = Duration.zero,
    this.playbackSpeed = 1.0,
    this.initialQuality,
    this.wasPlaying = true,
  });

  FloatingVideoState copyWith({
    Duration? initialPosition,
    double? playbackSpeed,
    String? initialQuality,
    bool? wasPlaying,
  }) {
    return FloatingVideoState(
      streams: streams,
      title: title,
      watermarkText: watermarkText,
      lessonId: lessonId,
      initialPosition: initialPosition ?? this.initialPosition,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      initialQuality: initialQuality ?? this.initialQuality,
      wasPlaying: wasPlaying ?? this.wasPlaying,
    );
  }
}

class FloatingVideoController extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────────
  static final FloatingVideoController instance = FloatingVideoController._();
  FloatingVideoController._();

  // ── State ────────────────────────────────────────────────────
  FloatingVideoState? _videoState;
  bool _isFloating = false;

  FloatingVideoState? get videoState => _videoState;
  bool get isFloating => _isFloating;
  bool get hasActiveVideo => _videoState != null;

  // ── Actions ──────────────────────────────────────────────────

  /// Called when the user taps "float" in NativeVideoPlayerScreen.
  /// Stores the stream data and signals that floating mode is active.
  /// [initialPosition], [playbackSpeed], [initialQuality] and [wasPlaying]
  /// carry the exact playback state over so the floating player resumes
  /// at the same point, speed and quality instead of restarting.
  void startFloating({
    required Map<String, String> streams,
    required String title,
    required String watermarkText,
    String? lessonId,
    Duration initialPosition = Duration.zero,
    double playbackSpeed = 1.0,
    String? initialQuality,
    bool wasPlaying = true,
  }) {
    _videoState = FloatingVideoState(
      streams: streams,
      title: title,
      watermarkText: watermarkText,
      lessonId: lessonId,
      initialPosition: initialPosition,
      playbackSpeed: playbackSpeed,
      initialQuality: initialQuality,
      wasPlaying: wasPlaying,
    );
    _isFloating = true;
    notifyListeners();
  }

  /// Updates the stored playback snapshot (position / speed / quality /
  /// playing state) without changing floating visibility. Used just before
  /// handing playback back to the full-screen player so it can resume
  /// exactly where the floating player left off.
  void updatePlaybackSnapshot({
    required Duration position,
    required double speed,
    required String quality,
    required bool isPlaying,
  }) {
    if (_videoState == null) return;
    _videoState = _videoState!.copyWith(
      initialPosition: position,
      playbackSpeed: speed,
      initialQuality: quality,
      wasPlaying: isPlaying,
    );
  }

  /// Called when the user dismisses the floating player or returns
  /// to the full-screen player.
  void stopFloating() {
    _isFloating = false;
    _videoState = null;
    notifyListeners();
  }

  /// Temporarily hides the floating overlay without destroying state.
  void hideOverlay() {
    if (_isFloating) {
      _isFloating = false;
      notifyListeners();
    }
  }

  /// Re-shows the overlay after [hideOverlay].
  void showOverlay() {
    if (_videoState != null && !_isFloating) {
      _isFloating = true;
      notifyListeners();
    }
  }
}
