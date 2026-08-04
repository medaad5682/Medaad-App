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
Future<void> _setupFirebaseMessaging(dynamic authBox) async {
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
      // ✅ [FIX] authBox قد تكون null الآن إذا فشل فتح auth_box بأمان عند
      // الإقلاع (راجع _openBoxSafely). لا نريد رمي استثناء آخر هنا.
      await authBox?.put('fcm_token', fcmToken);
    }
  } catch (e, stack) {
    // ✅ أي فشل هنا (بما فيه FlutterError من _APNSTokenCheck) يُسجَّل كخطأ
    // غير قاتل ولا يؤثر إطلاقًا على بقية التطبيق.
    debugPrint('⚠️ Firebase Messaging setup failed (non-fatal): $e');
    if (Firebase.apps.isNotEmpty) {
      await FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
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
      await FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'Startup: could not open Hive box "$boxName" (app continues without it)',
        fatal: false,
      );
    }
    return null;
  }
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
    // =========================================================
    await FirebaseAppCheck.instance.activate(
      // Play Integrity للأندرويد (الأقوى ضد الروت والتعديل) في وضع الإنتاج، أو Debug في وضع التطوير
      providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
      // ✅ App Attest مع DeviceCheck كـ fallback للأجهزة القديمة التي لا تدعم App Attest
      providerApple: kReleaseMode ? const AppleAppAttestWithDeviceCheckFallbackProvider() : const AppleDebugProvider(),
    );
    // =========================================================

    // ✅ ربط دالة الخلفية بفايربيز لاستقبال الإشعارات والتطبيق مغلق
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FlutterError.onError = _handleFlutterFatalError;

    await NotificationService().init();
    
    // ✅ استدعاء التهيئة هنا
    await initializeBackgroundService();

    // Hive — [FIX F-06] All boxes now opened with encryption via StorageService
    //
    // ✅ [FIX] هذه الاستدعاءات كانت بلا أي try/catch من حولها. عندما كانت
    // StorageService.openBox() تفشل بشكل غير متوقع (راجع تقرير
    // Crashlytics: FlutterError عند storage_service.dart:44 عبر
    // main.dart:212)، كان الاستثناء يصعد بلا حماية ليتحول إلى كراش قاتل
    // يمنع التطبيق من الوصول لـ runApp() إطلاقاً. الآن: نلتقط أي فشل هنا
    // (بما فيه StorageKeyUnavailableException) ونكمل الإقلاع بأمان —
    // التطبيق سيُقلع بحالة "بدون جلسة محفوظة مؤقتاً" بدل أن ينهار كلياً،
    // وستُسترجع البيانات تلقائياً في المحاولة التالية عندما يعود التخزين
    // الآمن للعمل الطبيعي، دون أن يتم حذف أي بيانات.
    await Hive.initFlutter();
    Box? authBox = await _openBoxSafely('auth_box');
    await _openBoxSafely('settings_box');
    await _openBoxSafely('downloads_box');
    await _openBoxSafely('pdf_drawings_db');

    // ✅ إعداد Firebase Messaging (الإذن + التوكن) انتُقل إلى ما بعد
    // runApp() أسفل هذه الدالة — انظر _setupFirebaseMessaging() أعلاه
    // لشرح السبب الكامل لهذا التغيير.

    // =========================================================================
    // ✅ إضافة كود التوجيه عند الضغط على الإشعار (Notification Click Handling)
    // =========================================================================
    
    // 1. إذا كان التطبيق مغلقاً تماماً (Terminated) وتم فتحه عن طريق الضغط على الإشعار
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.push(
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
        });
      }
    });

    // 2. إذا كان التطبيق يعمل في الخلفية (Background) وتم الضغط على الإشعار
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(builder: (context) => const NotificationsScreen()),
        );
      }
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

    // Theme
    await AppState().initTheme();

    // Locale (EN/AR)
    await AppState().initLocale();

    runApp(
      SecureScreenWidget(useBlur: true,
        child: const RestartWidget(
          child: EduVantageApp(),
        ),
      ),
    );

    // ✅ يُستدعى بعد runApp() عن قصد (fire-and-forget) — واجهة التطبيق
    // تظهر فورًا للمستخدم بغض النظر عن مدى سرعة/بطء تسجيل الإشعارات مع
    // Apple. الدالة نفسها معزولة بالكامل بـ try/catch فلا يمكن لأي فشل
    // بداخلها أن يصل لهذا الـ Zone أو يُسجَّل كـ fatal.
    unawaited(_setupFirebaseMessaging(authBox));
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
        await FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      }
      return;
    }
    if (Firebase.apps.isNotEmpty) {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
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
