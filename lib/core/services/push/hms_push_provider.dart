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
// ------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:huawei_push/huawei_push.dart' as hms;
import 'package:permission_handler/permission_handler.dart';

import 'push_provider.dart';

class HmsPushProvider implements PushProvider {
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _tokenSub;
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

    // إذن الإشعارات على أندرويد 13+ (huawei_push لا يوفّر requestPermission).
    try {
      final status = await Permission.notification.request();
      debugPrint('🔔 [push/hms] notification permission: $status');
    } catch (e) {
      debugPrint('⚠️ [push/hms] notification permission request failed: $e');
    }

    try {
      _tokenSub = hms.Push.getTokenStream.listen(
        _handleToken,
        onError: _handleTokenError,
      );
    } catch (e) {
      debugPrint('⚠️ [push/hms] failed to listen to token stream: $e');
    }
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
  @override
  Stream<PushMessage> get onForegroundMessage {
    return hms.Push.onMessageReceivedStream
        .handleError((Object e) => debugPrint('⚠️ [push/hms] message stream error: $e'))
        .map(_fromRemoteMessage);
  }

  @override
  Stream<PushMessage> get onMessageOpenedApp {
    return hms.Push.onNotificationOpenedApp
        .handleError((Object e) => debugPrint('⚠️ [push/hms] opened stream error: $e'))
        .map(_fromOpenedNotification);
  }

  @override
  Future<PushMessage?> getInitialMessage() async {
    try {
      final dynamic initial = await hms.Push.getInitialNotification();
      if (initial == null) return null;
      if (initial is Map && initial.isEmpty) return null;
      return _fromOpenedNotification(initial);
    } catch (e) {
      debugPrint('⚠️ [push/hms] getInitialNotification failed: $e');
      return null;
    }
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
    await _tokenController.close();
  }
}
