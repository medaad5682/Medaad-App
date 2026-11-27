import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_state.dart';
import 'storage_service.dart';

// ============================================================
// 🎬 VideoProgressService — Singleton
//
// بيحفظ آخر نقطة وصل لها الطالب في كل فيديو، عشان لو قفل الفيديو (أو
// التطبيق) ورجع يفتحه تاني يكمّل من نفس المكان.
//
// • مشترك بين كل المشغّلات: VideoPlayerScreen (media_kit)،
//   NativeVideoPlayerScreen (better_player)، YoutubePlayerScreen،
//   وFloatingVideoOverlay.
// • التخزين محلي على الجهاز في صندوق Hive مشفّر بـ AES (نفس آلية
//   StorageService.openBox المستخدمة في auth_box وغيره)، ومفصول لكل
//   مستخدم، فلو أكتر من طالب سجّلوا دخول على نفس الجهاز كل واحد له تقدّمه.
// • الكتابة على القرص بتتم بحد أقصى مرة كل 5 ثواني (throttle) أثناء
//   التشغيل، وفورًا (force) عند الخروج من المشغّل أو دخول التطبيق للخلفية.
// ============================================================
class VideoProgressService {
  VideoProgressService._();
  static final VideoProgressService instance = VideoProgressService._();

  /// أقل موضع يستاهل الحفظ/الاستئناف. أي موضع أقل من كده بنتجاهله
  /// (الفيديو لسه في أوله، ومفيش داعي نرجّع الطالب لثواني قليلة).
  static const Duration minSavePosition = Duration(seconds: 5);

  /// لو فاضل على نهاية الفيديو أقل من المدة دي نعتبره «خلّص»، ونمسح
  /// التقدّم المحفوظ عشان المشاهدة الجاية تبدأ من الأول.
  static const Duration completionThreshold = Duration(seconds: 10);

  /// بنرجّع الطالب ثانيتين قبل نقطة التوقف عشان يلحق السياق.
  static const Duration resumeRewind = Duration(seconds: 2);

  static const Duration _writeInterval = Duration(seconds: 5);
  static const String _boxName = 'video_progress_box';
  static const String _prefix = 'video_progress_v1';

  /// ✅ مفتاح لكل مشغّل: كل مشغّل بيحتفظ بتقدّمه الخاص حتى لو نفس الدرس
  /// اتفتح بأكتر من مشغّل (قبل كده media_kit والـ native كانوا بيشاركوا نفس
  /// المفتاح، فالـ native كان بيكمّل من تقدّم media_kit).
  ///   mk:     VideoPlayerScreen (media_kit) — أونلاين وأوفلاين وExplode
  ///   native: NativeVideoPlayerScreen + النافذة العائمة (تابعة له)
  ///   yt:     YoutubePlayerScreen
  static String mediaKitKey(String lessonId) => 'mk:$lessonId';
  static String nativeKey(String lessonId) => 'native:$lessonId';
  static String youtubeKey(String videoId) => 'yt:$videoId';

  Box? _box;
  final Map<String, _ProgressEntry> _memory = {};
  final Map<String, DateTime> _lastWrite = {};

  /// بيفتح الصندوق المشفّر عبر StorageService (نفس المفتاح والتعامل مع
  /// التلف/تعذّر المفتاح). لو فشل نرجّع null ونكمّل بدون حفظ بدل ما نكسر
  /// المشغّل، ومنخزّنش الفشل عشان المحاولة الجاية تجرّب تاني.
  Future<Box?> _getBox() async {
    final cached = _box;
    if (cached != null && cached.isOpen) return cached;
    try {
      _box = await StorageService.openBox(_boxName);
    } catch (e) {
      debugPrint('⚠️ VideoProgressService: encrypted box unavailable: $e');
      _box = null;
    }
    return _box;
  }

