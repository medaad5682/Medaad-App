import 'dart:async';
import 'dart:io';
import 'package:Medaad/core/services/security_manager.dart';
import 'package:Medaad/core/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart'; // نحتاجه فقط لـ Options إذا لزم الأمر
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
// ✅ 1. استيراد خدمة الإشعارات
import '../../core/services/notification_service.dart';
import 'login_screen.dart';
import 'main_wrapper.dart';
import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';
import '../../core/constants/api_constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("App Started - Splash Screen");

    // 1. إعدادات الأنيميشن
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0.0, end: 15.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _progressController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // 2. بدء عملية التهيئة
    _initializeApp();
  }

  /// دالة لحذف الملفات المؤقتة (تنظيف المخلفات)
  Future<void> _cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);

      if (await dir.exists()) {
        final List<FileSystemEntity> entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            // حذف ملفات PDF المفكوكة وملفات التحميل المؤقتة
            final filename = entity.uri.pathSegments.last;
            if (filename.startsWith('view_') ||
                filename.startsWith('temp_') ||
                filename.startsWith('downloading_')) {
              try {
                await entity.delete();
                debugPrint("🧹 Deleted temp file: $filename");
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Cleanup error: $e");
    }
  }

  // نافذة الموافقة على الشروط والسياسات
  Future<bool> _showTermsDialog(Box box) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: AppColors.backgroundSecondary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                "Welcome / مرحباً بك",
                style: TextStyle(
                    color: AppColors.accentYellow, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "يرجى الموافقة على الشروط والأحكام وسياسة الخصوصية للمتابعة.",
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please accept our Terms & Privacy Policy to continue.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      dense: true,
                      leading: Icon(LucideIcons.fileText,
                          color: AppColors.accentOrange, size: 20),
                      title: Text("Terms & Conditions",
                          style: TextStyle(color: AppColors.textPrimary)),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TermsConditionsScreen())),
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(LucideIcons.shield,
                          color: AppColors.accentOrange, size: 20),
                      title: Text("Privacy Policy",
                          style: TextStyle(color: AppColors.textPrimary)),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyScreen())),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.error)),
                  child:
                      Text("DECLINE", style: TextStyle(color: AppColors.error)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  child: const Text("ACCEPT",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _initializeApp() async {
    try {
      // تنظيف الملفات المؤقتة فوراً عند الفتح
      await _cleanupTempFiles();

      await Hive.initFlutter();
      var box = await StorageService.openBox('auth_box');
      await StorageService.openBox('downloads_box');

      final UpdateService _updateService = UpdateService();

      final updateResult = await _updateService.checkUpdate();

      if (!mounted) return;

      if (updateResult.status != UpdateStatus.none) {
        await _handleUpdate(updateResult);
        if (updateResult.status == UpdateStatus.force) {
          return;
        }
      }

      bool termsAccepted = box.get('terms_accepted', defaultValue: false);
      if (!termsAccepted) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          // التحقق الأمني قبل عرض الشروط
          if (!await SecurityManager.instance.checkSecurity()) return;

          bool userAgreed = await _showTermsDialog(box);
          if (!userAgreed) {
            if (Platform.isAndroid) SystemNavigator.pop();
            exit(0);
          } else {
            await box.put('terms_accepted', true);
          }
        }
      }

      bool isGuest = box.get('is_guest', defaultValue: false);
      String? userId = box.get('user_id');
      String? deviceId = box.get('device_id');

      await Future.delayed(const Duration(seconds: 1));

      if (isGuest) {
        deviceId ??= 'guest_device_${DateTime.now().millisecondsSinceEpoch}';
        await _initAsGuest(deviceId, box);
        return;
      }

      if (userId == null || deviceId == null) {
        if (mounted) {
          if (!await SecurityManager.instance.checkSecurity()) return;

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }

      await _initAsUser(userId, deviceId, box);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      if (mounted) {
        if (!await SecurityManager.instance.checkSecurity()) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _handleUpdate(UpdateResult result) async {
    await showDialog(
      context: context,
      barrierDismissible: result.status == UpdateStatus.optional,
      builder: (_) => AlertDialog(
        title: const Text("تحديث التطبيق"),
        content: Text(result.message),
        actions: [
          if (result.status == UpdateStatus.optional)
            TextButton(
              onPressed: () {
                Navigator.pop(context); 
              },
              child: const Text("لاحقًا"),
            ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(result.storeUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: const Text("تحديث الآن"),
          ),
        ],
      ),
    );
  }

  Future<void> _initAsGuest(String deviceId, Box box) async {
    try {
      // الاعتماد على ApiClient دون حقن الهيدرز يدوياً
      final response = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        AppState().updateFromInitData(response.data);

        bool serverFreeMode = response.data['freeModeV3'] ?? false;
        if (Platform.isAndroid) {
          serverFreeMode = false;
        }
        await box.put('free_mode', serverFreeMode);

        // ✅ 3. تحديث قنوات الإشعارات للزائر
        if (response.data['myAccess'] != null && response.data['myAccess']['topics'] != null) {
          List<String> topics = List<String>.from(response.data['myAccess']['topics']);
          await NotificationService().updateSubscriptions(topics);
        }
      }
    } catch (_) {
    } finally {
      AppState().isGuest = true;
      if (mounted) {
        if (!await SecurityManager.instance.checkSecurity()) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainWrapper()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _initAsUser(String userId, String deviceId, Box box) async {
    try {
      // الاعتماد الكامل على ApiClient لحقن الهيدرز والتوكنز بشكل مركزي
      final response = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        AppState().updateFromInitData(response.data);

        bool serverFreeMode = response.data['freeModeV3'] ?? false;
        if (Platform.isAndroid) {
          serverFreeMode = false;
        }
        await box.put('free_mode', serverFreeMode);

        await StorageService.saveFullAppInitData(
            Map<String, dynamic>.from(response.data));

        if (response.data['user'] != null &&
            response.data['user']['phone'] != null) {
          await StorageService.saveUserPhone(response.data['user']['phone']);
        }
        if (response.data['contactInfo'] != null) {
          await StorageService.saveContactInfo(
            whatsapp: response.data['contactInfo']['whatsapp'] ?? '',
            telegram: response.data['contactInfo']['telegram'] ?? '',
          );
        }

        if (response.data['user'] != null) {
          final userData = response.data['user'];

          if (userData['role'] != null) {
            await box.put('role', userData['role']);
          }

          if (userData['profile_image'] != null) {
            await box.put('profile_image', userData['profile_image']);
          }
        }

        // ✅ 5. تحديث قنوات الإشعارات (Topics) للمستخدم المسجل بناءً على كورساته
        if (response.data['myAccess'] != null && response.data['myAccess']['topics'] != null) {
          List<String> topics = List<String>.from(response.data['myAccess']['topics']);
          await NotificationService().updateSubscriptions(topics);
        }

        bool isLoggedIn = response.data['isLoggedIn'] ?? false;

        if (!isLoggedIn) {
          await box.clear(); 
          await box.put('terms_accepted', true);

          if (mounted) {
            if (!await SecurityManager.instance.checkSecurity()) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
          return;
        }

        if (mounted) {
          if (!await SecurityManager.instance.checkSecurity()) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainWrapper()),
            (route) => false,
          );
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (serverError) {
      FirebaseCrashlytics.instance.log("Splash Offline Mode: $serverError");

      bool offlineSuccess = await AppState().loadOfflineData();

      if (offlineSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("No Internet. Entering Offline Mode."),
              backgroundColor: AppColors.accentOrange,
              duration: const Duration(seconds: 3),
            ),
          );

          if (!await SecurityManager.instance.checkSecurity()) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainWrapper()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Offline Mode (Limited Access)"),
                backgroundColor: Colors.grey),
          );

          if (!await SecurityManager.instance.checkSecurity()) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainWrapper()),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final isTablet = size.shortestSide > 600;
    final logoWidth =
        size.width * (isLandscape ? 0.25 : (isTablet ? 0.4 : 0.6));

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              AnimatedBuilder(
                animation: _bounceAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -_bounceAnimation.value),
                    child: child,
                  );
                },
                child: Image.asset(
                  'assets/images/logo.png',
                  width: logoWidth,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "EMPOWERING YOUR GROWTH",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentOrange,
                  letterSpacing: 4.0,
                ),
              ),
              const Spacer(flex: 2),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 160,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.4 + (0.6 * _progressAnimation.value),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.accentYellow.withOpacity(0.6),
                                  blurRadius: 12,
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "LOADING SYSTEM",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6.0,
                      color: AppColors.textSecondary.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
