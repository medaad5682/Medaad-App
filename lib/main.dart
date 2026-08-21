import 'dart:async';
import 'dart:io' show Platform;
import 'package:Medaad/app.dart';
import 'package:Medaad/core/services/security_manager.dart';
import 'package:Medaad/core/services/widgets/restart_widget.dart';
import 'package:Medaad/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// ✅ استيراد مكتبة الإشعارات من فايربيز
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:secure_display/secure_display.dart';

// ✅ استيراد حزمة App Check و Foundation لمعرفة وضع التطبيق
import 'package:flutter/foundation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ✅ استيراد حزمة الخلفية
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

import 'core/services/notification_service.dart';
import 'core/services/app_state.dart';
import 'core/services/storage_service.dart';
// ✅ استيراد شاشة الإشعارات ليتم التوجيه إليها
import 'presentation/screens/notifications_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> snackbarKey =
    GlobalKey<ScaffoldMessengerState>();

// ✅ [FIX] يمنع دفع NotificationsScreen قبل أن تُنهي SplashScreen تهيئتها
// الكاملة وتنتقل بنفسها للوجهة النهائية (MainWrapper أو LoginScreen).
//
// المشكلة الأصلية: كان main.dart يدفع NotificationsScreen مباشرة بمجرد
// وصول إشعار (getInitialMessage/onMessageOpenedApp) بغض النظر عن حالة
// SplashScreen. لو وصل هذا الدفع أثناء ما زالت SplashScreen تعمل (تنتظر
// رد السيرفر، تتحقق من الشروط، إلخ)، كانت NotificationsScreen تُدفع فوق
// SplashScreen في المكدس — ثم عندما تنتهي SplashScreen وتستدعي
// `Navigator.pushAndRemoveUntil(..., (route) => false)`، هذا الاستدعاء
// يمسح *كل* المسارات السابقة بما فيها NotificationsScreen التي دُفعت
// للتو، فتختفي الشاشة التي كان يُفترض أن يراها المستخدم دون أي تفسير —
// بالضبط المشكلة التي وصفتَها. أيضاً لم يكن هناك أي حماية من دفع الشاشة
// أكثر من مرة إذا وصلت أكثر من إشارة ضغط على إشعار في نفس اللحظة تقريباً
// (مثال: getInitialMessage() وonMessageOpenedApp() قد يُطلقان معاً).
//
// الحل: SplashScreen تستدعي `AppReadySignal.instance.markReady()` هي
// نفسها فور وصولها لوجهتها النهائية (راجع `_navigateToFinalDestination`
// في splash_screen.dart). أي طلب تنقّل بسبب إشعار (من هنا أو من
// notification_service.dart) يمرّ عبر `openNotificationsScreenWhenReady()`
// أدناه، والتي تنتظر تلك الإشارة أولاً (بمهلة أمان قصوى حتى لا تُعلَّق
// للأبد لو تعطّلت SplashScreen لسبب ما، مثال: تحديث إجباري يحجب التنقل
// عمداً)، ثم تدفع الشاشة مرة واحدة فقط بفضل قفل `_isNavigatingToNotifications`.
class AppReadySignal {
  AppReadySignal._();
  static final AppReadySignal instance = AppReadySignal._();

  final Completer<void> _completer = Completer<void>();

  bool get isReady => _completer.isCompleted;

  /// تُستدعى مرة واحدة من SplashScreen فور وصولها لوجهتها النهائية.
  void markReady() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// تنتظر الجاهزية الفعلية، مع مهلة أمان قصوى (15 ثانية) حتى لا تُعلَّق
  /// أي محاولة تنقّل للأبد في حالة نادرة تمنع SplashScreen من الوصول لأي
  /// وجهة نهائية (مثال: حوار تحديث إجباري يبقى معلّقاً بانتظار المستخدم).
  Future<void> get future => _completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
}

// ✅ [FIX] قفل بسيط يمنع تنفيذ أكثر من محاولة تنقّل لشاشة الإشعارات في
// نفس اللحظة تقريباً — يحدث فعلياً حين يصل أكثر من مصدر إشعار معاً
// (مثال: getInitialMessage() عند الإقلاع البارد، ومباشرة بعده
// onDidReceiveNotificationResponse من flutter_local_notifications لنفس
// الإشعار). بدون هذا القفل كان من الممكن دفع NotificationsScreen أكثر من
// مرة فوق بعضها.
bool _isNavigatingToNotifications = false;

/// نقطة الدخول الموحّدة لأي مصدر إشعار (FCM في main.dart، أو الإشعارات
/// المحلية في notification_service.dart) للتنقل لشاشة الإشعارات. تنتظر
/// اكتمال تهيئة SplashScreen فعلياً أولاً حتى لا تُدفع الشاشة فوق
/// SplashScreen لتُمسَح لاحقاً (راجع شرح [AppReadySignal] أعلاه)، وتمنع
/// أي دفع مكرر متزامن.
Future<void> openNotificationsScreenWhenReady() async {
  if (_isNavigatingToNotifications) return;
  _isNavigatingToNotifications = true;
  try {
    await AppReadySignal.instance.future;
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
      );
    }
  } finally {
    _isNavigatingToNotifications = false;
  }
}

