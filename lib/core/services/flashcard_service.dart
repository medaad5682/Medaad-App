import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import '../constants/api_constants.dart';
import '../../data/models/flashcard_model.dart';
import 'api_client.dart';
import 'flashcard_progress_store.dart';
import 'storage_service.dart';

/// سبب فشل تحميل مجموعة.
enum FlashcardFailure {
  /// لا إنترنت/مهلة ولا توجد نسخة مخزّنة.
  offline,

  /// 403 reason=expired
  expired,

  /// 403 reason=not_owned
  notOwned,

  /// 404 (حُذفت أو أُخفيت)
  notFound,

  /// 401 (توكن/جهاز غير صالح)
  unauthorized,

  server,
}

class FlashcardException implements Exception {
  final FlashcardFailure failure;
  final String? message;
  FlashcardException(this.failure, [this.message]);

  @override
  String toString() => 'FlashcardException($failure${message != null ? ': $message' : ''})';
}

/// 🗂️ جلب مجموعات الفلاش كاردس وتخزينها للدراسة بدون إنترنت (Step 12).
///
/// منطق التحميل `loadDeck`:
///  1) نسخة مخزّنة + نفس `updated_at` القادم من قائمة المادة ⇒ تُستخدم مباشرة بلا طلب شبكة.
///  2) وإلا نجلب من السيرفر ونحدّث الكاش وننظّف تقدم البطاقات المحذوفة.
///  3) فشل الشبكة (لا إنترنت/مهلة/خطأ سيرفر) ⇒ نرجع النسخة المخزّنة إن وُجدت، وإلا استثناء offline.
///  4) 403/404 ⇒ نحذف النسخة المخزّنة (انتهى الاشتراك أو أُخفيت/حُذفت المجموعة) ونرمي استثناءً مناسباً.
///
/// الكاش **لكل مستخدم** (`deck:<userId>:<deckId>`) فلا يقرأ حساب آخر على نفس الهاتف محتوى لم يشترِ به.
class FlashcardService {
  FlashcardService._();

  static const String cacheBoxName = 'flashcard_cache_box';

  static String _cacheKey(String userId, int deckId) => 'deck:$userId:$deckId';

  static Future<Box> _box() => StorageService.openBox(cacheBoxName);

  // ───────────────────────── الكاش ─────────────────────────

  static Future<FlashcardDeckModel?> getCachedDeck(int deckId) async {
    try {
      final box = await _box();
      final userId = await FlashcardProgressStore.currentUserId();
      final raw = box.get(_cacheKey(userId, deckId));
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return FlashcardDeckModel.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null; // كاش تالف ⇒ نتجاهله ونجلب من السيرفر
    }
  }

  static Future<void> _cacheDeck(FlashcardDeckModel deck) async {
    try {
      final box = await _box();
      final userId = await FlashcardProgressStore.currentUserId();
      await box.put(_cacheKey(userId, deck.id), jsonEncode(deck.toJson()));
    } catch (_) {
      // فشل الكتابة لا يمنع الدراسة في الجلسة الحالية
    }
  }

  static Future<void> removeCachedDeck(int deckId) async {
    try {
      final box = await _box();
      final userId = await FlashcardProgressStore.currentUserId();
      await box.delete(_cacheKey(userId, deckId));
    } catch (_) {}
  }

  /// هل المجموعة مخزّنة ومحدّثة (تطابق updated_at)؟ مفيد لإظهار علامة «متاحة بدون إنترنت».
  static Future<bool> isCachedAndFresh(int deckId, String? serverUpdatedAt) async {
    final cached = await getCachedDeck(deckId);
    return cached != null && serverUpdatedAt != null && cached.updatedAt == serverUpdatedAt;
  }

  // ───────────────────────── التحميل ─────────────────────────

  /// [serverUpdatedAt]: قيمة updated_at من قائمة المادة (FlashcardDeckSummary.updatedAt) إن توفرت.
  /// [forceRefresh]: تجاهل الكاش وإجبار الجلب من السيرفر.
  static Future<FlashcardDeckModel> loadDeck(
    int deckId, {
    String? serverUpdatedAt,
    bool forceRefresh = false,
  }) async {
    final cached = await getCachedDeck(deckId);

    if (!forceRefresh &&
        cached != null &&
        serverUpdatedAt != null &&
        cached.updatedAt == serverUpdatedAt) {
      await FlashcardProgressStore.pruneToCards(deckId, cached.cardIds);
      return cached;
    }

    try {
      final res = await ApiClient.instance.get(
        '${ApiConstants.baseUrl}/api/flashcards/get-deck',
        queryParameters: {'deckId': deckId},
      );
      final data = res.data;
      if (data is! Map) {
        throw FlashcardException(FlashcardFailure.server, 'Invalid response');
      }
      final deck = FlashcardDeckModel.fromJson(Map<String, dynamic>.from(data));
      await _cacheDeck(deck);
      await FlashcardProgressStore.pruneToCards(deckId, deck.cardIds);
      return deck;
    } on FlashcardException {
      rethrow;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      if (status == 403) {
        final body = e.response?.data;
        final reason = body is Map ? body['reason']?.toString() : null;
        await removeCachedDeck(deckId);
        throw FlashcardException(
          reason == 'expired' ? FlashcardFailure.expired : FlashcardFailure.notOwned,
        );
      }
      if (status == 404) {
        await removeCachedDeck(deckId);
        throw FlashcardException(FlashcardFailure.notFound);
      }
      if (status == 401) {
        throw FlashcardException(FlashcardFailure.unauthorized);
      }

      // لا رد من السيرفر (لا إنترنت/مهلة) أو خطأ 5xx ⇒ نستخدم النسخة المخزّنة إن وُجدت
      if (cached != null) {
        await FlashcardProgressStore.pruneToCards(deckId, cached.cardIds);
        return cached;
      }
      final noResponse = status == null;
      throw FlashcardException(noResponse ? FlashcardFailure.offline : FlashcardFailure.server);
    } catch (e) {
      if (cached != null) return cached;
      throw FlashcardException(FlashcardFailure.server, e.toString());
    }
  }
}
