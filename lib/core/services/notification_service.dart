import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ✅ إضافة استيراد Material لـ MaterialPageRoute
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// ✅ استيراد مكتبات فايربيز
import 'package:firebase_messaging/firebase_messaging.dart';

// ✅ استيراد المفتاح الخاص بالتوجيه ودالة التوجيه الآمنة (تنتظر اكتمال
// تهيئة السبلاش قبل الدفع — راجع main.dart)
import '../../main.dart';
// ✅ [FIX] استخدام StorageService.openBox() بدل Hive.openBox() المباشرة —
// auth_box صندوق مُشفَّر دائماً (HiveAesCipher)، وفتحه هنا مباشرة عبر Hive
// بلا مفتاح تشفير كان يتجاوز قفل التزامن وبوابة الجاهزية في
// StorageService (نفس المشكلة المُصلَحة في notifications_screen.dart).
import 'storage_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    // 1. تهيئة البلاغن
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // ✅ [FIX] التعامل مع الضغط على الإشعار الداخلي (محلي أو FCM
        // والتطبيق مفتوح/بالخلفية) وتوجيهه لشاشة الإشعارات — عبر نفس
        // الدالة المُستخدَمة في main.dart (getInitialMessage/
        // onMessageOpenedApp) بدل تكرار منطق التنقل هنا. هذه الدالة تنتظر
        // اكتمال تهيئة SplashScreen فعلياً (AppReadySignal) قبل الدفع، وتمنع
        // أي دفع متكرر إن وصلت أكثر من إشارة ضغط في نفس اللحظة تقريباً.
        openNotificationsScreenWhenReady();
      },
    );

    // 2. طلب الأذونات (أندرويد 13+)
    final androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();

    // ✅ طلب إذن الإشعارات على iOS
    final iOSImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iOSImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. إنشاء قنوات الإشعارات يدوياً لتفادي RemoteServiceException
    if (androidImplementation != null) {
      // القناة الأولى: للتحميل (صامتة للـ Foreground Service)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'downloads_channel',
          'Active Downloads',
          description: 'Shows progress of active downloads',
          importance: Importance.low,
          playSound: false,
          showBadge: false,
        ),
      );

      // القناة الثانية: عند اكتمال التحميل (بصوت)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'download_completed_channel',
          'Download Completed',
          description: 'Notifies when a download finishes',
          importance: Importance.high,
          playSound: true,
        ),
      );

      // ✅ القناة الثالثة: إشعارات فايربيز (عندما يكون التطبيق مفتوحاً)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'fcm_channel',
          'General Notifications',
          description: 'Important alerts and updates',
          importance: Importance.max, // Max = يظهر كانبثاق (Heads-up)
          playSound: true,
        ),
      );
    }

    // ✅ 4. تشغيل مستمع إشعارات فايربيز أثناء فتح التطبيق
    _listenToForegroundMessages();
  }

  // ==========================================
  // ✅ دوال فايربيز الجديدة (FCM)
  // ==========================================

  // ✅ [FIX] مهلة زمنية لكل عملية اشتراك/إلغاء اشتراك على حدة. بعض أجهزة
  // Huawei (بدون خدمات Google Play كاملة/أصلية) لا تُرجع أي استثناء عند فشل
  // subscribeToTopic/unsubscribeFromTopic — الـ Future ببساطة لا يكتمل أبداً
  // لأن الاستدعاء الأصلي ينتظر توكن FCM من Play Services الذي لن يصل. بدون
  // هذه المهلة، أي await على updateSubscriptions() (من شاشتي تسجيل الدخول
  // والـ Splash) كان يُعلَّق التطبيق إلى الأبد رغم نجاح كل استدعاءات الـ API
  // فعلياً (login و get-app-init-data)، لأن التعليق يحدث بعدهما مباشرة هنا.
  static const Duration _topicOpTimeout = Duration(seconds: 5);

  // دالة ذكية للاشتراك في القنوات وإلغاء القديمة
  Future<void> updateSubscriptions(List<String> newTopics) async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      var authBox = await StorageService.openBox('auth_box');

      // جلب القنوات القديمة التي كان مشتركاً بها مسبقاً
      List<String> oldTopics = authBox.get('subscribed_topics', defaultValue: <String>[]).cast<String>();

      // إلغاء الاشتراك من القنوات التي لم تعد موجودة في حساب الطالب (انتهى اشتراكه فيها)
      for (String oldTopic in oldTopics) {
        if (!newTopics.contains(oldTopic)) {
          try {
            await messaging.unsubscribeFromTopic(oldTopic).timeout(_topicOpTimeout);
            debugPrint("Unsubscribed from FCM Topic: $oldTopic");
          } catch (e, s) {
            // ✅ لا نوقف باقي القنوات بسبب فشل/تعليق قناة واحدة (خصوصاً على
            // أجهزة Huawei) — نُسجّل الخطأ ونكمل.
            debugPrint("⚠️ Failed/timed out unsubscribing from $oldTopic: $e");
            FirebaseCrashlytics.instance.recordError(
              e, s,
              reason: 'Timed out/failed unsubscribing from FCM topic (possibly GMS-less device)',
              fatal: false,
            );
          }
        }
      }

      // الاشتراك في القنوات الجديدة
      for (String topic in newTopics) {
        if (!oldTopics.contains(topic)) {
          try {
            await messaging.subscribeToTopic(topic).timeout(_topicOpTimeout);
            debugPrint("Subscribed to FCM Topic: $topic");
          } catch (e, s) {
            debugPrint("⚠️ Failed/timed out subscribing to $topic: $e");
            FirebaseCrashlytics.instance.recordError(
              e, s,
              reason: 'Timed out/failed subscribing to FCM topic (possibly GMS-less device)',
              fatal: false,
            );
          }
        }
      }

      // حفظ القائمة الجديدة للاستخدام في المرة القادمة
      await authBox.put('subscribed_topics', newTopics);
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to update FCM subscriptions');
    }
  }

  // مستمع الإشعارات والتطبيق مفتوح
  void _listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');

      if (message.notification != null) {
        _showForegroundFCMNotification(message);
      }
    });
  }

  // عرض الإشعار المنبثق برمجياً
  Future<void> _showForegroundFCMNotification(RemoteMessage message) async {
    const String channelId = 'fcm_channel';

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      'General Notifications',
      channelDescription: 'Important alerts and updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/launcher_icon', // أيقونة التطبيق
    );

    // ✅ إضافة إعدادات iOS
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      message.notification.hashCode, // توليد ID فريد بناء على الرسالة
      message.notification?.title,
      message.notification?.body,
      platformChannelSpecifics,
    );
  }

  // ==========================================
  // دوال الإشعارات القديمة (التحميلات)
  // ==========================================

  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e, s) {
      FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'Failed to cancel all notifications');
    }
  }

  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    const String channelId = 'downloads_channel';

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      'Active Downloads',
      channelDescription: 'Shows progress of active downloads',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
      playSound: false,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: const DarwinNotificationDetails(
        presentAlert: false,
        presentSound: false,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> showCompletionNotification({
    required int id,
    required String title,
    required bool isSuccess,
  }) async {
    const String channelId = 'download_completed_channel';

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      'Download Completed',
      channelDescription: 'Notifies when a download finishes',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      ongoing: false,
      autoCancel: true,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      isSuccess ? 'Download Complete' : 'Download Failed',
      isSuccess ? '$title has been downloaded.' : 'Failed to download $title.',
      platformChannelSpecifics,
    );
  }
}
