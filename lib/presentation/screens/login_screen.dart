import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ تم الاستيراد لتمكين النسخ الصامت و MethodChannel
import 'package:dio/dio.dart'; // مطلوب من أجل Options
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_id/android_id.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/notification_service.dart';
import 'main_wrapper.dart';
import 'register_screen.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ✅ تعريف قناة الاتصال بالـ Native للوصول إلى دالة getDebugToken
  static const _nativeChannel = MethodChannel('medaad.app.com/audio_protection');

  // نستخدم هذا المتحكم لاسم المستخدم أو رقم الهاتف
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  final String _baseUrl = ApiConstants.baseUrl;
  bool _isLoading = false;
  String? _errorMessage;

  // ✅ متغيرات الخدعة السرية لاستخراج التوكن
  int _secretTapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered Login Screen");
    _userFocus.addListener(() => setState(() {}));
    _passFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ✅ الدالة السرية: تطلب التوكن من الـ Native وتنسخه بصمت إذا اكتملت 5 ضغطات متتالية
  void _handleSecretTap() async {
  final now = DateTime.now();
  if (_lastTapTime == null ||
      now.difference(_lastTapTime!) > const Duration(seconds: 2)) {
    _secretTapCount = 1;
  } else {
    _secretTapCount++;
  }
  _lastTapTime = now;

  // Show tap count visually so you know it's registering
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Tap $_secretTapCount/5'),
      duration: const Duration(milliseconds: 500),
    ),
  );

  if (_secretTapCount >= 5) {
    _secretTapCount = 0;
    if (Platform.isAndroid) {
      try {
        // Step 1: Check if channel works at all
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calling native...')),
        );

        final String? token =
            await _nativeChannel.invokeMethod('getDebugToken');

        // Step 2: Show exactly what came back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(token != null
                ? 'Token found: ${token.substring(0, 8)}...'
                : 'Token is NULL — logcat returned nothing'),
            duration: const Duration(seconds: 4),
          ),
        );

        if (token != null && token.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: token));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Copied to clipboard!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        // Step 3: Show the actual error instead of hiding it
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

  // دالة الحصول على معرف الجهاز الفريد (Android ID)
  Future<String> _getAndSaveDeviceId(Box box) async {
    String deviceId;
    try {
      if (Platform.isAndroid) {
        const androidIdPlugin = AndroidId();
        final String? androidId = await androidIdPlugin.getId();
        deviceId = androidId ??
            'unknown_android_${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = 'ios_${iosInfo.identifierForVendor}';
      } else {
        deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      final random = Random();
      deviceId =
          'fallback_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(1000)}';
    }

    await box.put('device_id', deviceId);
    return deviceId;
  }

  Future<void> _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      setState(
          () => _errorMessage = "Please enter username/phone and password");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var box = await StorageService.openBox('auth_box');
      // 1. جلب معرف الجهاز الحقيقي
      final deviceId = await _getAndSaveDeviceId(box);

      // 2. إرسال الطلب للباك اند بالاعتماد كلياً على ApiClient (بدون هيدرز يدوية)
      final response = await ApiClient.instance.post(
        '$_baseUrl/api/auth/login',
        data: {
          'identifier': identifier,
          'password': password,
          'deviceId': deviceId,
        },
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['success'] == true) {
        final userMap = data['user'];

        // حفظ البيانات الأساسية
        await box.put('user_id', userMap['id'].toString());
        await box.put('username', userMap['username']);
        await box.put('first_name', userMap['firstName']);
        await box.put('phone', userMap['phone'] ?? '');

        // حفظ نوع المستخدم (معلم/طالب)
        await box.put('role', userMap['role']);

        // حفظ رابط صورة البروفايل إذا وجد (للمعلمين)
        if (userMap['profileImage'] != null) {
          await box.put('profile_image', userMap['profileImage']);
        } else {
          await box.delete('profile_image');
        }

        // حفظ التوكن القادم من السيرفر
        if (data['token'] != null) {
          await box.put('jwt_token', data['token']);
        }

        // مسح علامة الضيف
        await box.delete('is_guest');
        AppState().isGuest = false;

        // تحديث حالة التطبيق بالبيانات الجديدة
        AppState().updateUserData(
            {...userMap, 'profile_image': userMap['profileImage']});

        // جلب البيانات الأولية وتسجيل الإشعارات
        await _fetchInitData(deviceId);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainWrapper()),
          );
        }
      } else {
        setState(() => _errorMessage = data['message'] ?? 'Login failed');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = "Connection Error");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // معالجة الدخول كضيف
  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);

    try {
      var box = await StorageService.openBox('auth_box');
      await _getAndSaveDeviceId(box);
      
      // ✅ جلب توكن فايربيز لإرساله وتسجيله في الباك إند
      String? fcmToken = box.get('fcm_token');

      // الاعتماد على ApiClient مع تمرير x-fcm-token و x-user-id للضيف
      final response = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(headers: {
          'x-user-id': '0', // ✅ تمت إضافته لتوحيد منطق الزائر
          if (fcmToken != null) 'x-fcm-token': fcmToken,
        }),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        AppState().updateFromInitData(response.data);

        bool serverFreeMode = response.data['freeModeV3'] ?? false;

        // ⛔ إجبار الإغلاق للأندرويد
        if (Platform.isAndroid) {
          serverFreeMode = false;
        }

        await box.put('free_mode', serverFreeMode);
        
        // تحديث قنوات الإشعارات للزائر
        if (response.data['myAccess'] != null && response.data['myAccess']['topics'] != null) {
          List<String> topics = List<String>.from(response.data['myAccess']['topics']);
          await NotificationService().updateSubscriptions(topics);
        }
      }

      await box.put('is_guest', true);
      AppState().isGuest = true;

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainWrapper()),
        );
      }
    } catch (e) {
      // في حالة الفشل (أوفلاين)، ندخل كضيف فارغ
      var box = await StorageService.openBox('auth_box');
      await box.put('is_guest', true);
      AppState().isGuest = true;

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainWrapper()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchInitData(String deviceId) async {
    try {
      var box = await StorageService.openBox('auth_box');
      
      // ✅ جلب توكن فايربيز للإشعارات
      String? fcmToken = box.get('fcm_token');

      // الاعتماد على ApiClient مع إضافة x-fcm-token فقط كاستثناء ذكي
      final response = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(headers: {
          if (fcmToken != null) 'x-fcm-token': fcmToken,
        }),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        AppState().updateFromInitData(response.data);

        bool serverFreeMode = response.data['freeModeV3'] ?? false;

        // ⛔ إجبار الإغلاق للأندرويد دائماً
        if (Platform.isAndroid) {
          serverFreeMode = false;
        }

        await box.put('free_mode', serverFreeMode);
        
        // تحديث قنوات الإشعارات (Topics) بعد تسجيل الدخول
        if (response.data['myAccess'] != null && response.data['myAccess']['topics'] != null) {
          List<String> topics = List<String>.from(response.data['myAccess']['topics']);
          await NotificationService().updateSubscriptions(topics);
        }
      }
    } catch (e) {
      debugPrint("Init Data Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 64),

              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),

              Center(
                child: Text(
                  "LOGIN",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              // ✅ هنا تم إضافة الـ GestureDetector للسر المخفي
              Center(
                child: GestureDetector(
                  onTap: _handleSecretTap, // استدعاء الدالة الصامتة عند الضغط
                  behavior: HitTestBehavior.opaque, // لالتقاط النقرات بدقة
                  child: Text(
                    "PLEASE LOGIN TO CONTINUE.",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentYellow,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),

              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              _buildInputLabel("Username or Phone"),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _identifierController,
                focusNode: _userFocus,
                hint: "Enter username or 01xxxxxxxxx",
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 24),

              _buildInputLabel("Password"),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _passwordController,
                focusNode: _passFocus,
                hint: "••••••••",
                icon: LucideIcons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 32),

              // Login Button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: AppColors.backgroundPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 10,
                  shadowColor: AppColors.accentYellow.withOpacity(0.2),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.backgroundPrimary))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            "SIGN IN",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                          SizedBox(width: 12),
                          Icon(LucideIcons.arrowRight, size: 18),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // Guest Login Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleGuestLogin,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    side: BorderSide(color: AppColors.accentYellow),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    "BROWSE AS GUEST",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.0,
                      color: AppColors.accentYellow,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "New student? ",
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: Text(
                      "CREATE ACCOUNT",
                      style: TextStyle(
                        color: AppColors.accentYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.accentYellow,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.accentYellow,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focusNode.hasFocus
              ? AppColors.accentYellow.withOpacity(0.5)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        cursorColor: AppColors.accentYellow,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          prefixIcon: Icon(
            icon,
            size: 18,
            color: (controller.text.isNotEmpty || focusNode.hasFocus)
                ? AppColors.accentYellow
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
