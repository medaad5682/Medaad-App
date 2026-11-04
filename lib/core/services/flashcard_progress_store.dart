import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'storage_service.dart';

/// 💾 تقدم الطالب في الفلاش كاردس — محلي بالكامل (Hive)، لا شيء يُحفظ على السيرفر.
///
/// - صندوق مشفّر مستقل عبر `StorageService.openBox` (نفس نمط بقية الصناديق).
/// - مفاتيح التقدم لكل **مستخدم ومجموعة** (`known:<userId>:<deckId>`) فيبقى تقدم حسابين على نفس
///   الهاتف منفصلاً، وتسجيل الخروج (الذي يمسح auth_box فقط) لا يمسح التقدم.
/// - المخزَّن: معرّفات البطاقات المعروفة فقط. البطاقة التي حذفها المعلم تُنظَّف عند تحميل المجموعة
///   (pruneToCards)، والبطاقة الجديدة تظهر «غير مدروسة» تلقائياً، وتعديل نص البطاقة يُبقي id فيبقى التقدم.
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

  static String _knownKey(String userId, int deckId) => 'known:$userId:$deckId';
  static String _hintKey(String userId) => 'swipe_hint_shown:$userId';

  static Future<Box> _box() => StorageService.openBox(boxName);

  // ───────────────────────── المعروف ─────────────────────────

  static Future<Set<int>> getKnownIds(int deckId) async {
    final box = await _box();
    final userId = await currentUserId();
    final raw = box.get(_knownKey(userId, deckId));
    if (raw is List) {
      return raw.map((e) => e is int ? e : int.tryParse('$e')).whereType<int>().toSet();
    }
    return <int>{};
  }

  static Future<void> _save(int deckId, Set<int> ids) async {
    final box = await _box();
    final userId = await currentUserId();
    final key = _knownKey(userId, deckId);
    if (ids.isEmpty) {
      await box.delete(key);
    } else {
      final list = ids.toList()..sort();
      await box.put(key, list);
    }
  }

  /// يعلّم البطاقة «عرفتها» (known=true) أو «ما زلت أتعلمها» (known=false).
  static Future<Set<int>> setKnown(int deckId, int cardId, bool known) async {
    final ids = await getKnownIds(deckId);
    if (known) {
      ids.add(cardId);
    } else {
      ids.remove(cardId);
    }
    await _save(deckId, ids);
    return ids;
  }

  /// يحذف من التقدم أي بطاقة لم تعد موجودة في المجموعة (حذفها المعلم). يرجع المجموعة بعد التنظيف.
  static Future<Set<int>> pruneToCards(int deckId, Iterable<int> validCardIds) async {
    final ids = await getKnownIds(deckId);
    final valid = validCardIds.toSet();
    final pruned = ids.intersection(valid);
    if (pruned.length != ids.length) await _save(deckId, pruned);
    return pruned;
  }

  /// عدد المعروف لشريط التقدم على بطاقة المجموعة. cardCount من السيرفر (مصدر الحقيقة للعدد الكلي)،
  /// والناتج لا يتجاوزه حتى لو بقيت معرّفات قديمة لم تُنظَّف بعد.
  static Future<int> knownCount(int deckId, int cardCount) async {
    final n = (await getKnownIds(deckId)).length;
    return n > cardCount ? cardCount : n;
  }

  /// إعادة ضبط تقدم المجموعة (زر «إعادة ضبط» على بطاقة المجموعة).
  static Future<void> resetDeck(int deckId) => _save(deckId, <int>{});

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
