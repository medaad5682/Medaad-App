import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ✅ ضروري لـ ThemeMode و ValueNotifier
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/course_model.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../constants/api_constants.dart';
import 'download_manager.dart'; // 👈 ✅ تم استيراد مدير التحميل

class AppState {
  // Singleton Pattern
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // البيانات المخزنة
  List<CourseModel> allCourses = []; // للمتجر والشاشة الرئيسية
  Map<String, dynamic>? userData;

  List<String> myCourseIds = [];
  List<String> mySubjectIds = [];

  // ✅ القائمة الجاهزة للعرض في صفحة "مكتبتي"
  List<Map<String, dynamic>> myLibrary = [];

  // ✅ متغير لتحديد هل المستخدم ضيف أم لا
  bool isGuest = false;

  // ============================================================
  // 🌓 إدارة الثيم (Theme Management)
  // ============================================================

  // ✅ 1. إضافة متغير لمراقبة الثيم (ValueNotifier) لتحديث الواجهة فورياً
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

  // ✅ 2. دالة ثابتة (Static Getter) لمعرفة هل الوضع الحالي داكن (تستخدمها AppColors)
  static bool get isDark => _instance.themeNotifier.value == ThemeMode.dark;

  // ✅ [FIX] مفاتيح SharedPreferences المستخدمة كـ"ذاكرة تخزين مؤقت" سريعة
  // وغير حسّاسة للثيم واللغة — راجع شرح initLocaleFast()/initThemeFast()
  // أدناه لسبب وجودها.
  static const String _kCachedIsDarkModeKey = 'cached_is_dark_mode_fast_v1';
  static const String _kCachedLanguageCodeKey =
      'cached_language_code_fast_v1';

