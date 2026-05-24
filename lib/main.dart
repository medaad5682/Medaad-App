import 'dart:async';
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

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ ربط دالة الخلفية بفايربيز لاستقبال الإشعارات والتطبيق مغلق
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    await NotificationService().init();
    
    // ✅ استدعاء التهيئة هنا
    await initializeBackgroundService();

    // Hive — [FIX F-06] All boxes now opened with encryption via StorageService
    await Hive.initFlutter();
    var authBox = await StorageService.openBox('auth_box');
    await StorageService.openBox('settings_box');
    await StorageService.openBox('downloads_box');
    await StorageService.openBox('pdf_drawings_db');

    // ✅ طلب إذن الإشعارات من المستخدم وجلب التوكن وحفظه في Hive
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // [FIX F-07] FCM token log is now debug-only (stripped in release builds)
    String? fcmToken = await messaging.getToken();
    assert(() {
      debugPrint("🔥 FCM Token: $fcmToken");
      return true;
    }());

    if (fcmToken != null) {
      await authBox.put('fcm_token', fcmToken);
    }

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

    await _enableSecureMode();

    // Security
    SecurityManager.instance.initListeners();
    // Start periodic check
    SecurityManager.instance.startPeriodicCheck();

    // Theme
    await AppState().initTheme();

    runApp(
      SecureScreenWidget(useBlur: true,
        child: const RestartWidget(
          child: EduVantageApp(),
        ),
      ),
    );
  }, (error, stack) async {
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