// ✅ دالة التقاط الإشعارات عندما يكون التطبيق مغلقاً أو في الخلفية (يجب أن تكون خارج أي Class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // يجب تهيئة فايربيز هنا أيضاً لأن هذه الدالة تعمل في بيئة معزولة
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

// ✅ دالة تهيئة خدمة الخلفية
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackgroundService, // الدالة التي ستعمل في الخلفية
      autoStart: false, // ⚠️ مهم جداً: لا تبدأها تلقائياً لتجنب الحظر، ستبدأ مع التحميل
      isForegroundMode: true,
      autoStartOnBoot: false,
      notificationChannelId: 'downloads_channel', 
      initialNotificationTitle: 'مــــداد',
      initialNotificationContent: 'Initializing Service...',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStartBackgroundService,
      onBackground: onIosBackground,
    ),
  );
}

// ✅ دالة التشغيل الفعلية (يجب أن تكون خارج أي Class أو Top Level)
@pragma('vm:entry-point')
void onStartBackgroundService(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('keepAlive').listen((event) {
      // يمكنك وضع كود هنا إذا أردت استلام إشارات من الواجهة الأمامية
  });
}

// ✅ دالة مخصصة للعمل في الخلفية في نظام iOS
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// ✅ [ROOT-CAUSE FIX] إعداد Firebase Messaging بشكل معزول تمامًا عن مسار
// إقلاع التطبيق الرئيسي.
//
// المشكلة الأصلية: كان `messaging.getToken()` يُستدعى مباشرة بعد
// requestPermission() دون أي try/catch من حوله. على iOS تحديدًا،
// getToken() يتطلب أن يكون APNs token قد وصل بالفعل من نظام التشغيل
// (عبر application:didRegisterForRemoteNotificationsWithDeviceToken:)
// قبل أن يتمكن من طلب FCM token. هذا التسجيل مع Apple يحدث بشكل غير
// متزامن تمامًا، وقد يتأخر (شبكة بطيئة عند أول تشغيل، اتصال خلوي فقط،
// أو ببساطة رفض المستخدم لإذن الإشعارات فيمنع تسجيل الجهاز أصلاً).
// عندما لم يكن الـ APNs token جاهزًا، كانت المكتبة ترمي FlutterError من
// `_APNSTokenCheck` — وبما أن هذا الاستدعاء داخل runZonedGuarded بلا أي
// حماية، كان الخطأ يصعد مباشرة إلى onError الخاص بالـ Zone، الذي يسجّله
// كـ crash **قاتل** (`fatal: true`) و **يوقف تنفيذ باقي main() قبل
// الوصول إلى runApp()** — أي أن التطبيق لا يفتح إطلاقًا لبعض المستخدمين،
// وذلك فقط على الأجهزة/الشبكات التي يتأخر فيها تسجيل APNs، وهو ما يفسر
// حدوث المشكلة على بعض أجهزة iOS دون الأخرى.
//
// الإصلاح: (1) لف كل شيء بـ try/catch محلي بحيث لا يمكن لأي فشل هنا أن
// يصل إطلاقًا إلى الـ Zone الرئيسي أو يمنع runApp(). (2) على iOS، ننتظر
// فعليًا وصول الـ APNs token (بمحاولات متكررة محدودة بمهلة زمنية) قبل أي
// استدعاء لـ getToken() بدلاً من افتراض جاهزيته فورًا. (3) تُستدعى هذه
// الدالة الآن بعد runApp() (fire-and-forget) حتى لا تؤخر ظهور واجهة
// التطبيق أبدًا مهما استغرق تسجيل الإشعارات من وقت.
Future<void> _setupFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 Notification permission status: ${settings.authorizationStatus}');

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // ✅ على iOS فقط: انتظر وصول الـ APNs token فعليًا قبل طلب FCM token.
    // بدون هذا الانتظار، getToken() يرمي FlutterError إن لم يكن الـ APNs
    // token جاهزًا بعد — وهو ما كان يسبب الانهيار الأصلي.
    if (Platform.isIOS) {
      String? apnsToken = await messaging.getAPNSToken();
      var attempts = 0;
      while (apnsToken == null && attempts < 10) {
        await Future.delayed(const Duration(seconds: 1));
        apnsToken = await messaging.getAPNSToken();
        attempts++;
      }
      if (apnsToken == null) {
        // لم يصل الـ APNs token خلال 10 ثوانٍ (شبكة بطيئة جدًا أو الإذن
        // مرفوض) — نتخلى عن جلب FCM token في هذه الجلسة بهدوء بدلاً من
        // رمي استثناء. سيُعاد المحاولة تلقائيًا في التشغيل التالي، أو عبر
        // onTokenRefresh لاحقًا إن توفر الاتصال.
        debugPrint('⚠️ APNs token not available after retries — skipping FCM token fetch for now');
        return;
      }
    }

    final fcmToken = await messaging.getToken();
    assert(() {
      debugPrint("🔥 FCM Token: $fcmToken");
      return true;
    }());

    if (fcmToken != null) {
      // ✅ [CLEAN] auth_box يُفتح هنا فقط عند الحاجة الفعلية لحفظ الـ
      // fcm_token — بدل فتحه مسبقاً في main() وتمريره كمعامل. بفضل قفل
      // StorageService.openBox() (_openInFlight)، هذا الاستدعاء يتشارك
      // نفس نتيجة الفتح مع splash_screen.dart إن كانت قد بدأته بالفعل
      // (أو أي مسار آخر)، فلا يحدث أي فتح مكرر فعلياً للصندوق. قد تكون
      // النتيجة null إذا فشل فتح الصندوق بأمان — لا نريد رمي استثناء آخر
      // هنا.
      final authBox = await _openBoxSafely('auth_box');
      await authBox?.put('fcm_token', fcmToken);
    }
  } catch (e, stack) {
    // ✅ أي فشل هنا (بما فيه FlutterError من _APNSTokenCheck) يُسجَّل كخطأ
    // غير قاتل ولا يؤثر إطلاقًا على بقية التطبيق.
    debugPrint('⚠️ Firebase Messaging setup failed (non-fatal): $e');
    if (Firebase.apps.isNotEmpty) {
      await _safeRecordError(e, stack, fatal: false);
    }
  }
}

