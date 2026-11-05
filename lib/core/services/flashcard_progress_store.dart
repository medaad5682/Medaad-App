import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart' show Box;

import 'flashcard_leitner.dart';
import 'storage_service.dart';

/// 💾 تقدم الطالب في الفلاش كاردس — محلي بالكامل (Hive)، لا شيء يُحفظ على السيرفر.
///
/// - صندوق مشفّر مستقل عبر `StorageService.openBox` (نفس نمط بقية الصناديق).
/// - المفاتيح لكل **مستخدم ومجموعة** فيبقى تقدم حسابين على نفس الهاتف منفصلاً،
///   وتسجيل الخروج (الذي يمسح auth_box فقط) لا يمسح التقدم.
///
/// ## Step 19 — نظام لايتنر
/// بدل قائمة المعروف (`known:<userId>:<deckId>`) صار لكل بطاقة سجل مستقل
/// `{cardId, box, dueDate}` في المفتاح `leitner:<userId>:<deckId>` (JSON).
///
/// - البطاقة **بلا سجل** = جديدة لم تُدرَس (الصندوق 1، مستحقة فوراً).
///   لذلك البطاقة الجديدة التي يضيفها المعلم تظهر مستحقة تلقائياً.
/// - البطاقة المحذوفة تُنظَّف عند تحميل المجموعة ([pruneToCards]).
/// - تعديل نص البطاقة يُبقي id فيبقى تقدمها.
/// - **الهجرة** تلقائية وعند أول قراءة: كل بطاقة كانت «معروفة» ⇒ الصندوق 3 وأول موعد بعد 3 أيام،
///   وغير المعروفة تبقى بلا سجل (الصندوق 1 ومستحقة فوراً). ثم يُحذف المفتاح القديم.
/// - كل العمليات تُنفَّذ بالتسلسل (قفل داخلي) فلا يتداخل ترحيل مع كتابة تقييم.
class FlashcardProgressStore {
  FlashcardProgressStore._();

  static const String boxName = 'flashcard_progress_box';
  static const String _guestId = 'guest';

  /// معرّف المستخدم الحالي كما يحفظه تسجيل الدخول (auth_box/user_id).
  static Future<String> currentUserId() async {
    try {
      final box = await StorageService.openBox('auth_box');
      final id = box.get('user_id');
      if (id != null && id.toString().isNotEmpty) return id.toString();
    } catch (_) {}
    return _guestId;
  }

  static String _legacyKnownKey(String userId, int deckId) => 'known:$userId:$deckId';
  static String _progressKey(String userId, int deckId) => 'leitner:$userId:$deckId';
  static String _hintKey(String userId) => 'swipe_hint_shown:$userId';

  static Future<Box> _box() => StorageService.openBox(boxName);

  // ───────────────────────── قفل التسلسل ─────────────────────────

  static Future<void> _tail = Future<void>.value();

  /// ينفّذ [action] بعد انتهاء كل ما سبقه (قراءة/كتابة/هجرة لا تتداخل أبداً).
  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _tail;
    _tail = completer.future.then<void>((_) {}, onError: (_) {});
    previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  // ───────────────────────── القراءة/الكتابة (بدون قفل) ─────────────────────────

  /// يقرأ سجلات المجموعة، ويهاجر القائمة القديمة إن وُجدت. لا يستدعى إلا داخل [_synchronized].
  static Future<Map<int, FlashcardCardProgress>> _read(int deckId) async {
    final box = await _box();
    final userId = await currentUserId();
    final key = _progressKey(userId, deckId);
    final today = FlashcardLeitner.today();

    final raw = box.get(key);
    if (raw is String) {
      return _decode(raw, today);
    }

    // لا سجلات جديدة ⇒ هل توجد قائمة «معروفة» قديمة للهجرة؟
    final legacyKey = _legacyKnownKey(userId, deckId);
    final legacy = box.get(legacyKey);
    if (legacy == null) return <int, FlashcardCardProgress>{};

    final migrated = <int, FlashcardCardProgress>{};
    if (legacy is List) {
      for (final e in legacy) {
        final id = e is int ? e : (e is num ? e.toInt() : int.tryParse('$e'));
        if (id != null) migrated[id] = FlashcardLeitner.migratedKnown(id, today);
      }
    }
    // نكتب الجديد أولاً ثم نحذف القديم: لو انقطعت العملية بينهما تُعاد الهجرة بنفس النتيجة.
    if (migrated.isNotEmpty) {
      await box.put(key, _encode(migrated));
    }
    await box.delete(legacyKey);
    return migrated;
  }

  static Future<void> _write(int deckId, Map<int, FlashcardCardProgress> records) async {
    final box = await _box();
    final userId = await currentUserId();
    final key = _progressKey(userId, deckId);
    if (records.isEmpty) {
      await box.delete(key);
    } else {
      await box.put(key, _encode(records));
    }
  }

