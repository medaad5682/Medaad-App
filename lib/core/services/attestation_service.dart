// lib/core/services/attestation_service.dart
// ------------------------------------------------------------------
// نقطة الدخول الوحيدة لإثبات أن الطلب قادم من تطبيقنا الأصلي (خطوة 18).
//
// الاختيار عند الإقلاع (مرة واحدة، يُحفظ في الذاكرة):
//   iOS                      -> Firebase App Check            (كما هو اليوم)
//   Android + GMS فقط        -> Firebase App Check            (كما هو اليوم)
//   Android + الاثنان معاً   -> Firebase App Check، فإن فشل وتوفّر HMS => Huawei
//   Android + HMS فقط        -> Huawei SysIntegrity           (لا يلمس FirebaseAppCheck
//                                                              إطلاقاً => لا حوارات Play Integrity)
//
// الهيدر الذي يرسله التطبيق:
//   App Check : X-Firebase-AppCheck: <token>
//   Huawei    : X-App-Attestation:   <token>   (توكن السيرفر الخاص، ساعة واحدة)
// السيرفر يجرّبهما بهذا الترتيب ثم القائمة البيضاء (lib/clientAttestation.js).
//
// تدفق Huawei (يطابق pages/api/attest/hms/*):
//   1) POST /api/attest/hms/nonce   { deviceId }              -> { nonce }
//   2) SafetyDetect.sysIntegrity(utf8(nonce), appId)           -> jws
//   3) POST /api/attest/hms/verify  { deviceId, nonce, jws }   -> { token, expiresInSeconds }
// التوكن مرتبط بـ deviceId، لذلك نستخدم نفس قيمة auth_box['device_id'] التي
// يرسلها ApiClient في هيدر x-device-id (وقبل تسجيل الدخول، حيث لا يوجد
// device_id ولا يُرسل الهيدر، نستخدم معرّفاً محلياً مستقلاً).
//
// قواعد التصميم:
//   - getHeaders() لا ترمي استثناءً أبداً: عند الفشل تعود بهيدرز فارغة فيُرسل
//     الطلب بلا إثبات (وتعمل القائمة البيضاء كما هي بلا أي تغيير).
//   - التوكن يُخزَّن مؤقتاً ويُجدَّد قبل انتهائه بـ 5 دقائق، والطلبات المتزامنة
//     تشترك في محاولة واحدة.
//   - بعد فشل محاولة Huawei لا نعيد المحاولة مع كل طلب (فترة تهدئة قصيرة) كي
//     لا نُبطئ كل طلب في التطبيق.
// ------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_hms_gms_availability/flutter_hms_gms_availability.dart';
import 'package:huawei_safetydetect/huawei_safetydetect.dart';

import '../constants/api_constants.dart';
import 'api_client.dart';
import 'storage_service.dart';

enum AttestationMethod { appCheck, hms }

class _Environment {
  final AttestationMethod method;

  /// Android فيه GMS و HMS معاً: نجرّب App Check أولاً، وHuawei كاحتياط.
  final bool hmsFallback;
  const _Environment(this.method, {this.hmsFallback = false});
}

class _CachedToken {
  final String token;
  final String deviceId;
  final DateTime expiresAt;
  const _CachedToken(this.token, this.deviceId, this.expiresAt);
}

/// فشل في تدفق Huawei. [transient] = سببه شبكة/مهلة (نعيد المحاولة قريباً)،
/// وإلا فهو رفض من السيرفر أو من HMS (نهدّئ فترة أطول).
class _AttestationException implements Exception {
  final String message;
  final bool transient;
  const _AttestationException(this.message, {this.transient = false});

  @override
  String toString() => message;
}

class AttestationService {
  AttestationService._();
  static final AttestationService instance = AttestationService._();

  static const String appCheckHeader = 'X-Firebase-AppCheck';
  static const String hmsHeader = 'X-App-Attestation';

  // مفاتيح auth_box
  static const String _kDeviceIdKey = 'device_id'; // يكتبه login_screen
  static const String _kLocalAttestIdKey = 'attest_device_id'; // احتياطي قبل تسجيل الدخول

  // مهل زمنية
  static const Duration _appCheckTimeout = Duration(seconds: 5);
  static const Duration _nonceTimeout = Duration(seconds: 8);
  static const Duration _sysIntegrityTimeout = Duration(seconds: 15);
  static const Duration _verifyTimeout = Duration(seconds: 8);
  static const Duration _hmsOverallTimeout = Duration(seconds: 25);

