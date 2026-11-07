import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'storage_service.dart';

// ============================================================
// 🔒 حدّ الدخول بدون إنترنت (Offline Entry Limit)
// ============================================================
// الهدف: التحميلات المحفوظة على الجهاز لا تُنظَّف من الصلاحيات الملغاة إلا
// عند رد ناجح من السيرفر (get-app-init-data → validateAndCleanRevokedDownloads).
// في وضع عدم الاتصال يُقرأ الكاش القديم فقط، فلو سُحبت صلاحية الطالب لا
// يعرف التطبيق. لذلك نسمح بعدد محدود من الدخولات أوفلاين ([maxOfflineEntries])،
// وبعدها نشترط اتصالاً واحداً ناجحاً بالسيرفر يُعيد العدّاد للصفر
// (فيتم أثناءه تنظيف أي تحميلات ملغاة).
//
// التعريف المعتمد لـ"دخول أوفلاين": إقلاع للتطبيق (SplashScreen) فشل فيه
// طلب get-app-init-data وانتقل التطبيق لوضع عدم الاتصال.
//
// العدّاد محفوظ داخل auth_box (صندوق Hive المشفّر) فلا يمكن للمستخدم
// تعديله، ولا يعتمد على ساعة الجهاز إطلاقاً (تغيير التاريخ لا يفيد).
class OfflineEntryResult {
  /// هل يُسمح بالدخول أوفلاين؟
  final bool allowed;

  /// عدد مرات الدخول المتبقية *بعد* احتساب هذا الدخول (0 = هذا آخر دخول).
  /// null = تعذّر قراءة/كتابة العدّاد (نسمح بالدخول بدون عرض رقم).
  final int? remaining;

  /// الحد الأقصى الكلي.
  final int max;

  const OfflineEntryResult({
    required this.allowed,
    required this.remaining,
    required this.max,
  });

  bool get isLastEntry => allowed && remaining == 0;
}

class OfflineAccessGuard {
  OfflineAccessGuard._();
  static final OfflineAccessGuard instance = OfflineAccessGuard._();

  /// ⚙️ الحد الأقصى لمرات الدخول أوفلاين قبل اشتراط الاتصال بالإنترنت.
  static const int maxOfflineEntries = 5;

  static const String _kUsedKey = 'offline_entries_used_v1';

  // 🔁 RestartWidget (تغيير اللغة/الثيم) يُعيد بناء التطبيق كله ويُشغّل
  // SplashScreen من جديد داخل *نفس العملية*. هذا ليس "دخولاً" جديداً، فلا
  // نحتسبه مرة ثانية: نتذكّر في الذاكرة (وليس في التخزين) أننا احتسبنا هذه
  // الجلسة. تُصفَّر عند أي مزامنة ناجحة أو عند إقلاع جديد للعملية.
  bool _sessionCounted = false;
  int _sessionRemaining = maxOfflineEntries;

  int _readUsed(Box box) {
    if (!box.containsKey(_kUsedKey)) return 0;
    final raw = box.get(_kUsedKey);
    if (raw is int && raw >= 0) return raw;
    // قيمة غير سليمة (تلف/عبث) → نعتبر الحد مستنفداً بدل فتح الباب.
    return maxOfflineEntries;
  }

  /// تُستدعى عند الدخول في وضع عدم الاتصال (قبل تحميل أي بيانات مخبأة).
  /// - إن كان المتبقي > 0: تحتسب دخولاً وتُرجع allowed=true مع المتبقي.
  /// - إن استُنفد الحد: تُرجع allowed=false ولا تُغيّر شيئاً.
  Future<OfflineEntryResult> consumeEntry() async {
    if (_sessionCounted) {
      return OfflineEntryResult(
        allowed: true,
        remaining: _sessionRemaining,
        max: maxOfflineEntries,
      );
    }

    try {
      final box = await StorageService.openBox('auth_box');
      final used = _readUsed(box);

      if (used >= maxOfflineEntries) {
        return const OfflineEntryResult(
          allowed: false,
          remaining: 0,
          max: maxOfflineEntries,
        );
      }

      final newUsed = used + 1;
      await box.put(_kUsedKey, newUsed);

      _sessionCounted = true;
      _sessionRemaining = maxOfflineEntries - newUsed;

      return OfflineEntryResult(
        allowed: true,
        remaining: _sessionRemaining,
        max: maxOfflineEntries,
      );
    } catch (e, st) {
      // الصندوق مفتوح أصلاً عند هذه النقطة (SplashScreen قرأت منه للتو)،
      // فهذا الفرع نادر جداً. لا نحبس مستخدماً بسبب خلل تخزين عابر: نسمح
      // بالدخول ونسجّل الحدث، بدون عرض رقم.
      debugPrint('⚠️ OfflineAccessGuard.consumeEntry failed: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'OfflineAccessGuard.consumeEntry failed (entry allowed)',
        fatal: false,
      );
      return const OfflineEntryResult(
        allowed: true,
        remaining: null,
        max: maxOfflineEntries,
      );
    }
  }

  /// تُستدعى فقط بعد رد ناجح فعلاً من السيرفر (200 + success) لإعادة العدّاد
  /// إلى الحد الكامل. لا ترمي أبداً.
  Future<void> resetOnSuccessfulSync() async {
    _sessionCounted = false;
    _sessionRemaining = maxOfflineEntries;

    try {
      final box = await StorageService.openBox('auth_box');
      if (box.containsKey(_kUsedKey)) {
        await box.delete(_kUsedKey);
      }
    } catch (e, st) {
      debugPrint('⚠️ OfflineAccessGuard.resetOnSuccessfulSync failed: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'OfflineAccessGuard.resetOnSuccessfulSync failed',
        fatal: false,
      );
    }
  }
}
