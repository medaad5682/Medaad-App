// lib/core/services/push/hms_push_provider.dart
// ------------------------------------------------------------------
// مزوّد HMS (Huawei Push Kit) لأجهزة هواوي بدون خدمات Google.
//
// ملاحظات تصميم:
//  - huawei_push و firebase_messaging يعرّفان كلاهما RemoteMessage، لذلك
//    تُستورد huawei_push هنا فقط وبـ prefix (hms).
//  - Push.getToken(scope) لا يعيد التوكن مباشرة؛ التوكن يصل عبر
//    Push.getTokenStream، فنخزّنه ونوفّره عبر getToken().
//  - كل التعامل مع كائنات huawei_push يتم بحذر (dynamic + try/catch) كي لا
//    يؤدي اختلاف بسيط في شكل الرسالة إلى كراش.
//
// الإشعارات (خطوة 14):
//  - السيرفر يرسل رسائل "notification" فقط (lib/hmsPush.js). النظام (HMS Core)
//    هو من يعرضها دائماً، حتى والتطبيق في الواجهة، لأن foreground_show غير
//    مضبوط (القيمة الافتراضية true) — وفي هذه الحالة لا يستلم التطبيق محتوى
//    الرسالة أصلاً. لذلك لا نعرض أبداً إشعاراً محلياً لرسائل HMS (انظر
//    onForegroundMessage) فلا يظهر إشعاران.
//  - الضغط على الإشعار يُكتشف من مصدرين، ويُزال تكرارهما في main.dart:
//      1) huawei_push: Push.getInitialNotification / Push.onNotificationOpenedApp
//      2) intent أصلي بـ action = FLUTTER_NOTIFICATION_CLICK (click_action type 1
//         في الرسالة + intent-filter في AndroidManifest) تلتقطه MainActivity.kt
//         وتمرّره عبر MethodChannel. هذا المسار حتمي ولا يعتمد على شكل ما
//         تعيده الإضافة.
// ------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:huawei_push/huawei_push.dart' as hms;
import 'package:permission_handler/permission_handler.dart';

import 'push_provider.dart';

class HmsPushProvider implements PushProvider {
  // نفس اسم القناة في MainActivity.kt
  static const MethodChannel _tapChannel =
      MethodChannel('medaad.app.com/notification_tap');

  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();

  // كل ضغطات الإشعارات (من الإضافة ومن الـ intent الأصلي) تمرّ من هنا.
  final StreamController<PushMessage> _openedController =
      StreamController<PushMessage>.broadcast();

  StreamSubscription<dynamic>? _tokenSub;
  StreamSubscription<dynamic>? _openedSub;
  Completer<String?>? _pendingToken;
  String? _lastToken;
  bool _initialized = false;

  @override
  String get name => 'hms';

  // ---------------------------------------------------------------
  // initialize
  // ---------------------------------------------------------------
  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // المستمعون أولاً: نافذة إذن الإشعارات أدناه قد تبقى مفتوحة وقتاً، ولا نريد
    // أن يضيع توكن أو ضغطة إشعار وصلا أثناءها.
    try {
      _tokenSub = hms.Push.getTokenStream.listen(
        _handleToken,
        onError: _handleTokenError,
      );
    } catch (e) {
      debugPrint('⚠️ [push/hms] failed to listen to token stream: $e');
    }

    _listenForNotificationTaps();