// ✅ [FIX] غلاف آمن حول StorageService.openBox(): يمنع فشل فتح أي صندوق
// (وبالأخص فشل الحصول على مفتاح التشفير من Keychain/Keystore بعد تحديث
// App Store — راجع StorageKeyUnavailableException في storage_service.dart)
// من التصعيد إلى كراش قاتل يمنع إقلاع التطبيق. عند الفشل: نسجّل الخطأ
// كغير قاتل ونعيد null، فيقلع التطبيق بحالة "بدون بيانات محفوظة مؤقتاً"
// (مثلاً: يُعامل كضيف حتى تعود القراءة للعمل) بدل الانهيار الكامل أو حذف
// أي بيانات فعلياً.
Future<Box?> _openBoxSafely(String boxName) async {
  try {
    return await StorageService.openBox(boxName);
  } catch (e, st) {
    debugPrint('⚠️ Failed to open box "$boxName" safely at startup: $e');
    if (Firebase.apps.isNotEmpty) {
      await _safeRecordError(
        e,
        st,
        reason: 'Startup: could not open Hive box "$boxName" (app continues without it)',
        fatal: false,
      );
    }
    return null;
  }
}

// ✅ [FIX] يُستدعى بعد runApp() فقط (fire-and-forget) بدل أن يُنفَّذ قبله
// ويحجبه كما كان سابقاً. يفتح Hive والصناديق المشفّرة، ثم يُشغّل إعداد
// Firebase Messaging بعد ذلك مباشرة (بدل استدعائه بمعزل تام من مسار
// التخزين كما كان). واجهة التطبيق (runApp) لم تعد تنتظر أياً من هذا
// إطلاقاً — يظهر التطبيق فوراً بحالة "بدون بيانات محفوظة مؤقتاً" إلى أن
// تكتمل هذه الدالة في الخلفية، وStorageService._getKey() ستنتظر داخلياً
// تأكيد أن التطبيق نشط فعلاً (_AppReadyGate) قبل أي محاولة قراءة من
// Keychain/Keystore على أي حال.
Future<void> _initStorageAfterAppReady() async {
  try {
    // ✅ [FIX] StorageService.ensureInitialized() بدل Hive.initFlutter()
    // المباشرة — splash_screen.dart يستدعي نفس الدالة بالتوازي تقريباً،
    // فيتقاسم الاثنان نتيجة تهيئة واحدة بدل تكرارها (راجع التعليق في
    // storage_service.dart).
    await StorageService.ensureInitialized();
    // ✅ [CLEAN] main.dart لا يفتح أي صندوق (Box) بشكل استباقي بعد الآن.
    // كل صندوق يُفتح فقط من المكان الذي يحتاجه فعلياً وفي اللحظة التي
    // يحتاجه فيها:
    //   - settings_box  → AppState.initTheme()/initLocale() أدناه في main()
    //   - auth_box       → SplashScreen._initializeApp() فور ظهورها، أو من
    //                       داخل _setupFirebaseMessaging() أدناه فقط إذا
    //                       وُجد fcm_token فعلاً لحفظه
    //   - downloads_box  → SplashScreen._initializeApp()
    //   - pdf_drawings_db → PdfAnnotationStore عند فتح أول ملف PDF فعلياً
    // القفل الموجود في StorageService.openBox() (_openInFlight) يضمن أن
    // أي صندوق يُطلب فتحه من أكثر من مكان في نفس اللحظة تقريباً (مثال:
    // auth_box من هنا ومن SplashScreen معاً) لا يُفتح فعلياً إلا مرة
    // واحدة — كل الطلبات المتزامنة تتشارك نفس النتيجة. لكن الأنظف هو ألا
    // نطلب صندوقاً هنا أصلاً إلا إذا كنا سنستخدمه فعلياً في هذه الدالة.
  } catch (e, st) {
    // ✅ حماية إضافية: حتى لو حدث خطأ غير متوقع (مثال: فشل
    // Hive.initFlutter() ذاته)، لا يجب أن يصل هذا إلى الـ Zone الرئيسي
    // كـ crash قاتل — التطبيق ظاهر بالفعل للمستخدم عبر runApp() بحلول
    // هذه اللحظة.
    debugPrint('⚠️ Storage initialization failed (non-fatal, app already running): $e');
    if (Firebase.apps.isNotEmpty) {
      await _safeRecordError(
        e,
        st,
        reason: 'Deferred storage init failed after runApp()',
        fatal: false,
      );
    }
  }

  // ✅ يُستدعى بعد اكتمال (أو فشل) تهيئة التخزين — واجهة التطبيق تظهر
  // فورًا للمستخدم بغض النظر عن مدى سرعة/بطء تسجيل الإشعارات مع Apple أو
  // فتح الصناديق. الدالة نفسها معزولة بالكامل بـ try/catch فلا يمكن لأي
  // فشل بداخلها أن يصل لهذا الـ Zone أو يُسجَّل كـ fatal. هي التي تفتح
  // auth_box بنفسها (عند الحاجة فقط) بدل انتظار مرجع مُمرَّر لها.
  await _setupFirebaseMessaging();
}

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // =========================================================
    // ✅ تم النقل هنا: تفعيل وضع الأمان فوراً قبل أي شيء (حل N-03)
    // =========================================================
    await _enableSecureMode();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // =========================================================
    // ✅ تفعيل Firebase App Check (حماية الخوادم ضد المحاكي والروت)
    //
    // ✅ [FIX] كان هذا الاستدعاء بلا أي try/catch وبلا timeout، وكان يُستدعى
    // بشكل أعمى بغض النظر عن حالة الاتصال. وبما أنه يسبق runApp() (انظر
    // أسفل)، فإن فشله كان يوقف تنفيذ باقي main() **قبل الوصول إلى runApp()
    // إطلاقاً** — بالضبط نفس نمط مشكلتَي APNs وHive الموثقتين أعلاه/أسفل في
    // هذا الملف.
    //
    // لوحظ هذا تحديداً على بعض أجهزة Huawei في وضع Offline (يعمل بشكل طبيعي
    // Online على نفس الأجهزة). السبب الأرجح: كثير من أجهزة Huawei تعمل بنسخة
    // منقوصة/مُعدَّلة من Google Play Services (لأن هذه الأجهزة لا تأتي بـ
    // GMS أصلي من المصنع). على جهاز بخدمات Google كاملة، فشل استدعاء Play
    // Integrity يعود عادة كاستثناء Dart عادي يمكن التقاطه. على هذه النسخ
    // المُعدَّلة تحديداً، قد يُطلِق Play Services بدلاً من ذلك واجهة حل
    // الخطأ الأصلية الخاصة به (بالضبط الرسالة التي تظهر في تقرير الأعطال:
    // "Something went wrong / Check that Google Play is enabled...")، وهذه
    // الواجهة قد تظهر من كود أصلي (native) قبل أن تصل أصلاً كاستثناء إلى
    // try/catch في Dart.
    //
    // الحل بطبقتين:
    // 1) فحص الاتصال أولاً عبر connectivity_plus (المستخدمة بالفعل في
    //    bunny_tus_upload_service.dart وnative_video_player_screen.dart)،
    //    وتخطّي استدعاء activate() تماماً حين يكون الجهاز Offline — لتفادي
    //    استدعاء Play Integrity أصلاً وأي واجهة أصلية قد يُطلقها، بدل
    //    الاعتماد فقط على التقاط استثناء بعد وقوعه.
    // 2) الإبقاء على try/catch + timeout كخط دفاع ثانٍ لأي فشل آخر (جهاز
    //    Online لكن الشبكة بطيئة/غير مستقرة، أو أي خطأ غير متوقع).
    // في الحالتين: runApp() يُستدعى دائماً، والطلبات تُرسَل بدون هيدر
    // X-Firebase-AppCheck (الباك-إند يتعامل مع هذه الحالة عبر الـ
    // whitelist)، وFirebase App Check سيعاود المحاولة تلقائياً لاحقاً — إما
    // من تلقاء نفسه عند أول getToken() ناجح، أو عبر مستمع الاتصال بالأسفل.
    // =========================================================
    Future<void> activateAppCheck() async {
      try {
        await FirebaseAppCheck.instance
            .activate(
              // Play Integrity للأندرويد (الأقوى ضد الروت والتعديل) في وضع الإنتاج، أو Debug في وضع التطوير
              providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
              // ✅ App Attest مع DeviceCheck كـ fallback للأجهزة القديمة التي لا تدعم App Attest
              providerApple: kReleaseMode ? const AppleAppAttestWithDeviceCheckFallbackProvider() : const AppleDebugProvider(),
            )
            .timeout(const Duration(seconds: 5));
      } catch (e, stack) {
        // ✅ لا نمنع فتح التطبيق أبداً بسبب فشل/بطء App Check (خصوصاً في وضع
        // Offline أو على أجهزة بلا Google Play Services كاملة مثل Huawei).
        debugPrint('⚠️ FirebaseAppCheck.activate() failed or timed out (non-fatal, app continues): $e');
        if (Firebase.apps.isNotEmpty) {
          await _safeRecordError(
            e,
            stack,
            reason: 'FirebaseAppCheck.activate() failed at startup (non-fatal)',
            fatal: false,
          );
        }
      }
    }

    try {
      final connectivityResults =
          await Connectivity().checkConnectivity().timeout(const Duration(seconds: 3));
      final isOffline =
          connectivityResults.every((r) => r == ConnectivityResult.none);

      if (isOffline) {
        // ✅ Offline عند الإقلاع: لا نستدعي Play Integrity إطلاقاً الآن —
        // نتجنّب بذلك أي واجهة خطأ أصلية قد يُطلقها بنفسه على بعض الأجهزة
        // (Huawei خصوصاً). نحاول التفعيل مرة واحدة لاحقاً تلقائياً بمجرد
        // عودة الاتصال (fire-and-forget، لا يحجب أي شيء).
        debugPrint('⚠️ Device is offline at startup — skipping FirebaseAppCheck.activate() for now.');
        late final StreamSubscription<List<ConnectivityResult>> sub;
        sub = Connectivity().onConnectivityChanged.listen((results) {
          if (results.any((r) => r != ConnectivityResult.none)) {
            sub.cancel();
            activateAppCheck();
          }
        });
      } else {
        await activateAppCheck();
      }
    } catch (e) {
      // ✅ فشل فحص الاتصال نفسه (نادر) — لا نمنع الإقلاع، نحاول التفعيل
      // العادي (محمي بالفعل بـ try/catch + timeout داخل activateAppCheck).
      debugPrint('⚠️ Connectivity check before App Check activation failed: $e');
      await activateAppCheck();
    }
    // =========================================================

    // ✅ ربط دالة الخلفية بفايربيز لاستقبال الإشعارات والتطبيق مغلق
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FlutterError.onError = _handleFlutterFatalError;

    await NotificationService().init();
    
    // ✅ استدعاء التهيئة هنا
    await initializeBackgroundService();

    // Hive — [FIX F-06] All boxes now opened with encryption via StorageService
    //
    // ✅ [FIX] هذه الاستدعاءات كانت بلا أي try/catch من حولها، **وكانت
    // تُنفَّذ قبل runApp() وتحجبه** — أي أن التطبيق كان يحاول الوصول إلى
    // Keychain/Keystore قبل أن يُصبح "نشطاً" فعلياً بأي معنى (لا واجهة
    // مرسومة بعد، ولا حتى تأكيد أن حالة دورة الحياة resumed)، بالضبط
    // اللحظة الأكثر عرضة لسباق -25308. عندما تفشل، كان الاستثناء يصعد بلا
    // حماية ليتحول إلى كراش قاتل يمنع التطبيق من الوصول لـ runApp()
    // إطلاقاً (راجع تقرير Crashlytics: FlutterError عند
    // storage_service.dart:44 عبر main.dart:212).
    //
    // الآن: لا شيء هنا يحجب runApp() إطلاقاً. تهيئة Hive وفتح الصناديق
    // انتقلت بالكامل إلى _initStorageAfterAppReady() أسفل هذه الدالة،
    // والتي تُستدعى (fire-and-forget) بعد runApp() تماماً مثل
    // _setupFirebaseMessaging(). واجهة التطبيق تظهر فوراً بغض النظر عن
    // حالة التخزين الآمن، و StorageService._getKey() نفسها لديها الآن
    // بوابة داخلية (_AppReadyGate) تنتظر تأكيد أن الإطار الأول رُسم
    // وأن حالة دورة الحياة resumed قبل لمس Keychain — هذا يحمي أيضاً أي
    // مسار آخر يفتح صندوقاً لاحقاً (شاشات التطبيق المختلفة تفتح auth_box
    // عند الحاجة بشكل مستقل عن هذا الاستدعاء أصلاً).
    //
    // ✅ إعداد Firebase Messaging (الإذن + التوكن) انتُقل إلى ما بعد
    // runApp() أسفل هذه الدالة — انظر _setupFirebaseMessaging() أعلاه
    // لشرح السبب الكامل لهذا التغيير.

    // =========================================================================
    // ✅ إضافة كود التوجيه عند الضغط على الإشعار (Notification Click Handling)
    // =========================================================================
    
    // 1. إذا كان التطبيق مغلقاً تماماً (Terminated) وتم فتحه عن طريق الضغط على الإشعار
    //
    // ✅ [FIX] لم نعد نعتمد على تأخير ثابت (1500ms) كتخمين لوقت انتهاء
    // SplashScreen — كان هذا يفشل كلما استغرقت التهيئة الفعلية (طلب
    // الشبكة، فحص التحديث، حوار الشروط...) أكثر من 1.5 ثانية، وكان
    // أيضاً عرضة تماماً لمشكلة "الدفع فوق SplashScreen ثم مسحه" الموضحة
    // أعلاه عند AppReadySignal. الآن ننتظر الجاهزية الفعلية الحقيقية بدل
    // تخمين وقتها.
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        openNotificationsScreenWhenReady();
      }
    });

    // 2. إذا كان التطبيق يعمل في الخلفية (Background) وتم الضغط على الإشعار
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      openNotificationsScreenWhenReady();
    });
    // =========================================================================

    MediaKit.ensureInitialized();

    // ✅ إعداد جلسة الصوت
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.movie,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Security
    SecurityManager.instance.initListeners();
    // Start periodic check
    SecurityManager.instance.startPeriodicCheck();

    // ✅ [FIX] Theme/Locale full init (AppState().initTheme()/initLocale())
    // removed from here — see explanation below at runApp(). Both read
    // settings_box via StorageService, which now waits on _AppReadyGate —
    // and that gate cannot resolve before runApp() has run at least once.
    // Leaving those calls here would deadlock every single cold launch for
    // the full 5-second gate timeout.
    //
    // ✅ [FIX - root cause of "splash shows English then flips to Arabic
    // after ~2s"] However, doing *nothing* here meant the very first frame
    // was always painted with the hardcoded default locale ('en')/theme
    // (dark) in AppState's notifiers, regardless of what the user had
    // actually chosen last time — the real preference could only be read
    // from encrypted Hive storage after the gate opened, a moment after
    // that first frame. Below, we await a fast, *unencrypted* read from
    // SharedPreferences (not gated — see initLocaleFast()/initThemeFast()
    // docs in app_state.dart) so the notifiers already hold the correct
    // value before runApp() ever builds a frame. This is safe to await
    // here: SharedPreferences never touches Keychain/Keystore, so it can't
    // hit the -25308 race the gate exists to prevent.
    await AppState().initLocaleFast();
    await AppState().initThemeFast();

    runApp(
      SecureScreenWidget(useBlur: true,
        child: const RestartWidget(
          child: EduVantageApp(),
        ),
      ),
    );

    // ✅ [FIX] AppState().initTheme() و initLocale() تبقيان تُستدعيان هنا
    // أيضاً، بعد runApp() مباشرة (fire-and-forget)، كمصدر رسمي/نهائي
    // للتفضيل — لكنهما الآن ليستا المصدر الوحيد الذي يحدد أول إطار (راجع
    // initLocaleFast()/initThemeFast() المُستدعاتين أعلاه قبل runApp()
    // مباشرة، وشرحهما الكامل في app_state.dart).
    //
    // السبب في بقائهما هنا بعد runApp(): كلتاهما تستدعيان
    // StorageService.openBox('settings_box') داخلياً، وهذا الاستدعاء يمر
    // عبر _AppReadyGate في storage_service.dart — والتي لا يمكنها إطلاقاً
    // أن تتحقق (الإطار الأول + resumed) قبل أن يُستدعى runApp() فعلياً
    // ويُبنى الشجرة أول مرة. لو استُدعيتا قبل runApp() (وانتُظرتا)، لكان
    // كل إقلاع للتطبيق يتجمّد لمدة 5 ثوانٍ كاملة (مهلة الأمان القصوى في
    // البوابة) قبل ظهور أي واجهة على الإطلاق.
    //
    // بفضل initLocaleFast()/initThemeFast() أعلاه، القيمة التي يرسمها أول
    // إطار الآن هي غالباً نفسها التي ستؤكدها هاتان الدالتان من Hive، لذا
    // لا يوجد أي "وميض" ملحوظ بلغة أو ثيم مختلفين بعد اكتمالهما.
    unawaited(AppState().initTheme());
    unawaited(AppState().initLocale());

    // ✅ [FIX] تهيئة Hive تُستدعى الآن أيضاً بعد runApp() (fire-and-forget)
    // — انظر توثيق _initStorageAfterAppReady() أدناه. لم تعد main.dart
    // تفتح أي صندوق استباقياً هنا؛ _setupFirebaseMessaging() تفتح auth_box
    // بنفسها فقط عند الحاجة الفعلية لحفظ fcm_token.
    unawaited(_initStorageAfterAppReady());
  }, (error, stack) async {
    // ✅ الخطأ المعروف وغير الضار (راجع _isBenignAppCheckTokenListenerError
    // أدناه) لا يُرسَل إلى Crashlytics إطلاقاً الآن — لم يعد كافياً تخفيضه
    // فقط إلى non-fatal، لأنه كان لا يزال يُسجَّل كـ Issue متكرر في لوحة
    // Crashlytics رغم كونه غير قاتل (وهو نفس الـ Issue الذي كان يظهر هنا).
    if (_isBenignAppCheckTokenListenerError(error)) {
      debugPrint(
          '⚠️ Ignoring benign App Check token-listener MissingPluginException (not sent to Crashlytics): $error');
      return;
    }
    // ✅ راجع _isBenignVideoPlayerError أعلاه: أخطاء تشغيل الفيديو الطبيعية
    // (PlatformException برمز 'VideoError') تُسجَّل كغير قاتلة بدلاً من
    // قاتلة، لأنها مُعالَجة أصلاً داخل شاشة المشغّل ولا تمثل انهيارًا حقيقيًا
    // للتطبيق.
    if (_isBenignVideoPlayerError(error)) {
      debugPrint(
          '⚠️ Downgrading benign video-player PlatformException(VideoError) to non-fatal: $error');
      if (Firebase.apps.isNotEmpty) {
        await _safeRecordError(error, stack, fatal: false);
      }
      return;
    }
    if (Firebase.apps.isNotEmpty) {
      await _safeRecordError(error, stack, fatal: true);
    }
  });
}