  String _currentUserId() {
    try {
      final fromState = AppState().userData?['id'];
      if (fromState != null && fromState.toString().isNotEmpty) {
        return fromState.toString();
      }
    } catch (_) {}
    try {
      if (Hive.isBoxOpen('auth_box')) {
        final fromBox = Hive.box('auth_box').get('user_id');
        if (fromBox != null && fromBox.toString().isNotEmpty) {
          return fromBox.toString();
        }
      }
    } catch (_) {}
    return 'anon';
  }

  String _storageKey(String key) => '$_prefix:${_currentUserId()}:$key';

  /// يرجّع الموضع اللي المفروض يكمّل منه الفيديو، أو null لو مفيش تقدّم
  /// محفوظ يستاهل الاستئناف (أو الفيديو كان خلّص).
  Future<Duration?> getResumePosition(String? key) async {
    if (key == null || key.isEmpty) return null;
    try {
      final sk = _storageKey(key);

      _ProgressEntry? entry = _memory[sk];
      if (entry == null) {
        final box = await _getBox();
        final raw = box?.get(sk);
        entry = _ProgressEntry.tryParse(raw is String ? raw : null);
      }
      if (entry == null) return null;

      if (entry.position < minSavePosition) return null;
      if (entry.duration > Duration.zero &&
          entry.duration - entry.position <= completionThreshold) {
        return null;
      }

      final target = entry.position - resumeRewind;
      return target.isNegative ? Duration.zero : target;
    } catch (e) {
      debugPrint('⚠️ VideoProgressService.getResumePosition: $e');
      return null;
    }
  }

  /// يسجّل موضع التشغيل الحالي. آمن للاستدعاء بتكرار عالي (كل tick من
  /// المشغّل) — الكتابة الفعلية على القرص متقيّدة بـ [_writeInterval]
  /// إلا لو [force] = true (عند الخروج / الخلفية).
  void update(
    String? key,
    Duration position,
    Duration? duration, {
    bool force = false,
  }) {
    if (key == null || key.isEmpty) return;
    if (position < minSavePosition) return;

    try {
      final sk = _storageKey(key);
      final total = duration ?? Duration.zero;

      // الفيديو قرّب يخلّص (أو خلّص) → امسح التقدّم.
      if (total > Duration.zero && total - position <= completionThreshold) {
        _memory.remove(sk);
        _lastWrite.remove(sk);
        unawaited(_remove(sk));
        return;
      }

      final entry = _ProgressEntry(position, total);
      _memory[sk] = entry;

      final now = DateTime.now();
      final last = _lastWrite[sk];
      if (force || last == null || now.difference(last) >= _writeInterval) {
        _lastWrite[sk] = now;
        unawaited(_write(sk, entry));
      }
    } catch (e) {
      debugPrint('⚠️ VideoProgressService.update: $e');
    }
  }

  /// يمسح التقدّم المحفوظ لفيديو معيّن (للاستخدام اليدوي لو احتجته).
  Future<void> clear(String? key) async {
    if (key == null || key.isEmpty) return;
    final sk = _storageKey(key);
    _memory.remove(sk);
    _lastWrite.remove(sk);
    await _remove(sk);
  }

  Future<void> _write(String sk, _ProgressEntry entry) async {
    try {
      final box = await _getBox();
      await box?.put(sk, entry.encode());
    } catch (e) {
      debugPrint('⚠️ VideoProgressService write failed: $e');
    }
  }

  Future<void> _remove(String sk) async {
    try {
      final box = await _getBox();
      await box?.delete(sk);
    } catch (e) {
      debugPrint('⚠️ VideoProgressService remove failed: $e');
    }
  }
}

class _ProgressEntry {
  final Duration position;
  final Duration duration;
  const _ProgressEntry(this.position, this.duration);

  String encode() => '${position.inMilliseconds}:${duration.inMilliseconds}';

  static _ProgressEntry? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final pos = int.tryParse(parts[0]);
    final dur = int.tryParse(parts[1]);
    if (pos == null || dur == null || pos < 0 || dur < 0) return null;
    return _ProgressEntry(
      Duration(milliseconds: pos),
      Duration(milliseconds: dur),
    );
  }
}
