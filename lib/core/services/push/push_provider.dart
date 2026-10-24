// lib/core/services/push/push_provider.dart
// ------------------------------------------------------------------
// واجهة موحّدة لمزوّدي الإشعارات (FCM / HMS).
// باقي التطبيق يتعامل مع PushService فقط ولا يهمه أي مزوّد يعمل فعلياً.
// ------------------------------------------------------------------

import 'dart:async';

/// رسالة إشعار محايدة (لا ترتبط بـ firebase_messaging ولا huawei_push).
class PushMessage {
  final String? id;
  final String? title;
  final String? body;

  /// بيانات التوجيه القادمة من السيرفر (type / id / ...). كل القيم نصوص.
  final Map<String, String> data;

  const PushMessage({
    this.id,
    this.title,
    this.body,
    this.data = const <String, String>{},
  });

  @override
  String toString() => 'PushMessage(id: $id, title: $title, data: $data)';
}

abstract class PushProvider {
  /// 'fcm' أو 'hms' — نفس القيم التي يقبلها السيرفر في x-push-provider.
  String get name;

  /// تجهيز المزوّد (طلب الإذن، فتح الـ streams). آمنة للاستدعاء أكثر من مرة
  /// ولا ترمي استثناءً أبداً.
  Future<void> initialize();

  /// يعيد توكن الجهاز، أو null إذا لم يتوفر (لا خدمات / لا شبكة / انتهت المهلة).
  /// لا يرمي استثناءً.
  Future<String?> getToken({Duration? timeout});

  /// يصدر عند تغيّر التوكن لاحقاً.
  Stream<String> get onTokenRefresh;

  /// الاشتراك / إلغاء الاشتراك في topic. يرميان استثناءً عند الفشل
  /// (المستدعي — NotificationService — يغلّفهما بمهلة و try/catch).
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);

  /// رسالة وصلت والتطبيق مفتوح.
  Stream<PushMessage> get onForegroundMessage;

  /// المستخدم ضغط على إشعار والتطبيق في الخلفية.
  Stream<PushMessage> get onMessageOpenedApp;

  /// المستخدم فتح التطبيق (من حالة الإغلاق التام) بالضغط على إشعار، وإلا null.
  Future<PushMessage?> getInitialMessage();
}