// ✅ [REAL FIX — root cause of the persisting "-25308" fatal crashes] Every
// original error that reaches this zone's onError handler was ALREADY being
// reported via `FirebaseCrashlytics.instance.recordError(...)` directly,
// with no try/catch around it. That call is itself a MethodChannel call
// into native Crashlytics code, and Crashlytics internally touches the
// iOS Keychain (installation/session identifiers) to attach to the report.
// During exactly the same "device not fully unlocked yet / Data Protection
// still settling" window that causes our own Keychain reads to throw
// `PlatformException(-25308, "User interaction is not allowed.")`, the
// Crashlytics SDK's *own* Keychain access can throw the identical error.
//
// Previously that meant: a real (often already-handled, non-fatal) error
// arrives here -> we try to *report* it -> reporting itself throws -25308
// -> because this call was awaited with no try/catch inside an `async`
// onError callback, that second exception had nowhere left to go and
// became a genuinely unhandled, fatal crash of the whole app. This is
// exactly the second Crashlytics event in the report
// (`firebase_crashlytics.dart:119` inside `main.dart:520`): the crash
// wasn't the original bug, it was us crashing *while trying to log* the
// original bug. Every one of the 47+ other `recordError(...)` call sites
// in this app is fire-and-forget (not awaited), so if the native call
// throws, Dart forwards that as an unhandled zone error straight back to
// this same onError handler — meaning this single chokepoint was silently
// amplifying failures from anywhere in the app into a fatal crash.
//
// The fix: recording a crash report must never itself be allowed to crash
// the app. We swallow (and locally log) any failure from the recording
// call itself, with one short retry since -25308 here is transient (it
// clears the moment Data Protection finishes unlocking, same as our own
// Keychain reads). This changes nothing about *what* we protect with the
// Keychain (accessibility class, encryption, etc. are untouched) — it only
// stops a failed *report* of an error from becoming a worse, unrelated
// crash.
Future<void> _safeRecordError(
  Object error,
  StackTrace? stack, {
  required bool fatal,
  String? reason,
}) async {
  const attempts = 2;
  for (var i = 0; i < attempts; i++) {
    try {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: fatal, reason: reason);
      return;
    } catch (reportingError) {
      if (i < attempts - 1) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }
      // Give up reporting rather than let a failed *report* crash the app.
      debugPrint(
          '⚠️ Crashlytics.recordError itself failed (not re-thrown, '
          'original error preserved above only in debug log): '
          '$reportingError | original error was: $error');
    }
  }
}