  // ✅ 3. دالة تهيئة الثيم عند فتح التطبيق (تستدعى في main.dart)
  // ✅ [FIX] ملفوفة الآن بـ try/catch: هذه الدالة تُستدعى عبر unawaited()
  // من main.dart بلا await، لذا أي خطأ غير ملتقط هنا (مثال:
  // StorageKeyUnavailableException عابر من Keychain) كان يتحول إلى خطأ
  // غير معالج في الـ Zone الرئيسي ويُسجَّل كـ crash قاتل (fatal: true) —
  // رغم أن initThemeFast() سبق ورسمت الثيم الصحيح من الكاش قبل runApp().
  // عند الفشل هنا، نُبقي القيمة التي رسمتها initThemeFast() كما هي بدل
  // إسقاط التطبيق بأكمله.
  Future<void> initTheme() async {
    try {
      var box = await StorageService.openBox('settings_box');
      // القيمة الافتراضية هي الوضع الداكن (true)
      bool storedIsDark = box.get('is_dark_mode', defaultValue: true);
      themeNotifier.value = storedIsDark ? ThemeMode.dark : ThemeMode.light;
      unawaited(_cacheIsDarkMode(storedIsDark));
    } catch (e, st) {
      debugPrint('⚠️ initTheme() failed to read settings_box (keeping fast-cached value): $e');
      if (Firebase.apps.isNotEmpty) {
        await FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'initTheme(): could not confirm theme from settings_box (fast-cached value kept)',
          fatal: false,
        );
      }
    }
  }

  // ✅ [FIX] راجع initLocaleFast() أسفل قسم اللغة لشرح كامل للمشكلة والحل —
  // هذه هي نفس المعالجة تماماً لكن للثيم بدل اللغة. تُستدعى في main.dart
  // *قبل* runApp() مباشرة (بعكس initTheme() أعلاه التي تبقى تُستدعى بعد
  // runApp() كمصدر رسمي) حتى لا يُرسم أول إطار دائماً بالوضع الداكن
  // الافتراضي قبل أن يتحول لاحقاً للوضع الفاتح إن كان هذا اختيار المستخدم
  // الفعلي.
  Future<void> initThemeFast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedIsDark = prefs.getBool(_kCachedIsDarkModeKey);
      if (cachedIsDark != null) {
        themeNotifier.value = cachedIsDark ? ThemeMode.dark : ThemeMode.light;
      }
      // لا يوجد قيمة مخزنة مؤقتاً بعد (أول تشغيل على الإطلاق) → نُبقي
      // القيمة الافتراضية (dark) كما هي؛ initTheme() اللاحقة ستضبطها من
      // Hive على أي حال ولا يوجد "وميض" لأن لا تفضيل سابق أصلاً ليُخالَف.
    } catch (_) {
      // فشل غير متوقع لقراءة SharedPreferences: نُبقي القيمة الافتراضية؛
      // initTheme() اللاحقة ستصحّحها من Hive.
    }
  }

  Future<void> _cacheIsDarkMode(bool isDark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCachedIsDarkModeKey, isDark);
    } catch (_) {
      // تجاهل: هذا تحسين لتفادي وميض الثيم فقط، وليس مصدر البيانات الرسمي.
    }
  }

  // ✅ 4. دالة التبديل بين الوضعين (عند ضغط الزر)
  Future<void> toggleTheme() async {
    bool currentIsDark = themeNotifier.value == ThemeMode.dark;

    // عكس القيمة الحالية
    themeNotifier.value = currentIsDark ? ThemeMode.light : ThemeMode.dark;

    // حفظ التفضيل الجديد في التخزين المحلي
    var box = await StorageService.openBox('settings_box');
    await box.put('is_dark_mode', !currentIsDark);

    // ✅ [FIX] تحديث النسخة المخزنة مؤقتاً أيضاً — راجع initThemeFast().
    await _cacheIsDarkMode(!currentIsDark);
  }

  // ============================================================
  // 🌐 إدارة اللغة (Locale Management) — نفس نمط إدارة الثيم تماماً
  // ============================================================

  // ✅ 1. متغير لمراقبة اللغة الحالية (ValueNotifier) لتحديث الواجهة فورياً
  //    اللغة الافتراضية: الإنجليزية إلى أن يتم تحديد لغة النظام في initLocale()
  final ValueNotifier<Locale> localeNotifier =
      ValueNotifier(const Locale('en'));

  // ✅ 2. دالة ثابتة لمعرفة هل اللغة الحالية عربية (RTL)
  static bool get isArabic => _instance.localeNotifier.value.languageCode == 'ar';

  // ✅ اللغات المدعومة فعلياً في التطبيق (يجب أن تطابق AppLocalizations.supportedLocales)
  static const List<String> _supportedLanguageCodes = ['en', 'ar'];

  // ✅ [FIX] عند عدم وجود أي تفضيل محفوظ (أول تشغيل فعلي للتطبيق)، كنا
  // نتحقق فقط من platformDispatcher.locale (اللغة الأولى/الأساسية على
  // الجهاز). لكن بعض الأجهزة تُرتّب أكثر من لغة مفضّلة (Settings > General
  // > Language & Region > Preferred Languages على iOS، ونظام مشابه على
  // أندرويد) — فإن كانت اللغة الأساسية غير مدعومة (مثلاً فرنسية) بينما
  // العربية أو الإنجليزية مدرجتان كلغة مفضّلة ثانية، كنا نتجاهل ذلك تماماً
  // ونذهب مباشرة لـ 'en' كافتراضي أخير. الآن نمر على كامل القائمة
  // المرتّبة بحسب أفضلية المستخدم (platformDispatcher.locales) ونختار أول
  // لغة مدعومة فعلياً في التطبيق، ولا نلجأ لـ 'en' إلا إن لم تكن أي لغة
  // من قائمة تفضيلات الجهاز بأكملها مدعومة.
  static String _resolveSystemLanguageCode() {
    for (final locale in WidgetsBinding.instance.platformDispatcher.locales) {
      if (_supportedLanguageCodes.contains(locale.languageCode)) {
        return locale.languageCode;
      }
    }
    return 'en';
  }

  // ✅ 3. دالة تهيئة اللغة عند فتح التطبيق (تستدعى في main.dart)
  //    - إن كان المستخدم قد اختار لغة من قبل، نستخدمها.
  //    - وإلا، نعتمد لغة نظام الجهاز إن كانت مدعومة (عربي أو إنجليزي).
  //    - وإن لم تكن لغة النظام مدعومة، تكون الإنجليزية هي الافتراضية.
  // ✅ [FIX] ملفوفة الآن بـ try/catch لنفس سبب initTheme() أعلاه تماماً:
  // تُستدعى عبر unawaited() بلا await من main.dart، فأي خطأ غير ملتقط
  // (مثال: StorageKeyUnavailableException عابر) كان يتحول إلى crash قاتل
  // رغم أن initLocaleFast() سبق ورسمت اللغة الصحيحة من الكاش. عند الفشل،
  // نُبقي القيمة التي رسمتها initLocaleFast() بدل إسقاط التطبيق.
  Future<void> initLocale() async {
    try {
      var box = await StorageService.openBox('settings_box');
      String? storedLanguageCode = box.get('language_code');

      if (storedLanguageCode != null &&
          _supportedLanguageCodes.contains(storedLanguageCode)) {
        localeNotifier.value = Locale(storedLanguageCode);
        unawaited(_cacheLanguageCode(storedLanguageCode));
        return;
      }

      // لا يوجد تفضيل محفوظ بعد (أول تشغيل فعلي) → استخدم لغة الجهاز
      final resolvedCode = _resolveSystemLanguageCode();

      localeNotifier.value = Locale(resolvedCode);
      unawaited(_cacheLanguageCode(resolvedCode));
    } catch (e, st) {
      debugPrint('⚠️ initLocale() failed to read settings_box (keeping fast-cached value): $e');
      if (Firebase.apps.isNotEmpty) {
        await FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'initLocale(): could not confirm locale from settings_box (fast-cached value kept)',
          fatal: false,
        );
      }
    }
  }

  // ✅ [FIX - جذر مشكلة "شاشة البداية تظهر بالإنجليزية ثم تتحول للعربية
  // بعد ثانيتين"] initLocale() أعلاه تقرأ تفضيل اللغة من settings_box،
  // وهو صندوق Hive مشفّر — وفتح أي صندوق Hive مشفّر يمر عبر _AppReadyGate
  // في storage_service.dart، والتي تنتظر عمداً حتى يُرسم *الإطار الأول*
  // وتصبح حالة دورة الحياة resumed قبل لمس Keychain/Keystore (إصلاح ضروري
  // لسباق -25308 على iOS — راجع توثيقها). بسبب هذا، لا يمكن لـ
  // initLocale() أن تكتمل قبل أول إطار على الإطلاق، فيُرسم ذلك الإطار
  // الأول دائماً بالقيمة الافتراضية المضبوطة سلفاً في localeNotifier
  // (الإنجليزية) — بصرف النظر عمّا اختاره المستخدم فعلياً — ثم يتحول
  // للعربية فور اكتمال القراءة الحقيقية من Hive في الخلفية. وهذا بالضبط
  // "الوميض" الذي يظهر لمستخدمي اللغة العربية عند كل إقلاع بارد للتطبيق.
  //
  // الحل: نحتفظ بنسخة "ذاكرة تخزين مؤقت" من رمز اللغة داخل
  // SharedPreferences (تخزين عادي غير مشفّر — NSUserDefaults على iOS،
  // وليس Keychain — لذا لا تمر إطلاقاً عبر _AppReadyGate ويمكن قراءتها
  // بأمان قبل runApp() مباشرة). هذه الدالة تُستدعى في main.dart قبل
  // runApp() لتضبط localeNotifier على القيمة الصحيحة *قبل* أول إطار،
  // فلا يظهر أي وميض. initLocale() الأصلية أعلاه تبقى تُستدعى بعد
  // runApp() كما هي تماماً وتبقى المصدر الرسمي/النهائي (وتُحدّث الذاكرة
  // المؤقتة لأي تشغيل لاحق)، لكنها الآن غالباً تجد القيمة متطابقة أصلاً
  // فلا يظهر أي تغيّر ملحوظ للمستخدم.
  Future<void> initLocaleFast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCode = prefs.getString(_kCachedLanguageCodeKey);

      if (cachedCode != null && _supportedLanguageCodes.contains(cachedCode)) {
        localeNotifier.value = Locale(cachedCode);
        return;
      }

      // لا يوجد شيء مخزن مؤقتاً بعد (أول تشغيل على الإطلاق) → استخدم لغة
      // الجهاز، بنفس منطق initLocale()/_resolveSystemLanguageCode() تماماً.
      // لا "وميض" هنا لأنه لا يوجد تفضيل سابق أصلاً ليُخالَف — وهذه القيمة
      // نفسها ستؤكدها initLocale() لاحقاً من Hive (وتُخزَّن مؤقتاً حينها
      // لأول مرة عبر _cacheLanguageCode) لأنه لا يوجد فرق بينهما أصلاً.
      final resolvedCode = _resolveSystemLanguageCode();
      localeNotifier.value = Locale(resolvedCode);
    } catch (_) {
      // فشل غير متوقع لقراءة SharedPreferences: نُبقي القيمة الافتراضية
      // (en) كما هي؛ initLocale() اللاحقة ستصحّحها من Hive على أي حال.
    }
  }

  Future<void> _cacheLanguageCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedLanguageCodeKey, code);
    } catch (_) {
      // تجاهل: هذا تحسين لتفادي وميض اللغة فقط، وليس مصدر البيانات الرسمي.
    }
  }

  // ✅ 4. دالة تغيير اللغة (تستدعى من شاشة الإعدادات/البروفايل)
  Future<void> setLocale(Locale newLocale) async {
    localeNotifier.value = newLocale;

    // حفظ التفضيل الجديد في التخزين المحلي (المصدر الرسمي)
    var box = await StorageService.openBox('settings_box');
    await box.put('language_code', newLocale.languageCode);

    // ✅ [FIX] تحديث النسخة المخزنة مؤقتاً في SharedPreferences أيضاً —
    // راجع initLocaleFast() أعلاه — لضمان ظهور اللغة الصحيحة فوراً في
    // الإقلاع القادم دون أي وميض بلغة أخرى.
    await _cacheLanguageCode(newLocale.languageCode);
  }

  // ============================================================
  // 🟢 Getters مساعدة للتحقق من الصلاحيات بسرعة
  // ============================================================

  // هل المستخدم معلم؟
  bool get isTeacher => userData?['role'] == 'teacher';

  // هل المستخدم طالب؟
  bool get isStudent => userData?['role'] == 'student';

  // هل المستخدم مسجل دخول (سواء كعضو أو ضيف)؟
  bool get isLoggedIn => userData != null || isGuest;

  // ============================================================
  // 🔍 دوال التحقق من الملكية
  // ============================================================
  bool ownsCourse(String courseId) => myCourseIds.contains(courseId);
  bool ownsSubject(String subjectId) => mySubjectIds.contains(subjectId);

  // ============================================================
  // ⚙️ دوال إدارة الحالة (State Management)
  // ============================================================

  // ✅ تحديث بيانات المستخدم فقط (تستخدم بعد تسجيل الدخول أو تعديل البروفايل)
  void updateUserData(Map<String, dynamic> user) {
    userData = user;
    isGuest = false; // تأكيد أنه ليس ضيفاً
  }

  // ✅ ضبط حالة الضيف (تستخدم عند الدخول كزائر)
  void setGuest(bool value) {
    isGuest = value;
    if (value) {
      userData = null;
      myLibrary = [];
      myCourseIds = [];
      mySubjectIds = [];
    }
  }

  // 🔥 دالة مساعدة سحرية لتحويل البيانات القادمة من Hive بأمان
  // تحول أي Map<dynamic, dynamic> إلى Map<String, dynamic> لتجنب أخطاء النوع
  Map<String, dynamic> _makeSafeMap(dynamic data) {
    if (data == null) return {};
    // إذا كانت البيانات Map عادية، نحولها بشكل صريح
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    // كحل أخير، نحاول التحويل عبر JSON (أبطأ قليلاً لكنه الأضمن في الحالات المعقدة)
    try {
      return jsonDecode(jsonEncode(data));
    } catch (_) {
      return {};
    }
  }

  // ============================================================
  // 🔍 دالة مساعدة لاستخراج جميع المواد التي يمتلكها الطالب 
  // (سواء كان يمتلك الكورس كاملاً أو المادة منفردة)
  // ============================================================
  List<String> _getAllAuthorizedSubjectIds() {
    Set<String> authorizedSubjects = {};
    for (var item in myLibrary) {
      if (item['owned_subjects'] != null) {
        for (var sub in item['owned_subjects']) {
          if (sub['id'] != null) {
            authorizedSubjects.add(sub['id'].toString());
          }
        }
      }
    }
    return authorizedSubjects.toList();
  }

  // تحديث البيانات القادمة من الـ API (Init Data) أو الذاكرة المحلية
  void updateFromInitData(dynamic data) {
    if (data == null) return;

    try {
      // 1. "تعقيم" البيانات: تحويل أي Map<dynamic, dynamic> إلى Map<String, dynamic>
      // هذه الخطوة تضمن أن البيانات القادمة من Hive تتصرف تماماً مثل JSON القادم من الإنترنت
      final Map<String, dynamic> castedData = _makeSafeMap(data);

      // 2. استقبال كورسات المتجر (متاحة للجميع: مسجلين وضيوف)
      if (castedData['courses'] != null) {
        allCourses = (castedData['courses'] as List)
            .map((e) => CourseModel.fromJson(
                _makeSafeMap(e))) // ✅ استخدام التحويل الآمن هنا
            .toList();
      } else {
        allCourses = [];
      }

      // 3. بيانات المستخدم (إذا وجد في الرد، فهو ليس ضيفاً)
      if (castedData['user'] != null) {
        userData = _makeSafeMap(castedData['user']);
        isGuest = false;
      }

      // 4. أرقام الاشتراكات (فقط إذا لم يكن ضيفاً)
      if (!isGuest && castedData['myAccess'] != null) {
        final access = _makeSafeMap(castedData['myAccess']);

        myCourseIds =
            (access['courses'] as List?)?.map((e) => e.toString()).toList() ??
                [];

        mySubjectIds =
            (access['subjects'] as List?)?.map((e) => e.toString()).toList() ??
                [];
      } else {
        myCourseIds = [];
        mySubjectIds = [];
      }

      // 5. استقبال مكتبة الطالب الجاهزة
      if (!isGuest && castedData['library'] != null) {
        myLibrary = (castedData['library'] as List)
            .map((e) => _makeSafeMap(e)) // ✅ تحويل آمن لكل عنصر في المكتبة
            .toList();
            
        // 👈 ✅ السطر الجديد: بعد بناء المكتبة، نستخرج كل المواد المتاحة وننظف التحميلات (يطبق على الطالب والمعلم)
        List<String> allAuthSubjects = _getAllAuthorizedSubjectIds();
        DownloadManager().validateAndCleanRevokedDownloads(allAuthSubjects);
        
      } else {
        // إذا كان ضيفاً، نجعل المكتبة فارغة دائماً
        myLibrary = [];
        
        // 👈 ✅ السطر الجديد: حذف التحميلات المحمية لأن الضيف لا يملك صلاحيات
        DownloadManager().validateAndCleanRevokedDownloads([]);
      }

      if (kDebugMode) {
        print(
            "✅ Data Updated: Courses: ${allCourses.length}, Library: ${myLibrary.length}");
      }
    } catch (e, stack) {
      if (kDebugMode) print("❌ Error parsing init data: $e\n$stack");
    }
  }

  // ✅ محاولة تحميل البيانات من الذاكرة المحلية (Offline Mode)
  Future<bool> loadOfflineData() async {
    try {
      if (kDebugMode) print("📂 Attempting to load offline data...");

      // ✅ استخدام الدالة الجديدة لجلب البيانات الكاملة المخزنة
      final cachedData = await StorageService.getFullAppInitData();

      if (cachedData != null) {
        if (kDebugMode) print("📂 Found cached data, processing...");

        // تحديث التطبيق بالبيانات المخبأة
        updateFromInitData(cachedData);

        // ⚠️ استرجاع نوع المستخدم وصورته من auth_box لضمان التزامن
        var authBox = await StorageService.openBox('auth_box');
        if (userData != null) {
          if (authBox.containsKey('role')) {
            userData!['role'] = authBox.get('role');
          }
          if (authBox.containsKey('profile_image')) {
            userData!['profile_image'] = authBox.get('profile_image');
          }
          // ✅ استرجاع رقم الهاتف من التخزين السريع إذا لم يكن موجوداً
          if (userData!['phone'] == null) {
            userData!['phone'] = await StorageService.getUserPhone();
          }
        }

        // إذا نجحنا في تحميل الكورسات أو المكتبة، نعتبر العملية ناجحة
        if (allCourses.isNotEmpty || myLibrary.isNotEmpty) {
          return true;
        }
      } else {
        if (kDebugMode) print("⚠️ No offline data found in storage.");
      }
    } catch (e) {
      if (kDebugMode) print("❌ Offline Load Error: $e");
    }
    return false; // فشل التحميل أو لا توجد بيانات
  }

  // 🟢 دالة جديدة: تحديث بيانات التطبيق بالكامل من السيرفر
  // تستدعى عند: إضافة/تعديل/حذف كورس أو مادة
  Future<void> reloadAppInit() async {
    try {
      var box = await StorageService.openBox('auth_box');
      String? token = box.get('jwt_token');

      // التأكد من وجود التوكن قبل الطلب (للمستخدم المسجل فقط)
      if (token == null || isGuest) return;

      // ✅ التعديل هنا: الاعتماد على ApiClient دون تمرير الهيدرز يدوياً وإضافة timestamp لمنع الكاش
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiUrl}/public/get-app-init-data',
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch, // 👈 هذا السطر يمنع الكاش
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        // 1. تحديث الذاكرة الحية (RAM)
        updateFromInitData(data);

        // 2. ✅ حفظ كامل الرد في الذاكرة الدائمة (للأوفلاين)
        // نقوم بتحويل البيانات إلى Map<String, dynamic> قبل الحفظ للتأكد
        await StorageService.saveFullAppInitData(
            Map<String, dynamic>.from(data));

        // 3. ✅ حفظ رقم الهاتف للعلامة المائية (وصول سريع)
        if (data['user'] != null && data['user']['phone'] != null) {
          await StorageService.saveUserPhone(data['user']['phone']);
        }

        // 4. ✅ حفظ معلومات التواصل (وصول سريع)
        if (data['contactInfo'] != null) {
          await StorageService.saveContactInfo(
            whatsapp: data['contactInfo']['whatsapp'] ?? '',
            telegram: data['contactInfo']['telegram'] ?? '',
          );
        }

        if (kDebugMode) print("✅ App Init Reloaded & Full Data Persisted!");
      }
    } catch (e) {
      if (kDebugMode) print("❌ App Init Reload Error: $e");
    }
  }

  // دالة لمسح البيانات عند الخروج
  void clear() {
    userData = null;
    myCourseIds = [];
    mySubjectIds = [];
    myLibrary = [];
    isGuest = false; // إعادة تعيين حالة الضيف
    // لا نمسح allCourses لأنها بيانات عامة قد نحتاجها في صفحة الدخول
  }
}