  static const Duration _expiryMargin = Duration(minutes: 5);
  static const Duration _transientCooldown = Duration(seconds: 5); // شبكة/مهلة: نعيد قريباً (مثلاً بعد عودة الإنترنت)
  static const Duration _rejectedCooldown = Duration(minutes: 2); // رفض من السيرفر/HMS: لا فائدة من التكرار كل طلب

  // اختياري: --dart-define=HMS_APP_ID=... إن تعذّر قراءته من agconnect-services.json
  static const String _appIdFromEnv = String.fromEnvironment('HMS_APP_ID');

  Future<_Environment>? _environmentFuture;
  String? _appId;

  _CachedToken? _cached;
  Future<String?>? _inFlight;
  String? _inFlightDeviceId;
  DateTime? _blockedUntil;
  String? _blockedDeviceId;

  // ---------------------------------------------------------------
  // اختيار الطريقة
  // ---------------------------------------------------------------
  Future<_Environment> _environment() => _environmentFuture ??= _detectEnvironment();

  Future<_Environment> _detectEnvironment() async {
    // iOS: App Check كما هو، دون أي فحص.
    if (!Platform.isAndroid) return const _Environment(AttestationMethod.appCheck);

    var gms = false;
    var hms = false;
    try {
      gms = await FlutterHmsGmsAvailability.isGmsAvailable;
    } catch (e) {
      debugPrint('⚠️ [attest] GMS availability check failed: $e');
    }
    try {
      hms = await FlutterHmsGmsAvailability.isHmsAvailable;
    } catch (e) {
      debugPrint('⚠️ [attest] HMS availability check failed: $e');
    }
    debugPrint('ℹ️ [attest] availability -> GMS: $gms | HMS: $hms');

    if (hms && !gms) return const _Environment(AttestationMethod.hms);
    return _Environment(AttestationMethod.appCheck, hmsFallback: hms);
  }

  /// الطريقة المختارة لهذا الجهاز.
  Future<AttestationMethod> get method async => (await _environment()).method;

  // ---------------------------------------------------------------
  // تفعيل App Check عند الإقلاع (main.dart)
  // ---------------------------------------------------------------
  /// على أجهزة HMS فقط لا يفعل شيئاً (لا يلمس FirebaseAppCheck ولا Play
  /// Integrity). على باقي الأجهزة يرمي نفس الاستثناءات التي كان يرميها
  /// FirebaseAppCheck.activate() سابقاً، والمستدعي (main.dart) يلتقطها.
  Future<void> activate() async {
    final env = await _environment();
    if (env.method == AttestationMethod.hms) {
      debugPrint('ℹ️ [attest] HMS-only device: skipping FirebaseAppCheck.activate()');
      return;
    }

    await FirebaseAppCheck.instance
        .activate(
          // Play Integrity للأندرويد (الأقوى ضد الروت والتعديل) في وضع الإنتاج، أو Debug في وضع التطوير
          providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
          // ✅ App Attest مع DeviceCheck كـ fallback للأجهزة القديمة التي لا تدعم App Attest
          providerApple: kReleaseMode ? const AppleAppAttestWithDeviceCheckFallbackProvider() : const AppleDebugProvider(),
        )
        .timeout(_appCheckTimeout);
  }

  // ---------------------------------------------------------------
  // الهيدرز المرفقة بالطلبات
  // ---------------------------------------------------------------
  /// تعيد هيدر الإثبات المناسب لهذا الجهاز ({} إن لم يتوفر). لا ترمي أبداً.
  /// الاستعمال:  headers: { ...await AttestationService.instance.getHeaders() }
  Future<Map<String, String>> getHeaders({bool forceRefresh = false}) async {
    try {
      final env = await _environment();

      if (env.method == AttestationMethod.hms) {
        return await _hmsHeaders(forceRefresh);
      }

      final String? appCheck = await _appCheckToken(forceRefresh);
      if (appCheck != null) return <String, String>{appCheckHeader: appCheck};

      // GMS + HMS معاً وفشل Play Integrity: نجرّب Huawei بدل إرسال الطلب بلا إثبات.
      if (env.hmsFallback) return await _hmsHeaders(forceRefresh);
    } catch (e) {
      debugPrint('⚠️ [attest] getHeaders failed (non-fatal): $e');
    }
    return const <String, String>{};
  }

