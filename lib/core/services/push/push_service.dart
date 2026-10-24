// lib/core/services/push/push_service.dart
// ------------------------------------------------------------------
// نقطة الدخول الوحيدة للإشعارات في التطبيق.
//
// عند الإقلاع يختار مزوّداً واحداً:
//   iOS                      -> FCM (بدون أي تغيير عن السلوك الحالي)
//   Android + GMS فقط        -> FCM
//   Android + HMS فقط        -> HMS   (لا يلمس FirebaseMessaging إطلاقاً)
//   Android + الاثنان معاً   -> يجرّب FCM لمدة قصيرة، فإن لم يعطِ توكن => HMS
//   لا شيء متوفر             -> يعمل التطبيق بدون إشعارات
//
// يحفظ في auth_box:
//   push_provider : 'fcm' | 'hms'
//   push_token    : توكن المزوّد الحالي
//   fcm_token     : (للتوافق مع الكود الحالي) يُحفظ فقط عند اختيار FCM
// ------------------------------------------------------------------

import 'dart:async';
import 'dart:io' show Platform;

import 'package:Medaad/core/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hms_gms_availability/flutter_hms_gms_availability.dart';

import 'fcm_push_provider.dart';
import 'hms_push_provider.dart';
import 'push_provider.dart';

class _Selection {
  final PushProvider provider;
  final String? token; // قد يكون جُلب أثناء الاختيار
  const _Selection(this.provider, this.token);
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  // مفاتيح auth_box
  static const String _kProviderKey = 'push_provider';
  static const String _kTokenKey = 'push_token';
  static const String _kLegacyFcmTokenKey = 'fcm_token';

  // مهل زمنية
  static const Duration _fcmProbeTimeout = Duration(seconds: 5);
  static const Duration _fcmTokenTimeout = Duration(seconds: 30);
  static const Duration _hmsTokenTimeout = Duration(seconds: 15);
  static const Duration _waitReadyTimeout = Duration(seconds: 30);

  PushProvider? _provider;
  String? _token;
  Future<void>? _initFuture;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _tokenReady = Completer<void>();

  final StreamController<PushMessage> _foreground =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _opened =
      StreamController<PushMessage>.broadcast();

  // ---------------------------------------------------------------
  // حالة
  // ---------------------------------------------------------------
  /// 'fcm' أو 'hms' أو null (لا إشعارات / لم تكتمل التهيئة بعد)
  String? get providerName => _provider?.name;
  String? get token => _token;
  bool get hasProvider => _provider != null;

  /// رسائل وصلت والتطبيق مفتوح (من المزوّد المختار).
  Stream<PushMessage> get onForegroundMessage => _foreground.stream;

  /// ضغط المستخدم على إشعار والتطبيق في الخلفية.
  Stream<PushMessage> get onMessageOpenedApp => _opened.stream;

  // ---------------------------------------------------------------
  // initialize (آمنة للاستدعاء أكثر من مرة، ولا ترمي استثناءً)
  // ---------------------------------------------------------------
  Future<void> initialize() => _initFuture ??= _doInitialize();

  Future<void> _doInitialize() async {
    try {
      final selection = await _selectProvider();
      if (selection == null) {
        debugPrint('ℹ️ [push] no push provider available on this device');
        return;
      }

      final provider = selection.provider;
      _provider = provider;
      await provider.initialize();
      _wireStreams(provider);

      // المزوّد معروف الآن: getInitialMessage() والاشتراك في الـ topics يمكنهما المتابعة.
      if (!_ready.isCompleted) _ready.complete();
      debugPrint('✅ [push] provider selected: ${provider.name}');

      final String? token = selection.token ??
          await provider.getToken(
            timeout: provider.name == 'fcm' ? _fcmTokenTimeout : _hmsTokenTimeout,
          );
      _token = token;
      await _persist(provider, token);
      if (token != null && !_tokenReady.isCompleted) _tokenReady.complete();

      // أي تغيّر لاحق للتوكن (أو وصوله متأخراً بعد عودة الشبكة)
      provider.onTokenRefresh.listen(
        (String newToken) {
          _token = newToken;
          _persist(provider, newToken);
          if (!_tokenReady.isCompleted) _tokenReady.complete();
        },
        onError: (Object e) => debugPrint('⚠️ [push] token refresh error: $e'),
      );
    } catch (e) {
      debugPrint('⚠️ [push] initialize failed (non-fatal): $e');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
      // لا يوجد مزوّد أصلاً: لا فائدة من انتظار توكن.
      if (_provider == null && !_tokenReady.isCompleted) _tokenReady.complete();
    }
  }

