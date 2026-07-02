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

  const FloatingVideoState({
    required this.streams,
    required this.title,
    required this.watermarkText,
  });
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
  void startFloating({
    required Map<String, String> streams,
    required String title,
    required String watermarkText,
  }) {
    _videoState = FloatingVideoState(
      streams: streams,
      title: title,
      watermarkText: watermarkText,
    );
    _isFloating = true;
    notifyListeners();
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