  // ---------------------------------------------------------------
  // Firebase App Check (نفس سلوك ApiClient السابق: محاولة ثم إعادة بـ force refresh)
  // ---------------------------------------------------------------
  Future<String?> _appCheckToken(bool forceRefresh) async {
    try {
      return await FirebaseAppCheck.instance.getToken(forceRefresh).timeout(_appCheckTimeout);
    } catch (e, stack) {
      String? retryToken;
      try {
        retryToken = await FirebaseAppCheck.instance.getToken(true).timeout(_appCheckTimeout);
      } catch (_) {
        // تجاهل - الطلب سيُرسل بدون App Check header
      }
      await _recordNonFatal(e, stack, 'Failed to retrieve App Check token');
      debugPrint('🚨 App Check Error logged to Crashlytics: $e');
      return retryToken;
    }
  }

  // ---------------------------------------------------------------
  // Huawei SysIntegrity
  // ---------------------------------------------------------------
  Future<Map<String, String>> _hmsHeaders(bool forceRefresh) async {
    final String? token = await _hmsToken(forceRefresh);
    if (token == null) return const <String, String>{};
    return <String, String>{hmsHeader: token};
  }

  Future<String?> _hmsToken(bool forceRefresh) async {
    final String? deviceId = await _currentDeviceId();
    if (deviceId == null) return null;

    final now = DateTime.now();

    final cached = _cached;
    if (!forceRefresh && cached != null && cached.deviceId == deviceId && cached.expiresAt.isAfter(now)) {
      return cached.token;
    }

    // بعد فشل قريب: لا نعيد المحاولة مع كل طلب.
    if (!forceRefresh &&
        _blockedDeviceId == deviceId &&
        _blockedUntil != null &&
        now.isBefore(_blockedUntil!)) {
      return null;
    }

    // الطلبات المتزامنة (صور، API...) تشترك في محاولة واحدة.
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightDeviceId == deviceId) return inFlight;

