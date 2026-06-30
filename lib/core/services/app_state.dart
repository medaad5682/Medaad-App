import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ✅ ضروري لـ ThemeMode و ValueNotifier
import 'package:hive_flutter/hive_flutter.dart';
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

  // ✅ 3. دالة تهيئة الثيم عند فتح التطبيق (تستدعى في main.dart)
  Future<void> initTheme() async {
    var box = await StorageService.openBox('settings_box');
    // القيمة الافتراضية هي الوضع الداكن (true)
    bool storedIsDark = box.get('is_dark_mode', defaultValue: true);
    themeNotifier.value = storedIsDark ? ThemeMode.dark : ThemeMode.light;
  }

  // ✅ 4. دالة التبديل بين الوضعين (عند ضغط الزر)
  Future<void> toggleTheme() async {
    bool currentIsDark = themeNotifier.value == ThemeMode.dark;

    // عكس القيمة الحالية
    themeNotifier.value = currentIsDark ? ThemeMode.light : ThemeMode.dark;

    // حفظ التفضيل الجديد في التخزين المحلي
    var box = await StorageService.openBox('settings_box');
    await box.put('is_dark_mode', !currentIsDark);
  }

  // ============================================================
  // 🌐 إدارة اللغة (Locale Management) — نفس نمط إدارة الثيم تماماً
  // ============================================================

  // ✅ 1. متغير لمراقبة اللغة الحالية (ValueNotifier) لتحديث الواجهة فورياً
  //    اللغة الافتراضية: العربية (اللغة الأساسية الفعلية للتطبيق حالياً)
  final ValueNotifier<Locale> localeNotifier =
      ValueNotifier(const Locale('ar'));

  // ✅ 2. دالة ثابتة لمعرفة هل اللغة الحالية عربية (RTL)
  static bool get isArabic => _instance.localeNotifier.value.languageCode == 'ar';

  // ✅ 3. دالة تهيئة اللغة عند فتح التطبيق (تستدعى في main.dart)
  Future<void> initLocale() async {
    var box = await StorageService.openBox('settings_box');
    // القيمة الافتراضية هي العربية
    String storedLanguageCode = box.get('language_code', defaultValue: 'ar');
    localeNotifier.value = Locale(storedLanguageCode);
  }

  // ✅ 4. دالة تغيير اللغة (تستدعى من شاشة الإعدادات/البروفايل)
  Future<void> setLocale(Locale newLocale) async {
    localeNotifier.value = newLocale;

    // حفظ التفضيل الجديد في التخزين المحلي
    var box = await StorageService.openBox('settings_box');
    await box.put('language_code', newLocale.languageCode);
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
