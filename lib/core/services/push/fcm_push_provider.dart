// lib/core/services/push/fcm_push_provider.dart
// ------------------------------------------------------------------
// مزوّد FCM: يغلّف نفس الاستدعاءات التي كانت موجودة في main.dart
// (إذن الإشعارات، انتظار APNs على iOS، جلب التوكن) دون تغيير سلوكها.
// ------------------------------------------------------------------

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_provider.dart';

class FcmPushProvider implements PushProvider {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  bool _initialized = false;

  @override
  String get name => 'fcm';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('🔔 [push/fcm] permission: ${settings.authorizationStatus}');

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('⚠️ [push/fcm] initialize failed (non-fatal): $e');
    }
  }

  @override
  Future<String?> getToken({Duration? timeout}) async {
    try {
      // على iOS: انتظر وصول APNs token قبل طلب FCM token (نفس منطق main.dart القديم).
      if (Platform.isIOS) {
        String? apnsToken = await _messaging.getAPNSToken();
        var attempts = 0;
        while (apnsToken == null && attempts < 10) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging.getAPNSToken();
          attempts++;
        }
        if (apnsToken == null) {
          debugPrint('⚠️ [push/fcm] APNs token not available — skipping FCM token for now');
          return null;
        }
      }

      final Future<String?> request = _messaging.getToken();
      final String? token =
          timeout == null ? await request : await request.timeout(timeout);
      return (token != null && token.isNotEmpty) ? token : null;
    } on TimeoutException {
      debugPrint('⚠️ [push/fcm] getToken timed out');
      return null;
    } catch (e) {
      debugPrint('⚠️ [push/fcm] getToken failed: $e');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> subscribeToTopic(String topic) => _messaging.subscribeToTopic(topic);

  @override
  Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_convert);

  @override
  Stream<PushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_convert);

  @override
  Future<PushMessage?> getInitialMessage() async {
    try {
      final RemoteMessage? message = await _messaging.getInitialMessage();
      return message == null ? null : _convert(message);
    } catch (e) {
      debugPrint('⚠️ [push/fcm] getInitialMessage failed: $e');
      return null;
    }
  }

  PushMessage _convert(RemoteMessage message) {
    return PushMessage(
      id: message.messageId,
      title: message.notification?.title,
      body: message.notification?.body,
      data: message.data.map(
        (key, value) => MapEntry<String, String>(key, value?.toString() ?? ''),
      ),
    );
  }
}
