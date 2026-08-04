import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ [FIX] يُرمى عندما نعلم أن مفتاح التشفير تم إنشاؤه مسبقاً على هذا
/// الجهاز، لكن لا يمكن قراءته حالياً من Keychain/Keystore (خطأ عابر في
/// قناة الاتصال الأصلية، وليس عدم وجود المفتاح فعلياً). هذا الاستثناء
/// مميّز عمداً حتى لا تتعامل openBox() مع هذه الحالة كتلف بيانات وتحذف
/// الصندوق — فالبيانات سليمة، المفتاح فقط غير قابل للقراءة مؤقتاً.
class StorageKeyUnavailableException implements Exception {
  final String message;
  StorageKeyUnavailableException(this.message);
  @override
  String toString() => 'StorageKeyUnavailableException: $message';
}

class StorageService {
  // التخزين الآمن للمفاتيح فقط
  static const _secureStorage = FlutterSecureStorage();
  static List<int>? _encryptionKey;

  // ✅ [FIX] علم دائم (يبقى عبر تحديثات التطبيق، ويُمسح فقط عند إلغاء
  // التثبيت) يسجّل أننا سبق ونجحنا في توفير hive_key على هذا الجهاز.
  // هذا هو الفيصل الوحيد الموثوق لمعرفة: هل هذا أول تشغيل فعلاً (لا يوجد
  // مفتاح بعد)، أم أن المفتاح موجود لكن قراءته فشلت مؤقتاً؟
  static const String _kKeyProvisionedFlag = 'storage_service_key_provisioned_v1';

