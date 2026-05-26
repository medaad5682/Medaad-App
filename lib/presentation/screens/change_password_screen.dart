import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
// ✅ إضافة استيراد Firebase App Check
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
// أو المسار المناسب حسب مكان الملف
import '../../core/constants/api_constants.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldPassController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();
  bool _isLoading = false;
  final String _baseUrl = ApiConstants.baseUrl;

  Future<void> _changePassword() async {
    // 1. التحقق من تطابق كلمة السر الجديدة قبل الإرسال
    if (_newPassController.text != _confirmPassController.text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Passwords do not match"),
          backgroundColor: AppColors.error));
      return;
    }

    if (_oldPassController.text.isEmpty || _newPassController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Please fill all fields"),
          backgroundColor: AppColors.error));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. جلب بيانات المصادقة المخزنة محلياً
      var box = await StorageService.openBox('auth_box');
      // ✅ جلب التوكن والبصمة
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');

      if (token == null || deviceId == null) {
        throw Exception("Authentication data not found. Please login again.");
      }

      // ✅ جلب توكن الـ App Check
      String? appCheckToken;
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken();
      } catch (e) {
        debugPrint("App Check Error: $e");
      }

      // 3. إرسال الطلب مع الـ Headers الصحيحة
      final res = await ApiClient.instance.post(
        '$_baseUrl/api/student/change-password',
        data: {
          'oldPassword': _oldPassController.text,
          'newPassword': _newPassController.text,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token', // ✅ الهيدر الجديد
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
            if (appCheckToken != null) 'X-Firebase-AppCheck': appCheckToken, // ✅ إرسال توكن App Check
          },
          // لضمان استلام رسائل الخطأ من السيرفر حتى لو كان الكود 400 أو 401
          validateStatus: (status) => status! < 500,
        ),
      );

      if (mounted) {
        // التحقق من نجاح العملية بناءً على رد السيرفر
        if (res.statusCode == 200 && res.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("Password Updated Successfully"),
              backgroundColor: AppColors.success));
          Navigator.pop(context);
        } else {
          // عرض رسالة الخطأ القادمة من السيرفر (مثل: Incorrect old password)
          String errorMsg = res.data['message'] ??
              res.data['error'] ??
              "Failed to update password";
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(errorMsg), backgroundColor: AppColors.error));
        }
      }
    } catch (e) {
      if (mounted) {
        String msg = "Connection error. Please try again.";
        if (e is DioException && e.response != null) {
          msg = e.response?.data['error'] ?? e.response?.data['message'] ?? msg;
        }
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4)
                        ],
                      ),
                      child: Icon(LucideIcons.arrowLeft,
                          color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    "CHANGE PASSWORD",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildPasswordField(
                        "Current Password", "••••••••", _oldPassController),
                    const SizedBox(height: 20),
                    _buildPasswordField("New Password", "Create new password",
                        _newPassController),
                    const SizedBox(height: 20),
                    _buildPasswordField("Confirm New Password",
                        "Confirm new password", _confirmPassController),
                  ],
                ),
              ),
            ),

            // Submit Button
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 10,
                    shadowColor: AppColors.accentYellow.withOpacity(0.2),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.backgroundPrimary,
                              strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.save, size: 18),
                            SizedBox(width: 12),
                            Text("UPDATE PASSWORD",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1.0)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField(
      String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.accentYellow,
                letterSpacing: 1.5),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TextField(
            controller: controller,
            obscureText: true,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(LucideIcons.lock,
                  size: 18, color: AppColors.textSecondary),
              hintText: hint,
              hintStyle:
                  TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.accentYellow, width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