  static String _encode(Map<int, FlashcardCardProgress> records) {
    final list = records.values.toList()..sort((a, b) => a.cardId.compareTo(b.cardId));
    return jsonEncode(list.map((p) => p.toJson()).toList());
  }

  static Map<int, FlashcardCardProgress> _decode(String raw, DateTime today) {
    final out = <int, FlashcardCardProgress>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          final p = FlashcardCardProgress.fromJson(item, today);
          if (p != null) out[p.cardId] = p;
        }
      }
    } catch (_) {
      // سجل تالف ⇒ نبدأ نظيفاً بدل كسر الدراسة
    }
    return out;
  }

  // ───────────────────────── الواجهة العامة ─────────────────────────

  /// كل سجلات المجموعة (بعد الهجرة التلقائية إن لزم). البطاقة الغائبة = جديدة.
  static Future<Map<int, FlashcardCardProgress>> loadProgress(int deckId) =>
      _synchronized(() => _read(deckId));

  /// يحفظ سجل بطاقة واحدة (يستبدل سجلها فقط ولا يلمس غيرها).
  static Future<void> saveCardProgress(int deckId, FlashcardCardProgress progress) =>
      _synchronized(() async {
        final records = await _read(deckId);
        records[progress.cardId] = progress;
        await _write(deckId, records);
      });

  /// يحذف من التقدم أي بطاقة لم تعد موجودة في المجموعة (حذفها المعلم). يرجع السجلات بعد التنظيف.
  static Future<Map<int, FlashcardCardProgress>> pruneToCards(
    int deckId,
    Iterable<int> validCardIds,
  ) =>
      _synchronized(() async {
        final records = await _read(deckId);
        final valid = validCardIds.toSet();
        final before = records.length;
        records.removeWhere((id, _) => !valid.contains(id));
        if (records.length != before) await _write(deckId, records);
        return records;
      });

  /// معرّفات البطاقات «المعروفة» (الصناديق 3/4/5) — تبقي «غير المعروفة فقط» وملخص الجولة يعملان.
  static Future<Set<int>> getKnownIds(int deckId) async {
    final records = await loadProgress(deckId);
    return records.values.where((p) => p.isKnown).map((p) => p.cardId).toSet();
  }

  /// أرقام بطاقة المجموعة. [cardCount] من السيرفر (مصدر الحقيقة للعدد الكلي).
  /// [validCardIds] إن توفرت (من الكاش المحدّث) تُستبعد سجلات البطاقات المحذوفة بدقة؛
  /// وإلا نكتفي بسقف [cardCount] حتى تُنظَّف السجلات عند فتح المجموعة.
  static Future<FlashcardDeckStats> deckStats(
    int deckId,
    int cardCount, {
    Iterable<int>? validCardIds,
  }) async {
    var records = (await loadProgress(deckId)).values.toList();
    if (validCardIds != null) {
      final valid = validCardIds.toSet();
      records = records.where((p) => valid.contains(p.cardId)).toList();
    }
    final today = FlashcardLeitner.today();

    final newCount = cardCount > records.length ? cardCount - records.length : 0;
    final dueRecords = records.where((p) => FlashcardLeitner.isDue(p, today)).length;
    final due = (newCount + dueRecords).clamp(0, cardCount).toInt();
    final mastered = records.where((p) => p.isMastered).length.clamp(0, cardCount).toInt();
    final known = records.where((p) => p.isKnown).length.clamp(0, cardCount).toInt();

    return FlashcardDeckStats(
      total: cardCount,
      due: due,
      mastered: mastered,
      known: known,
      hasProgress: records.isNotEmpty,
      nextReviewInDays: due == 0 ? FlashcardLeitner.nextReviewInDays(records, today) : null,
    );
  }

  /// إعادة ضبط تقدم المجموعة على هذا الجهاز: تُمسح كل الصناديق والمواعيد فتصبح كل البطاقات جديدة.
  static Future<void> resetDeck(int deckId) => _synchronized(() async {
        await _write(deckId, <int, FlashcardCardProgress>{});
        // احتياطاً: لو بقي مفتاح قديم لم يُهاجَر فلا يُعاد إحياؤه بعد الإعادة
        final box = await _box();
        final userId = await currentUserId();
        await box.delete(_legacyKnownKey(userId, deckId));
      });

  // ───────────────────────── تلميح السحب ─────────────────────────

  static Future<bool> hasSeenSwipeHint() async {
    final box = await _box();
    final userId = await currentUserId();
    return box.get(_hintKey(userId)) == true;
  }

  static Future<void> markSwipeHintSeen() async {
    final box = await _box();
    final userId = await currentUserId();
    await box.put(_hintKey(userId), true);
  }
}