  /// ✅ [FIX] محاولة قراءة hive_key من Keychain/Keystore مع إعادة محاولة
  /// (retry with backoff) بدل الاستسلام من أول فشل. الفشل هنا قد يكون
  /// null عابر أو PlatformException عابر (شائع خصوصاً في اللحظات الأولى
  /// بعد تحديث App Store، أو قبل أول فتح قفل للجهاز بعد إعادة تشغيله).
  static Future<String?> _readKeyWithRetry() async {
    const attempts = 3;
    for (var i = 0; i < attempts; i++) {
      try {
        final value = await _secureStorage.read(key: 'hive_key');
        if (value != null) return value;
      } catch (_) {
        // نتجاهل ونعيد المحاولة أدناه؛ الفشل الأخير فقط هو ما سيُعتمد عليه
      }
      if (i < attempts - 1) {
        await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
    return null;
  }

  /// دالة داخلية: توليد أو استرجاع مفتاح التشفير من المنطقة الآمنة للهاتف
  ///
  /// ✅ [FIX - جذر مشكلة تسجيل الخروج التلقائي بعد التحديث / الكراش عند
  /// الإقلاع] كانت النسخة القديمة تعتبر أي قراءة فاشلة (null أو استثناء)
  /// دليلاً على "أول تشغيل" فتقوم بتوليد مفتاح جديد وتكتبه فوق المفتاح
  /// الحقيقي — فيصبح أي صندوق Hive مشفّر بالمفتاح القديم (بما فيه
  /// auth_box الذي يحوي jwt_token) غير قابل لفك التشفير أبداً بعدها.
  /// الآن: نميّز بوضوح بين "لا يوجد مفتاح بعد" و"يوجد مفتاح لكن يتعذر
  /// قراءته الآن" عبر علم دائم في shared_preferences، ولا نقوم أبداً
  /// بالكتابة فوق مفتاح موجود مسبقاً.
  static Future<List<int>> _getKey() async {
    // 1. إذا كان المفتاح موجوداً في الذاكرة، استخدمه فوراً
    if (_encryptionKey != null) return _encryptionKey!;

    final prefs = await SharedPreferences.getInstance();
    final bool keyProvisionedBefore = prefs.getBool(_kKeyProvisionedFlag) ?? false;

    // 2. محاولة قراءة المفتاح من التخزين الآمن (Keystore/Keychain) مع إعادة محاولة
    final String? keyString = await _readKeyWithRetry();

    if (keyString != null) {
      // 3. وُجد المفتاح: استخدمه، وتأكد من ضبط العلم إن لم يكن مضبوطاً
      if (!keyProvisionedBefore) {
        await prefs.setBool(_kKeyProvisionedFlag, true);
      }
      _encryptionKey = base64Url.decode(keyString);
      return _encryptionKey!;
    }

    if (keyProvisionedBefore) {
      // 4. ⚠️ نعلم من قبل أن هناك مفتاحاً تم إنشاؤه على هذا الجهاز، لكن
      // تعذّرت قراءته الآن رغم إعادة المحاولة. هذا خطأ عابر في التخزين
      // الآمن (وليس "أول تشغيل") — يجب ألا نولّد مفتاحاً بديلاً أبداً
      // هنا لأن ذلك سيُتلف كل البيانات المشفّرة الموجودة فعلياً وبشكل
      // نهائي. نرمي استثناءً مميزاً ليتعامل معه المستدعي (openBox) دون
      // حذف أي بيانات.
      throw StorageKeyUnavailableException(
        'hive_key was provisioned previously but is unreadable right now.',
      );
    }

    // 5. أول تشغيل فعلي فعلاً (لا يوجد سجل سابق لمفتاح على هذا الجهاز):
    // نولّد مفتاحاً عشوائياً جديداً ونحفظه، ونضبط العلم.
    final key = Hive.generateSecureKey();
    await _secureStorage.write(key: 'hive_key', value: base64Url.encode(key));
    await prefs.setBool(_kKeyProvisionedFlag, true);
    _encryptionKey = key;
    return _encryptionKey!;
  }

  /// الدالة الرئيسية: فتح أي صندوق بنظام التشفير
  ///
  /// ✅ [FIX] لم نعد نحذف الصندوق إلا في حالة تلف/عدم تطابق فعلي مؤكد
  /// (أي أن Hive.openBox رفض المفتاح فعلاً). إن كانت المشكلة أساساً أننا
  /// لم نستطع حتى الحصول على مفتاح (StorageKeyUnavailableException)، لا
  /// نحذف شيئاً — نرفع الخطأ للمستدعي ليقرر (مثال: عرض شاشة "إعادة
  /// المحاولة" بدل تسجيل خروج المستخدم أو تحطم التطبيق). كما أن مسار
  /// الاستعادة نفسه أصبح محمياً بـ try/catch منفصل حتى لا يتسبب فشله في
  /// كراش غير معالج يصعد إلى main() (وهو بالضبط ما ظهر في تقرير
  /// Crashlytics على السطر 44 القديم).
  static Future<Box> openBox(String boxName) async {
    try {
      final key = await _getKey();
      return await Hive.openBox(
        boxName,
        encryptionCipher: HiveAesCipher(key), // تفعيل التشفير هنا
      );
    } on StorageKeyUnavailableException catch (e, st) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'Encryption key temporarily unavailable for box: $boxName (data preserved, not deleted)',
        fatal: false,
      );
      // لا نحذف الصندوق — البيانات سليمة، فقط غير متاحة مؤقتاً. نعيد رمي
      // الخطأ حتى يتعامل معه المستدعي (main.dart) بلطف بدل تسجيل الخروج
      // أو تحطم التطبيق.
      rethrow;
    } catch (e, st) {
      // هذا يعني أن المفتاح تم الحصول عليه فعلاً لكن Hive فشل في فتح/فك
      // تشفير الصندوق — هذه هي الحالة الحقيقية لتلف البيانات أو عدم
      // تطابق المفتاح، وهنا فقط يكون حذف الصندوق وإعادة إنشائه منطقياً.
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'Hive failed to open/decrypt box (treated as corrupted): $boxName',
        fatal: false,
      );
      try {
        await Hive.deleteBoxFromDisk(boxName);
        final key = await _getKey();
        return await Hive.openBox(
          boxName,
          encryptionCipher: HiveAesCipher(key),
        );
      } catch (e2, st2) {
        // ✅ [FIX] مسار الاستعادة نفسه محمي الآن. فشل هنا يُسجَّل ويُرفع
        // كخطأ عادي بدل الانفجار كاستثناء غير معالج في main() (وهو ما
        // كان يظهر كـ Fatal Exception في Crashlytics).
        FirebaseCrashlytics.instance.recordError(
          e2,
          st2,
          reason: 'Recovery attempt also failed for box: $boxName',
          fatal: false,
        );
        rethrow;
      }
    }
  }

  // ==========================================================
  // دوال حفظ البيانات (للأوفلاين)
  // ==========================================================

  // 1. حفظ واسترجاع رقم الهاتف (للعلامة المائية - وصول سريع)
  static Future<void> saveUserPhone(String phone) async {
    final box = await openBox('auth_box');
    await box.put('user_phone_watermark', phone);
  }

  static Future<String?> getUserPhone() async {
    final box = await openBox('auth_box');
    return box.get('user_phone_watermark');
  }

  // 2. حفظ واسترجاع معلومات التواصل (واتساب / تليجرام - وصول سريع)
  static Future<void> saveContactInfo({required String whatsapp, required String telegram}) async {
    final box = await openBox('settings_box');
    await box.put('contact_whatsapp', whatsapp);
    await box.put('contact_telegram', telegram);
  }

  static Future<Map<String, String?>> getContactInfo() async {
    final box = await openBox('settings_box');
    return {
      'whatsapp': box.get('contact_whatsapp'),
      'telegram': box.get('contact_telegram'),
    };
  }

  // 3. حفظ واسترجاع كامل بيانات التطبيق (Init Data)
  static const String _keyFullAppInitData = 'full_app_init_data';

  static Future<void> saveFullAppInitData(Map<String, dynamic> data) async {
    final box = await openBox('app_cache');
    await box.put(_keyFullAppInitData, data);
  }

  // ✅ التعديل هنا: إرجاع dynamic لتجنب مشاكل Casting مع Hive
  static Future<dynamic> getFullAppInitData() async {
    final box = await openBox('app_cache');
    return box.get(_keyFullAppInitData);
  }
}