  // ---------------------------------------------------------------
  // اختيار المزوّد
  // ---------------------------------------------------------------
  Future<_Selection?> _selectProvider() async {
    // iOS: FCM كما هو اليوم، دون أي فحص.
    if (!Platform.isAndroid) return _Selection(FcmPushProvider(), null);

    var gms = false;
    var hms = false;
    try {
      gms = await FlutterHmsGmsAvailability.isGmsAvailable;
    } catch (e) {
      debugPrint('⚠️ [push] GMS availability check failed: $e');
    }
    try {
      hms = await FlutterHmsGmsAvailability.isHmsAvailable;
    } catch (e) {
      debugPrint('⚠️ [push] HMS availability check failed: $e');
    }
    debugPrint('ℹ️ [push] availability -> GMS: $gms | HMS: $hms');

    if (gms && !hms) return _Selection(FcmPushProvider(), null);
    if (hms && !gms) return _Selection(HmsPushProvider(), null);

    // الاثنان معاً (هواوي قديم) أو لم نستطع الكشف: نجرّب FCM أولاً.
    final fcm = FcmPushProvider();
    await fcm.initialize();
    final fcmToken = await fcm.getToken(timeout: _fcmProbeTimeout);
    if (fcmToken != null) return _Selection(fcm, fcmToken);

    final hmsProvider = HmsPushProvider();
    await hmsProvider.initialize();
    final hmsToken = await hmsProvider.getToken(timeout: _hmsTokenTimeout);
    if (hmsToken != null) return _Selection(hmsProvider, hmsToken);

    // فشل الاثنان (مثلاً بدون إنترنت وقت الإقلاع): إن كانت خدمات Google
    // موجودة نبقى على FCM فيصل التوكن لاحقاً عبر onTokenRefresh.
    if (gms) return _Selection(fcm, null);
    if (hms) return _Selection(hmsProvider, null);
    return null;
  }

  void _wireStreams(PushProvider provider) {
    try {
      provider.onForegroundMessage.listen(
        (m) {
          if (!_foreground.isClosed) _foreground.add(m);
        },
        onError: (Object e) => debugPrint('⚠️ [push] foreground stream error: $e'),
      );
      provider.onMessageOpenedApp.listen(
        (m) {
          if (!_opened.isClosed) _opened.add(m);
        },
        onError: (Object e) => debugPrint('⚠️ [push] opened stream error: $e'),
      );
    } catch (e) {
      debugPrint('⚠️ [push] failed to wire message streams: $e');
    }
  }

  // ---------------------------------------------------------------
  // حفظ الاختيار والتوكن في auth_box
  // ---------------------------------------------------------------
  Future<void> _persist(PushProvider provider, String? token) async {
    try {
      final box = await StorageService.openBox('auth_box');
      final stored = box.get(_kProviderKey);

      // تغيّر المزوّد: لا نُبقي توكناً قديماً يخص المزوّد السابق.
      if (stored != provider.name) {
        await box.delete(_kTokenKey);
        if (provider.name == 'hms') await box.delete(_kLegacyFcmTokenKey);
      }
      await box.put(_kProviderKey, provider.name);

      if (token != null && token.isNotEmpty) {
        await box.put(_kTokenKey, token);
        if (provider.name == 'fcm') {
          await box.put(_kLegacyFcmTokenKey, token); // توافق مع الكود الحالي
        } else {
          await box.delete(_kLegacyFcmTokenKey);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [push] failed to persist push registration: $e');
    }
  }

  /// هيدرز تسجيل الإشعارات للسيرفر، تُقرأ من auth_box.
  /// الاستعمال (خطوة 13):  headers: { ...PushService.registrationHeaders(box) }
  static Map<String, String> registrationHeaders(dynamic box) {
    try {
      final dynamic provider = box.get(_kProviderKey);
      final dynamic token = box.get(_kTokenKey);
      if (provider is String && token is String && token.isNotEmpty) {
        return <String, String>{
          'x-push-provider': provider,
          'x-push-token': token,
          // نُبقي الهيدر القديم مع FCM كاحتياط للتوافق الخلفي.
          if (provider == 'fcm') 'x-fcm-token': token,
        };
      }
      final dynamic legacy = box.get(_kLegacyFcmTokenKey);
      if (legacy is String && legacy.isNotEmpty) {
        return <String, String>{'x-fcm-token': legacy};
      }
    } catch (_) {}
    return const <String, String>{};
  }

  // ---------------------------------------------------------------
  // الرسائل والـ topics
  // ---------------------------------------------------------------
  /// ينتظر اختيار المزوّد (بحد أقصى [timeout]) ثم يعيد اسمه ('fcm' / 'hms')،
  /// أو null إذا لا يوجد مزوّد على هذا الجهاز.
  Future<String?> resolveProviderName({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      await _ready.future.timeout(timeout);
    } on TimeoutException {
      // نكمل: سيعود null إن لم يُختر مزوّد بعد
    }
    return providerName;
  }

  /// ينتظر جاهزية توكن الجهاز (بحد أقصى [timeout]) ويعيده، أو null.
  Future<String?> waitForToken({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_token != null) return _token;
    try {
      await _tokenReady.future.timeout(timeout);
    } on TimeoutException {
      // نكمل: سيعود null
    }
    return _token;
  }

  /// الرسالة التي فتحت التطبيق من حالة الإغلاق التام (أو null).
  Future<PushMessage?> getInitialMessage() async {
    try {
      await _ready.future.timeout(_waitReadyTimeout);
    } on TimeoutException {
      return null;
    }
    final provider = _provider;
    if (provider == null) return null;
    try {
      return await provider.getInitialMessage();
    } catch (e) {
      debugPrint('⚠️ [push] getInitialMessage failed: $e');
      return null;
    }
  }

  Future<PushProvider> _requireProvider() async {
    try {
      await _ready.future.timeout(_waitReadyTimeout);
    } on TimeoutException {
      // نتجاهل: سيُرمى StateError أدناه
    }
    final provider = _provider;
    if (provider == null) {
      throw StateError('No push provider available on this device');
    }
    return provider;
  }

  /// يرمي استثناءً عند الفشل (NotificationService يغلّفها بمهلة و try/catch).
  Future<void> subscribeToTopic(String topic) async {
    final provider = await _requireProvider();
    await provider.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    final provider = await _requireProvider();
    await provider.unsubscribeFromTopic(topic);
  }
}
