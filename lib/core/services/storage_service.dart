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
  // ✅ [FIX - جذر مشكلة "شاشة تسجيل الدخول تظهر بدون سبب على iOS"]
  // النسخة القديمة كانت بلا iOptions صريحة، أي أنها تستخدم افتراضياً على
  // iOS صنف الحماية kSecAttrAccessibleWhenUnlocked: "مقروء فقط إن كان
  // الجهاز مفتوحاً الآن هذه اللحظة بالذات". هذا الصنف معروف بأنه يفشل
  // بشكل متقطع (errSecInteractionNotAllowed / OSStatus -25308) في لحظات
  // طبيعية جداً: إطلاق بارد فور فتح القفل، عودة من الخلفية أثناء استكمال
  // iOS لتفعيل الـ scene، أو تشغيل الكود مبكراً جداً في main() قبل أن
  // يُعلن التطبيق نشطاً بالكامل. هذا سباق زمني بين "الجهاز يبدو مفتوحاً
  // للمستخدم" و"طبقة حماية البيانات انتهت فعلياً من تحديث حالتها" — وهو
  // السبب الجذري وراء وصول بعض مستخدمي iOS لشاشة تسجيل الدخول رغم كونهم
  // مسجّلين دخول فعلياً، بينما هذا لا يحدث إطلاقاً إن أعادوا فتح التطبيق
  // بعد إغلاقه مباشرة (لا سباق زمني في تلك الحالة).
  //
  // الحل: first_unlock_this_device يجعل العنصر قابلاً للقراءة بمجرد فتح
  // قفل الجهاز مرة واحدة منذ الإقلاع، ويبقى كذلك لبقية دورة الإقلاع تلك —
  // بلا تقيّد بلحظة "مفتوح الآن بالضبط". يبقى مقصوراً على هذا الجهاز فقط
  // (ThisDeviceOnly)، فلا يُستعاد عبر نسخة iCloud احتياطية على جهاز آخر —
  // نفس مستوى الحماية الحالي فعلياً، لكن بدون السباق الزمني.
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // ✅ [FIX] مثيل "قديم" بإعدادات افتراضية بلا iOptions صريحة — تطابق
  // تماماً الإعدادات التي كُتب بها عنصر hive_key لدى كل قاعدة المستخدمين
  // الحالية قبل هذا التحديث. تغيير iOptions على مثيل FlutterSecureStorage
  // لا يُرحّل تلقائياً عنصراً مكتوباً مسبقاً بصنف حماية مختلف؛ والقراءة
  // بالمثيل الجديد قد تُرجع null لعنصر موجود فعلياً بصنف قديم (حالة
  // موثّقة في مكتبة flutter_secure_storage عند تغيير accessibility لقاعدة
  // مستخدمين قائمة بالفعل). هذا المثيل يُستخدم فقط كمسار احتياطي أثناء
  // الترحيل، وليس للاستخدام العادي.
  static const _secureStorageLegacy = FlutterSecureStorage();

  // ✅ [FIX] علم دائم يمنع إعادة محاولة الترحيل في كل قراءة بعد نجاحه مرة.
  static const String _kAccessibilityMigratedFlag =
      'storage_service_keychain_migrated_v1';

  static List<int>? _encryptionKey;

  // ✅ [FIX] علم دائم (يبقى عبر تحديثات التطبيق، ويُمسح فقط عند إلغاء
  // التثبيت) يسجّل أننا سبق ونجحنا في توفير hive_key على هذا الجهاز.
  // هذا هو الفيصل الوحيد الموثوق لمعرفة: هل هذا أول تشغيل فعلاً (لا يوجد
  // مفتاح بعد)، أم أن المفتاح موجود لكن قراءته فشلت مؤقتاً؟
  static const String _kKeyProvisionedFlag = 'storage_service_key_provisioned_v1';

  // ✅ [FIX] عداد دائم (عبر عمليات إقلاع التطبيق، وليس ضمن نفس الجلسة) لعدد
  // المرات المتتالية التي فشلت فيها قراءة hive_key رغم أنه كان مزوّداً من
  // قبل. الغرض: تمييز "خلل عابر يزول خلال ثوانٍ/عمليات إعادة تشغيل قليلة"
  // عن "المفتاح فُقد فعلياً وبشكل دائم من Keychain/Keystore" (حالة نادرة
  // جداً لكن ممكنة). طالما العداد دون الحد، لا نلمس أي بيانات مطلقاً.
  static const String _kUnavailableStreakKey = 'storage_service_key_unavailable_streak_v1';

  // بعد هذا العدد من عمليات إقلاع متتالية فشلت جميعها في قراءة مفتاح موجود
  // مسبقاً، نعتبره فُقد فعلياً بشكل دائم بدل الاستمرار في حجب المستخدم عن
  // التطبيق للأبد، ونلجأ لتوليد مفتاح جديد كحل أخير موثّق.
  static const int _kMaxUnavailableStreakBeforeReset = 3;

  // يمنع زيادة العداد أكثر من مرة واحدة لكل تشغيل فعلي للتطبيق، حتى لو
  // استُدعيت openBox() عدة مرات ضمن نفس الجلسة (auth_box, settings_box,
  // downloads_box...) قبل أن تُحسم النتيجة.
  static bool _hasRecordedUnavailabilityThisRun = false;

  /// ✅ [FIX] محاولة قراءة hive_key من Keychain/Keystore مع إعادة محاولة
  /// (retry with backoff) بدل الاستسلام من أول فشل. الفشل هنا قد يكون
  /// null عابر أو PlatformException عابر (شائع خصوصاً في اللحظات الأولى
  /// بعد تحديث App Store، أو قبل أول فتح قفل للجهاز بعد إعادة تشغيله).
  static Future<String?> _readKeyWithRetry() async {
    const attempts = 3;
    for (var i = 0; i < attempts; i++) {
      try {
        // نحاول أولاً بالمثيل الجديد (first_unlock_this_device). ينجح
        // مباشرة للتثبيتات الجديدة، ولأي مستخدم سبق ترحيله بنجاح.
        final value = await _secureStorage.read(key: 'hive_key');
        if (value != null) return value;

        // ✅ [FIX] لم نجد شيئاً بالمثيل الجديد — هذا لا يعني بالضرورة "لا
        // يوجد مفتاح إطلاقاً"، فقد يكون العنصر لا يزال مكتوباً بصنف
        // الحماية القديم لمستخدم حالي لم يُرحَّل بعد. نتحقق صراحة بالمثيل
        // القديم قبل أن نستنتج غياب المفتاح.
        final legacyValue = await _secureStorageLegacy.read(key: 'hive_key');
        if (legacyValue != null) {
          await _migrateAccessibilityIfNeeded(legacyValue);
          return legacyValue;
        }
      } catch (_) {
        // نتجاهل ونعيد المحاولة أدناه؛ الفشل الأخير فقط هو ما سيُعتمد عليه
      }
      if (i < attempts - 1) {
        await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
    return null;
  }

  /// ✅ [FIX] يُرحّل عنصر hive_key من صنف الحماية القديم (WhenUnlocked
  /// الافتراضي) إلى first_unlock_this_device، مرة واحدة فقط لكل جهاز.
  ///
  /// بالترتيب: (1) يكتب القيمة عبر المثيل الجديد، (2) يتحقق بإعادة قراءتها
  /// فعلياً من نفس المثيل الجديد قبل تصديق نجاح الكتابة، (3) لا يحذف
  /// العنصر القديم ولا يضبط علم "تم الترحيل" إلا بعد نجاح ذلك التحقق.
  /// هذا الترتيب مقصود: إن فشلت الكتابة أو التحقق لأي سبب، يبقى العنصر
  /// القديم سليماً كما هو ونعيد محاولة الترحيل تلقائياً في القراءة
  /// الناجحة التالية — لا يوجد أي احتمال لفقدان المفتاح أثناء الترحيل.
  static Future<void> _migrateAccessibilityIfNeeded(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAccessibilityMigratedFlag) ?? false) return;

    try {
      await _secureStorage.write(key: 'hive_key', value: value);
      final verify = await _secureStorage.read(key: 'hive_key');
      if (verify == value) {
        // نجحت الكتابة والتحقق تحت صنف الحماية الجديد — الآن فقط يمكن
        // حذف النسخة القديمة بأمان.
        await _secureStorageLegacy.delete(key: 'hive_key');
        await prefs.setBool(_kAccessibilityMigratedFlag, true);
      }
      // إن لم يتطابق التحقق (نادر جداً)، لا نغيّر شيئاً — العنصر القديم
      // ما زال موجوداً وسيُعتمد عليه حتى تنجح محاولة ترحيل لاحقة.
    } catch (_) {
      // فشل الكتابة/التحقق غير مؤذٍ هنا: العنصر القديم لم يُمس بعد.
    }
  }

  /// ✅ [FIX] نفس فلسفة `_readKeyWithRetry` تماماً، لكن للكتابة. كتابة أول
  /// تشغيل وكتابة "الحل الأخير" كانتا بلا أي حماية محلية — لو رمت الكتابة
  /// نفسها `PlatformException(-25308)` بسبب نفس سباق "مفتوح الآن بالضبط"،
  /// كانت تفلت من هنا دون أي إعادة محاولة، معتمدة بالكامل على المستدعي
  /// البعيد (`_openBoxSafely` في main.dart) لمنع كراش قاتل — وقد يتسبب ذلك
  /// أيضاً في أن يتعامل openBox() مع الفشل كـ"تلف بيانات" ويحذف صندوقاً حديث
  /// الإنشاء بلا داعٍ. الآن: نعيد المحاولة محلياً أولاً بنفس نمط القراءة، ولا
  /// نرمي أبداً من هنا — نُرجع false عند فشل كل المحاولات فيقرر المستدعي كيف
  /// يتصرف (الاستمرار بمفتاح في الذاكرة فقط لهذه الجلسة، دون رمي استثناء).
  static Future<bool> _writeKeyWithRetry(List<int> key) async {
    const attempts = 3;
    for (var i = 0; i < attempts; i++) {
      try {
        await _secureStorage.write(key: 'hive_key', value: base64Url.encode(key));
        return true;
      } catch (_) {
        // نتجاهل ونعيد المحاولة أدناه؛ نعتمد على النتيجة النهائية فقط
      }
      if (i < attempts - 1) {
        await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
    return false;
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
      // ✅ [FIX] نجاح القراءة يعني أن المشكلة كانت عابرة فعلاً: نصفّر عداد
      // الفشل المتتالي عبر عمليات الإقلاع حتى لا يتراكم من مرات فشل قديمة.
      await prefs.setInt(_kUnavailableStreakKey, 0);
      _encryptionKey = base64Url.decode(keyString);
      return _encryptionKey!;
    }

    if (keyProvisionedBefore) {
      // 4. ⚠️ نعلم من قبل أن هناك مفتاحاً تم إنشاؤه على هذا الجهاز، لكن
      // تعذّرت قراءته الآن رغم إعادة المحاولة. هذا عادة خطأ عابر في
      // التخزين الآمن (وليس "أول تشغيل") — لذا لا نولّد مفتاحاً بديلاً
      // فوراً هنا لأن ذلك سيُتلف كل البيانات المشفّرة الموجودة فعلياً.
      //
      // لكن إن استمر هذا الفشل عبر عدة عمليات إقلاع متتالية للتطبيق (وليس
      // مجرد إعادة محاولات ضمن نفس الاستدعاء)، فهذا يعني على الأرجح أن
      // المفتاح فُقد فعلياً وبشكل دائم (مثال نادر: تغيّر إعدادات التوقيع
      // أفقد الوصول القديم لـ Keychain نهائياً) — وحينها الاستمرار في
      // حماية بيانات لم تعد قابلة للاسترجاع أصلاً يعني فقط حبس المستخدم
      // خارج التطبيق للأبد، وهو أسوأ من إعادة تسجيل دخول لمرة واحدة.
      int streak = prefs.getInt(_kUnavailableStreakKey) ?? 0;
      if (!_hasRecordedUnavailabilityThisRun) {
        streak += 1;
        await prefs.setInt(_kUnavailableStreakKey, streak);
        _hasRecordedUnavailabilityThisRun = true;
      }

      if (streak < _kMaxUnavailableStreakBeforeReset) {
        // ما زلنا ضمن نافذة "قد يكون عابراً" — لا نلمس أي بيانات، نرمي
        // استثناءً مميزاً ليتعامل معه المستدعي (openBox) دون حذف أي شيء.
        throw StorageKeyUnavailableException(
          'hive_key was provisioned previously but is unreadable right now '
          '(consecutive-launch failure streak: $streak/$_kMaxUnavailableStreakBeforeReset).',
        );
      }

      // ⚠️ آخر حل موثّق: تجاوزنا حد المحاولات عبر عمليات إقلاع منفصلة.
      // نعتبر المفتاح القديم مفقوداً فعلياً ونولّد مفتاحاً جديداً بدل حبس
      // المستخدم للأبد. صناديق Hive المشفّرة بالمفتاح القديم لن تُفتح بهذا
      // المفتاح الجديد — ستتعامل openBox() مع ذلك عبر مسارها المعتاد لتلف
      // البيانات (حذف الصندوق وإعادة إنشائه فارغاً) بدل تحطم التطبيق، وهذا
      // يعني عملياً تسجيل خروج المستخدم لمرة واحدة، وليس حبساً دائماً.
      FirebaseCrashlytics.instance.recordError(
        StorageKeyUnavailableException(
          'Forcing new hive_key as last-resort recovery after $streak consecutive failed app launches.',
        ),
        StackTrace.current,
        reason: 'hive_key considered permanently lost after repeated launch failures — regenerating',
        fatal: false,
      );

      final key = Hive.generateSecureKey();
      final persisted = await _writeKeyWithRetry(key);
      if (persisted) {
        await prefs.setInt(_kUnavailableStreakKey, 0);
      } else {
        // ✅ [FIX] فشلت حتى كتابة المفتاح الجديد بعد إعادة المحاولة (نفس
        // السباق أصاب الكتابة أيضاً، حالة نادرة جداً). لا نرمي استثناءً هنا
        // — نكمل بمفتاح في الذاكرة فقط لهذه الجلسة (التطبيق يعمل بشكل طبيعي
        // الآن) بدل تحويل هذا لكراش أو حذف صندوق. نترك عداد streak كما هو
        // فيُعاد تقييم الوضع من جديد في التشغيل القادم.
        FirebaseCrashlytics.instance.recordError(
          StorageKeyUnavailableException(
            'Failed to persist last-resort hive_key after retries — continuing with in-memory-only key for this session.',
          ),
          StackTrace.current,
          reason: 'last-resort hive_key write also failed after retries',
          fatal: false,
        );
      }
      _encryptionKey = key;
      return _encryptionKey!;
    }

    // 5. أول تشغيل فعلي فعلاً (لا يوجد سجل سابق لمفتاح على هذا الجهاز):
    // نولّد مفتاحاً عشوائياً جديداً ونحفظه، ونضبط العلم.
    final key = Hive.generateSecureKey();
    final persisted = await _writeKeyWithRetry(key);
    if (persisted) {
      await prefs.setBool(_kKeyProvisionedFlag, true);
    } else {
      // ✅ [FIX] لم نتمكن من حفظ مفتاح أول تشغيل بعد إعادة المحاولة. عمداً
      // لا نضبط _kKeyProvisionedFlag هنا: بما أنه لا توجد بيانات مشفّرة
      // بعد بهذا المفتاح (أول تشغيل فعلاً)، لا خطر من معاملة التشغيل
      // القادم كـ"أول تشغيل" من جديد حتى تنجح الكتابة فعلياً — بدل الدخول
      // في مسار "مفتاح مفقود"/streak دون داعٍ. نكمل هذه الجلسة بمفتاح في
      // الذاكرة فقط حتى لا ينهار التطبيق.
      FirebaseCrashlytics.instance.recordError(
        StorageKeyUnavailableException(
          'Failed to persist first-run hive_key after retries — continuing with in-memory-only key for this session.',
        ),
        StackTrace.current,
        reason: 'first-run hive_key write failed after retries',
        fatal: false,
      );
    }
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