Future<void> _enableSecureMode() async {
  try {
    await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE);
  } catch (e) {
    debugPrint("Security Mode Error: $e");
  }
}

// ✅ [إصلاح] "Fatal Exception: FlutterError — MissingPluginException(No
// implementation found for method listen on channel
// plugins.flutter.io/firebase_app_check/token/[DEFAULT])" كان يُسجَّل في
// Crashlytics كـ crash **قاتل** رغم أنه ليس كذلك فعليًا.
//
// السبب: حزمة firebase_app_check تبدأ تلقائيًا، فور أول وصول إلى
// FirebaseAppCheck.instance (داخل .activate() في main() أعلاه)، بالاستماع
// إلى EventChannel داخلي خاص بتحديثات الـ token — بمعزل تمامًا عن أي كود
// في تطبيقنا (نحن لا نستدعي onTokenChange في أي مكان — تم التحقق). الحزمة
// نفسها تلف هذا الإعداد بـ try/catch مع تعليق صريح من مطوّرها: "This can
// happen... Silently ignore errors during token listener registration."
// لكن هذا الـ catch يغطي فقط استدعاء التسجيل المتزامن؛ فشل "listen" نفسه
// (حين لا يكون المعالج الأصلي لهذه القناة مسجَّلاً على iOS) يحدث بشكل
// غير متزامن خارج نطاق ذلك الـ try، فيفلت كخطأ غير ملتقَط ويصل إلى
// FlutterError.onError أو إلى onError الخاص بـ runZonedGuarded — وكلاهما
// في هذا الملف كان يسجّل أي شيء يصله كـ fatal: true بلا أي تمييز.
//
// الحل: تمييز هذا النوع تحديدًا (MissingPluginException الخاص بقناة
// firebase_app_check/token) وتسجيله كخطأ غير قاتل (fatal: false) بدلاً من
// قاتل، تمامًا كما فُعل سابقًا مع أخطاء الشبكة. أي MissingPluginException
// أخرى (لقنوات مختلفة) تبقى تُعامل كقاتلة كما كانت، لتفادي إخفاء مشاكل
// حقيقية أخرى بنفس النوع من الاستثناءات.
bool _isBenignAppCheckTokenListenerError(Object error) {
  if (error is! MissingPluginException) return false;
  final message = error.message ?? '';
  return message.contains('firebase_app_check/token');
}