    // إذن الإشعارات على أندرويد 13+ (huawei_push لا يوفّر requestPermission).
    try {
      final status = await Permission.notification.request();
      debugPrint('🔔 [push/hms] notification permission: $status');
    } catch (e) {
      debugPrint('⚠️ [push/hms] notification permission request failed: $e');
    }
  }

  /// يربط مصدرَي "المستخدم ضغط على إشعار والتطبيق يعمل في الخلفية".
  void _listenForNotificationTaps() {
    // 1) إضافة huawei_push. أي حدث على هذا الـ stream هو ضغطة فعلاً.
    try {
      _openedSub = hms.Push.onNotificationOpenedApp.listen(
        (dynamic event) => _emitOpened(_fromOpenedNotification(event)),
        onError: (Object e) =>
            debugPrint('⚠️ [push/hms] opened stream error: $e'),
      );
    } catch (e) {
      debugPrint('⚠️ [push/hms] failed to listen to onNotificationOpenedApp: $e');
    }

    // 2) الـ intent الأصلي (MainActivity.onNewIntent -> هذه القناة).
    try {
      _tapChannel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onNotificationTap') {
          _emitOpened(const PushMessage(data: <String, String>{'source': 'intent'}));
        }
        return null;
      });
    } catch (e) {
      debugPrint('⚠️ [push/hms] failed to listen to native tap channel: $e');
    }
  }

  void _emitOpened(PushMessage message) {
    if (!_openedController.isClosed) _openedController.add(message);
  }

  void _handleToken(dynamic token) {
    final String? value = token?.toString();
    if (value == null || value.isEmpty) return;
    _lastToken = value;
    if (!_tokenController.isClosed) _tokenController.add(value);
    final pending = _pendingToken;
    if (pending != null && !pending.isCompleted) pending.complete(value);
  }

  void _handleTokenError(Object error) {
    debugPrint('⚠️ [push/hms] token error: $error');
    final pending = _pendingToken;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  // ---------------------------------------------------------------
  // token
  // ---------------------------------------------------------------
  @override
  Future<String?> getToken({Duration? timeout}) async {
    if (_lastToken != null) return _lastToken;
    try {
      await initialize();

      final completer = Completer<String?>();
      _pendingToken = completer;

      // لا يعيد التوكن؛ النتيجة تصل عبر getTokenStream (انظر _handleToken).
      hms.Push.getToken('');

      return await completer.future.timeout(
        timeout ?? const Duration(seconds: 15),
        onTimeout: () => null,
      );
    } catch (e) {
      debugPrint('⚠️ [push/hms] getToken failed: $e');
      return null;
    } finally {
      _pendingToken = null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _tokenController.stream;

  // ---------------------------------------------------------------
  // topics
  // ---------------------------------------------------------------
  @override
  Future<void> subscribeToTopic(String topic) async {
    // الاشتراك يحتاج توكن جاهزاً.
    if (_lastToken == null) {
      await getToken(timeout: const Duration(seconds: 10));
    }
    await hms.Push.subscribe(topic);
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    await hms.Push.unsubscribe(topic);
  }

  // ---------------------------------------------------------------
  // messages
  // ---------------------------------------------------------------

  /// رسائل وصلت إلى التطبيق وهو مفتوح.
  ///
  /// إشعارات HMS العادية يعرضها النظام بنفسه (انظر تعليق أعلى الملف)، ولا
  /// تصل هنا أصلاً غالباً. وكإجراء احتياطي صريح: إن وصلت رسالة هنا بعنوان
  /// ونص (مثلاً بعد تغيير مستقبلي في السيرفر) نمرّرها بدونهما، لأن
  /// NotificationService يعرض إشعاراً محلياً فقط عندما يجد عنواناً أو نصاً —
  /// وهذا سيعني إشعارين للمستخدم (واحد من النظام وواحد محلي).
  @override
  Stream<PushMessage> get onForegroundMessage {
    return hms.Push.onMessageReceivedStream
        .handleError((Object e) => debugPrint('⚠️ [push/hms] message stream error: $e'))
        .map((dynamic raw) {
      final PushMessage m = _fromRemoteMessage(raw);
      return PushMessage(id: m.id, data: m.data); // بلا title/body عمداً
    });
  }

  @override
  Stream<PushMessage> get onMessageOpenedApp => _openedController.stream;

  @override
  Future<PushMessage?> getInitialMessage() async {
    // 1) الـ intent الأصلي: الأوثق. القيمة تُستهلك (تعود true مرة واحدة فقط).
    try {
      final bool? launchedByTap =
          await _tapChannel.invokeMethod<bool>('consumeLaunchTap');
      if (launchedByTap == true) {
        return const PushMessage(data: <String, String>{'source': 'intent'});
      }
    } catch (e) {
      // MissingPluginException (نسخة MainActivity بدون القناة) أو غيرها: نكمل.
      debugPrint('ℹ️ [push/hms] native launch-tap check unavailable: $e');
    }

    // 2) إضافة huawei_push. هذه دالة "سحب" قد تعيد خريطة غير فارغة حتى في
    // تشغيل عادي، لذلك لا نقبلها إلا إن حملت أثر رسالة/ضغطة فعلاً.
    try {
      final dynamic initial = await hms.Push.getInitialNotification();
      if (_looksLikeNotificationTap(initial)) {
        return _fromOpenedNotification(initial);
      }
    } catch (e) {
      debugPrint('⚠️ [push/hms] getInitialNotification failed: $e');
    }
    return null;
  }

  /// هل تحمل النتيجة أثر ضغطة حقيقية على إشعار؟ (تفادي فتح شاشة الإشعارات في
  /// كل تشغيل عادي إن أعادت الإضافة خريطة بحقول فارغة.)
  bool _looksLikeNotificationTap(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return false;

    bool filled(dynamic v) {
      if (v == null) return false;
      if (v is Map) return v.isNotEmpty;
      if (v is Iterable) return v.isNotEmpty;
      if (v is String) return v.trim().isNotEmpty;
      return true;
    }

    if (filled(raw['uriPage'])) return true;
    if (filled(raw['remoteMessage'])) return true;
    if (filled(raw['messageId'])) return true;
    if (filled(raw['notification'])) return true;
    if (filled(raw['data'])) return true;

    // extras يحمل مفاتيح مثل _push_msgid عند فتح التطبيق من إشعار Push Kit.
    final dynamic extras = raw['extras'];
    if (extras is Map) {
      for (final dynamic key in extras.keys) {
        if ('$key'.toLowerCase().contains('push')) return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------
  // conversions (defensive: any field may be missing)
  // ---------------------------------------------------------------
  PushMessage _fromRemoteMessage(dynamic message) {
    String? id;
    String? title;
    String? body;
    final data = <String, String>{};

    try {
      id = message.messageId?.toString();
    } catch (_) {}

    try {
      final dynamic notification = message.notification;
      title = notification?.title?.toString();
      body = notification?.body?.toString();
    } catch (_) {}

    try {
      final dynamic map = message.dataOfMap;
      if (map is Map) {
        map.forEach((k, v) => data['$k'] = '$v');
      }
    } catch (_) {}

    // السيرفر يرسل data كنص JSON واحد (انظر lib/hmsPush.js).
    if (data.isEmpty) {
      try {
        final dynamic raw = message.data;
        if (raw is String && raw.isNotEmpty) {
          final dynamic decoded = jsonDecode(raw);
          if (decoded is Map) {
            decoded.forEach((k, v) => data['$k'] = '$v');
          }
        }
      } catch (_) {}
    }

    return PushMessage(id: id, title: title, body: body, data: data);
  }

  PushMessage _fromOpenedNotification(dynamic notification) {
    final data = <String, String>{};
    try {
      if (notification is Map) {
        notification.forEach((k, v) => data['$k'] = '$v');
      }
    } catch (_) {}
    return PushMessage(data: data);
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _openedSub?.cancel();
    await _tokenController.close();
    await _openedController.close();
  }
}
