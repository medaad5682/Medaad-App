import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/api_constants.dart'; // ✅ استيراد الثوابت
import 'api_client.dart';

enum UpdateStatus { none, optional, force }

class UpdateResult {
  final UpdateStatus status;
  final String message;
  final String storeUrl;

  UpdateResult({
    required this.status,
    required this.message,
    required this.storeUrl,
  });
}

class UpdateService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );

  /// 🔗 رابط التحقق من التحديث (يتم سحبه الآن من الملف الموحد)
  final String _checkVersionUrl =
      "${ApiConstants.baseUrl}/api/public/check-version";

  /// 🚀 فحص التحديث
  Future<UpdateResult> checkUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final platform = Platform.isAndroid ? 'android' : 'ios';

      final response = await ApiClient.instance.get(
        _checkVersionUrl, // ✅ استخدام الرابط الجديد المعتمد على ApiConstants
        queryParameters: {
          'platform': platform,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return _noUpdate();
      }

      final data = response.data;

      final String minVersion = data['min_version'] ?? "0.0.0";
      final String latestVersion = data['latest_version'] ?? "0.0.0";
      final bool forceUpdate = data['force_update'] ?? false;
      final String message =
          data['message'] ?? "يوجد تحديث جديد يتضمن تحسينات.";
      final String storeUrl = data['store_url'] ?? "";

      /// ⛔ تحديث إجباري (لو أقل من min_version)
      if (_compareVersions(currentVersion, minVersion) < 0 ||
          forceUpdate == true) {
        return UpdateResult(
          status: UpdateStatus.force,
          message: message,
          storeUrl: storeUrl,
        );
      }

      /// ⚠️ تحديث اختياري (لو أقل من latest_version)
      if (_compareVersions(currentVersion, latestVersion) < 0) {
        return UpdateResult(
          status: UpdateStatus.optional,
          message: message,
          storeUrl: storeUrl,
        );
      }

      return _noUpdate();
    } catch (e) {
      /// 🔥 لو حصل خطأ في الاتصال لا نوقف التطبيق
      return _noUpdate();
    }
  }

  /// 🔢 مقارنة الإصدارات بشكل آمن
  int _compareVersions(String v1, String v2) {
    final a = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final b = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength = a.length > b.length ? a.length : b.length;

    for (int i = 0; i < maxLength; i++) {
      final num1 = i < a.length ? a[i] : 0;
      final num2 = i < b.length ? b[i] : 0;

      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    }

    return 0;
  }

  UpdateResult _noUpdate() {
    return UpdateResult(
      status: UpdateStatus.none,
      message: "",
      storeUrl: "",
    );
  }
}