// ✅ [إصلاح] "Fatal Exception: PlatformException(VideoError, ...)" كان
// يُسجَّل في Crashlytics كـ crash **قاتل** رغم أنه ليس كذلك فعليًا.
//
// السبب: مشغلات الفيديو (better_player_plus / media_kit) تُبلّغ عن أخطاء
// تشغيل طبيعية وغير قاتلة (انقطاع شبكة مؤقت، رابط بث منتهي الصلاحية من
// Bunny، فشل مؤقت في فك الترميز...) عبر PlatformException برمز 'VideoError'
// على قناة المنصّة الخاصة بالمشغّل. هذه الأخطاء تُعالَج وتُعرَض للمستخدم
// بالفعل داخل شاشات المشغّل نفسها (انظر native_video_player_screen.dart —
// _handlePlayerError) — لكن نفس الاستثناء قد يفلت أيضًا بشكل غير متزامن من
// كود أصلي للمنصّة خارج نطاق أي try/catch في شجرة الودجت، فيصل إلى
// FlutterError.onError أو onError الخاص بـ runZonedGuarded، وكلاهما كان
// يسجّل أي شيء يصله كـ fatal: true بلا تمييز — فيُحتسَب كـ crash حقيقي يؤثر
// على نسبة "crash-free users" رغم أن المستخدم لم ير أي انهيار فعلي للتطبيق،
// فقط رسالة خطأ عادية داخل شاشة الفيديو.
//
// الحل: تمييز هذا النوع تحديدًا (PlatformException برمز 'VideoError') —
// بنفس نمط _isBenignAppCheckTokenListenerError أعلاه تمامًا — وتسجيله كخطأ
// غير قاتل (fatal: false) بدلاً من قاتل. أي PlatformException آخر (رموز
// مختلفة) يبقى يُعامَل كقاتل كما كان، لتفادي إخفاء مشاكل حقيقية أخرى بنفس
// النوع من الاستثناءات.
bool _isBenignVideoPlayerError(Object error) {
  if (error is! PlatformException) return false;
  return error.code == 'VideoError';
}

/// Wraps [FirebaseCrashlytics.instance.recordFlutterFatalError] so the known
/// benign App Check token-listener [MissingPluginException] (see comment on
/// [_isBenignAppCheckTokenListenerError]) is recorded as non-fatal instead of
/// crashing the crash-free rate for something that isn't a real crash.
Future<void> _handleFlutterFatalError(FlutterErrorDetails details) async {
  if (_isBenignAppCheckTokenListenerError(details.exception)) {
    debugPrint(
        '⚠️ Ignoring benign App Check token-listener MissingPluginException (non-fatal): ${details.exception}');
    if (Firebase.apps.isNotEmpty) {
      await FirebaseCrashlytics.instance
          .recordError(details.exception, details.stack, fatal: false);
    }
    return;
  }
  // ✅ راجع _isBenignVideoPlayerError أعلاه.
  if (_isBenignVideoPlayerError(details.exception)) {
    debugPrint(
        '⚠️ Downgrading benign video-player PlatformException(VideoError) to non-fatal: ${details.exception}');
    if (Firebase.apps.isNotEmpty) {
      await FirebaseCrashlytics.instance
          .recordError(details.exception, details.stack, fatal: false);
    }
    return;
  }
  await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
}