    final Future<String?> attempt = _runHmsAttestation(deviceId);
    _inFlight = attempt;
    _inFlightDeviceId = deviceId;
    try {
      return await attempt;
    } finally {
      if (identical(_inFlight, attempt)) {
        _inFlight = null;
        _inFlightDeviceId = null;
      }
    }
  }

  Future<String?> _runHmsAttestation(String deviceId) async {
    try {
      final _CachedToken result = await _attestWithHms(deviceId).timeout(_hmsOverallTimeout);
      _cached = result;
      _blockedUntil = null;
      _blockedDeviceId = null;
      debugPrint('✅ [attest] Huawei attestation token acquired');
      return result.token;
    } on TimeoutException {
      _block(deviceId, _transientCooldown);
      debugPrint('⚠️ [attest] Huawei attestation timed out');
    } on _AttestationException catch (e, stack) {
      _block(deviceId, e.transient ? _transientCooldown : _rejectedCooldown);
      debugPrint('⚠️ [attest] Huawei attestation failed: ${e.message}');
      if (!e.transient) {
        await _recordNonFatal(e, stack, 'Huawei attestation rejected: ${e.message}');
      }
    } catch (e, stack) {
      _block(deviceId, _transientCooldown);
      debugPrint('⚠️ [attest] Huawei attestation error: $e');
      await _recordNonFatal(e, stack, 'Huawei attestation unexpected error');
    }
    return null;
  }

  void _block(String deviceId, Duration duration) {
    _blockedDeviceId = deviceId;
    _blockedUntil = DateTime.now().add(duration);
  }

  Future<_CachedToken> _attestWithHms(String deviceId) async {
    final String appId = await _resolveAppId();

    // 1) nonce من السيرفر (مرتبط بـ deviceId، صالح 5 دقائق ولمرة واحدة)
    final Map<String, dynamic> nonceBody = await _post(
      '/api/attest/hms/nonce',
      <String, dynamic>{'deviceId': deviceId},
      _nonceTimeout,
    );
    final dynamic nonce = nonceBody['nonce'];
    if (nonce is! String || nonce.isEmpty) {
      throw const _AttestationException('nonce response has no nonce');
    }

    // 2) فحص سلامة النظام عبر HMS Core. السيرفر يتوقع bytes الـ UTF-8 للنص نفسه.
    final String jws;
    try {
      jws = await SafetyDetect.sysIntegrity(
        Uint8List.fromList(utf8.encode(nonce)),
        appId,
      ).timeout(_sysIntegrityTimeout);
    } on PlatformException catch (e) {
      // 19002 = NETWORK_ERROR (مؤقت). غيره (19202 نسخة HMS قديمة، 19004 appId غير صالح...) غير مؤقت.
      throw _AttestationException(
        'SysIntegrity failed: ${e.code} ${e.message}',
        transient: e.code == '19002',
      );
    }
    if (jws.isEmpty) throw const _AttestationException('SysIntegrity returned an empty result');

    // 3) السيرفر يتحقق من الـ JWS ويعيد توكنه الخاص
    final Map<String, dynamic> verifyBody = await _post(
      '/api/attest/hms/verify',
      <String, dynamic>{'deviceId': deviceId, 'nonce': nonce, 'jws': jws},
      _verifyTimeout,
    );
    final dynamic token = verifyBody['token'];
    if (token is! String || token.isEmpty) {
      throw const _AttestationException('verify response has no token');
    }

    final dynamic rawTtl = verifyBody['expiresInSeconds'];
    final int ttlSeconds = rawTtl is num ? rawTtl.toInt() : 3600;
    Duration lifetime = Duration(seconds: ttlSeconds) - _expiryMargin;
    if (lifetime < const Duration(minutes: 1)) lifetime = const Duration(minutes: 1);

    return _CachedToken(token, deviceId, DateTime.now().add(lifetime));
  }

  /// POST عبر ApiClient.bare (نفس الـ TLS pinning و x-app-secret، بدون interceptors
  /// حتى لا تستدعي الطلبات نفسها AttestationService وتدخل في حلقة).
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, Duration timeout) async {
    final Response<dynamic> response;
    try {
      response = await ApiClient.bare.post<dynamic>(
        '${ApiConstants.baseUrl}$path',
        data: body,
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (e) {
      // شبكة / مهلة / خطأ 5xx => مؤقت
      throw _AttestationException('$path network error: ${e.type.name}', transient: true);
    }

    final dynamic data = response.data;
    final Map<String, dynamic> map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final int status = response.statusCode ?? 0;

    if (status == 200 && map['success'] == true) return map;

    // 429 = تجاوز حد الطلبات (مؤقت). باقي 4xx = رفض (نُرفق code من السيرفر للتشخيص).
    throw _AttestationException(
      '$path -> HTTP $status code=${map['code'] ?? '-'}',
      transient: status == 429,
    );
  }

  Future<String> _resolveAppId() async {
    final cachedId = _appId;
    if (cachedId != null) return cachedId;

    String id = '';
    try {
      // يقرأها الـ plugin من agconnect-services.json (client/app_id)
      id = (await SafetyDetect.getAppID).trim();
    } catch (e) {
      debugPrint('⚠️ [attest] SafetyDetect.getAppID failed: $e');
    }
    if (id.isEmpty) id = _appIdFromEnv.trim();
    if (id.isEmpty) {
      throw const _AttestationException('HMS app id is unavailable (agconnect-services.json / HMS_APP_ID)');
    }
    return _appId = id;
  }

  // ---------------------------------------------------------------
  // معرّف الجهاز المرتبط بالتوكن
  // ---------------------------------------------------------------
  /// نفس قيمة هيدر x-device-id التي يرسلها ApiClient (auth_box['device_id']).
  /// قبل تسجيل الدخول لا توجد قيمة ولا يُرسل هذا الهيدر، فنستعمل معرّفاً محلياً
  /// عشوائياً ثابتاً. عند ظهور device_id (بعد الدخول) يتغيّر المعرّف تلقائياً
  /// فيُجرى إثبات جديد مرتبط به.
  Future<String?> _currentDeviceId() async {
    try {
      final box = await StorageService.openBox('auth_box');

      final dynamic deviceId = box.get(_kDeviceIdKey);
      if (deviceId is String && deviceId.isNotEmpty) return deviceId;

      final dynamic stored = box.get(_kLocalAttestIdKey);
      if (stored is String && stored.isNotEmpty) return stored;

      final rnd = Random.secure();
      final String hex = List<String>.generate(
        16,
        (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final String generated = 'attest_$hex';
      await box.put(_kLocalAttestIdKey, generated);
      return generated;
    } catch (e) {
      debugPrint('⚠️ [attest] cannot resolve device id (non-fatal): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------
  Future<void> _recordNonFatal(Object error, StackTrace stack, String reason) async {
    try {
      if (Firebase.apps.isEmpty) return;
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: false, // لا نريد إغلاق التطبيق
      );
    } catch (_) {
      // التسجيل نفسه لا يجب أن يكسر أي شيء
    }
  }
}
