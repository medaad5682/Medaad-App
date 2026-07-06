import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio/io.dart'; // ✅ مكتبة محول Dio المطلوبة للـ Pinning
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ إضافة Crashlytics
import 'storage_service.dart';
import 'package:flutter/foundation.dart'; // ✅ هذا هو الحل للخطأ

// ✅ 1. شهادة الجذور طويلة الأمد (GlobalSign & GTS) لتجنب التحديث كل 90 يوم
const String secureRootCert = """-----BEGIN CERTIFICATE-----
MIIDejCCAmKgAwIBAgIQf+UwvzMTQ77dghYQST2KGzANBgkqhkiG9w0BAQsFADBX
MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEQMA4GA1UE
CxMHUm9vdCBDQTEbMBkGA1UEAxMSR2xvYmFsU2lnbiBSb290IENBMB4XDTIzMTEx
NTAzNDMyMVoXDTI4MDEyODAwMDA0MlowRzELMAkGA1UEBhMCVVMxIjAgBgNVBAoT
GUdvb2dsZSBUcnVzdCBTZXJ2aWNlcyBMTEMxFDASBgNVBAMTC0dUUyBSb290IFI0
MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE83Rzp2iLYK5DuDXFgTB7S0md+8Fhzube
Rr1r1WEYNa5A3XP3iZEwWus87oV8okB2O6nGuEfYKueSkWpz6bFyOZ8pn6KY019e
WIZlD6GEZQbR3IvJx3PIjGov5cSr0R2Ko4H/MIH8MA4GA1UdDwEB/wQEAwIBhjAd
BgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwDwYDVR0TAQH/BAUwAwEB/zAd
BgNVHQ4EFgQUgEzW63T/STaj1dj8tT7FavCUHYwwHwYDVR0jBBgwFoAUYHtmGkUN
l8qJUC99BM00qP/8/UswNgYIKwYBBQUHAQEEKjAoMCYGCCsGAQUFBzAChhpodHRw
Oi8vaS5wa2kuZ29vZy9nc3IxLmNydDAtBgNVHR8EJjAkMCKgIKAehhxodHRwOi8v
Yy5wa2kuZ29vZy9yL2dzcjEuY3JsMBMGA1UdIAQMMAowCAYGZ4EMAQIBMA0GCSqG
SIb3DQEBCwUAA4IBAQAYQrsPBtYDh5bjP2OBDwmkoWhIDDkic574y04tfzHpn+cJ
odI2D4SseesQ6bDrarZ7C30ddLibZatoKiws3UL9xnELz4ct92vID24FfVbiI1hY
+SW6FoVHkNeWIP0GCbaM4C6uVdF5dTUsMVs/ZbzNnIdCp5Gxmx5ejvEau8otR/Cs
kGN+hr/W5GvT1tMBjgWKZ1i4//emhA1JG1BbPzoLJQvyEotc03lXjTaCzv8mEbep
8RqZ7a2CPsgRbuvTPBwcOMBBmuFeU88+FSBX6+7iP0il8b4Z0QFqIwwMHfs/L6K1
vepuoxtGzi4CZ68zJpiq1UvSqTbFJjtbD4seiMHl
-----END CERTIFICATE-----""";

class ApiClient {
  static final Dio _dio = Dio()
    // ✅ 2. تطبيق حماية الـ TLS Certificate Pinning (منع هجمات MITM)
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        // تحويل النص المباشر إلى بايتات في الذاكرة
        List<int> certBytes = utf8.encode(secureRootCert);

        // إنشاء السياق الأمني وإلغاء ثقة النظام (منع الشهادات المزيفة)
        SecurityContext securityContext =
            SecurityContext(withTrustedRoots: false);

        // إجبار التطبيق على الثقة بهذه الشهادة المحددة فقط
        securityContext.setTrustedCertificatesBytes(certBytes);

        return HttpClient(context: securityContext);
      },
    )
    // ✅ 3. إضافة الانترسبتورز الخاصة بك (لم تتغير)
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. مفتاح التطبيق (يُرسل مع كل الطلبات)
          options.headers['x-app-secret'] = 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only';

          // 2. توكن Firebase App Check
          try {
            final appCheckToken = await FirebaseAppCheck.instance
                .getToken(false)
                .timeout(const Duration(seconds: 5));
            if (appCheckToken != null) {
              options.headers['X-Firebase-AppCheck'] = appCheckToken;
            }
          } catch (e, stack) {
            // ✅ محاولة ثانية مع force refresh
            try {
              final retryToken = await FirebaseAppCheck.instance
                  .getToken(true)
                  .timeout(const Duration(seconds: 5));
              if (retryToken != null) {
                options.headers['X-Firebase-AppCheck'] = retryToken;
              }
            } catch (_) {
              // تجاهل - الطلب سيُرسل بدون App Check header
            }
            // ✅ إرسال تفاصيل الخطأ إلى Firebase Crashlytics
            await FirebaseCrashlytics.instance.recordError(
              e,
              stack,
              reason: 'Failed to retrieve App Check token in ApiClient',
              fatal: false, // نضعه false لأننا لا نريد إغلاق التطبيق
            );
            debugPrint("🚨 App Check Error logged to Crashlytics: $e");
          }

          // 3. توكن المستخدم (JWT) ومعرف الجهاز
          try {
            var box = await StorageService.openBox('auth_box');
            final token = box.get('jwt_token');
            final deviceId = box.get('device_id');

            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            if (deviceId != null) {
              options.headers['x-device-id'] = deviceId;
            }
          } catch (e) {
            // تجاهل الخطأ (يحدث إذا كان المستخدم غير مسجل الدخول)
          }

          // تمرير الطلب بعد حقن جميع الـ Headers
          return handler.next(options);
        },
      ),
    );

  // للوصول إلى المثيل الموحد
  static Dio get instance => _dio;
}
