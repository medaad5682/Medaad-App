import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ إضافة Crashlytics
import 'storage_service.dart';

class ApiClient {
  static final Dio _dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. مفتاح التطبيق (يُرسل مع كل الطلبات)
          options.headers['x-app-secret'] = const String.fromEnvironment('APP_SECRET');

          // 2. توكن Firebase App Check
          try {
            final appCheckToken = await FirebaseAppCheck.instance.getToken(false);
            if (appCheckToken != null) {
              options.headers['X-Firebase-AppCheck'] = appCheckToken;
            }
          } catch (e, stack) {
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
