import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio/io.dart'; // ✅ مكتبة محول Dio المطلوبة للـ Pinning
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ إضافة Crashlytics
import 'storage_service.dart';
import 'package:flutter/foundation.dart'; // ✅ هذا هو الحل للخطأ

// ✅ 1. الشهادات الجذرية (Self-signed Roots) طويلة الأمد
// تغطي جميع الدومينات:
//   - medaad.online                -> GTS Root R4  (Google Trust Services)
//   - courses.medaad.online        -> ISRG Root X1 (Let's Encrypt)
//   - medaad.aw478260.dpdns.org    -> ISRG Root X1 (Let's Encrypt)
//   - courses.aw478260.dpdns.org   -> ISRG Root X1 (Let's Encrypt)

// GTS Root R4 — صالحة حتى: Jun 22, 2036
const String gtsRootR4 = """-----BEGIN CERTIFICATE-----
MIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD
VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG
A1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw
WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz
IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi
AATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi
QHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR
HYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
BBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D
9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8
p/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD
-----END CERTIFICATE-----""";

// ISRG Root X1 — صالحة حتى: Jun 4, 2035  (⚠️ أقرب تاريخ انتهاء — حدّث التطبيق قبله)
const String isrgRootX1 = """-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----""";

// قائمة الجذور الموثوقة
const List<String> _trustedRootCerts = [gtsRootR4, isrgRootX1];

class ApiClient {
  static final Dio _dio = Dio()
    // ✅ 2. تطبيق حماية الـ TLS Certificate Pinning (منع هجمات MITM)
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        // دمج كل الشهادات الجذرية في بايتات واحدة (PEM متعدد)
        final List<int> certBytes =
            utf8.encode(_trustedRootCerts.join('\n'));

        // إنشاء السياق الأمني وإلغاء ثقة النظام (منع الشهادات المزيفة)
        final SecurityContext securityContext =
            SecurityContext(withTrustedRoots: false);

        // إجبار التطبيق على الثقة بهذه الجذور المحددة فقط
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
