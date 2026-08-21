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
import '../../l10n/generated/app_localizations.dart';

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

  // ✅ [FIX] عدد محاولات إعادة تشغيل التهيئة عند مواجهة
  // StorageKeyUnavailableException تحديداً (مفتاح موجود مسبقاً لكن تعذّرت
  // قراءته الآن). هذا منفصل تماماً عن عدّاد الفشل المتتالي عبر عمليات
  // الإقلاع الموجود داخل StorageService — هذا هنا لإعادة محاولة سريعة
  // ضمن نفس فتحة التطبيق قبل الاستسلام والذهاب لشاشة تسجيل الدخول.
  int _storageUnavailableRetryCount = 0;
  static const int _maxStorageUnavailableRetries = 2;

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
                AppLocalizations.of(context)!.termsWelcomeTitle,
                style: TextStyle(
                    color: AppColors.accentYellow, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.termsDialogBody,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      dense: true,
                      leading: Icon(LucideIcons.fileText,
                          color: AppColors.accentOrange, size: 20),
                      title: Text(AppLocalizations.of(context)!.termsAndConditions,
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
                      title: Text(AppLocalizations.of(context)!.privacyPolicy,
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
                  child: Text(AppLocalizations.of(context)!.decline,
                      style: TextStyle(color: AppColors.error)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  child: Text(AppLocalizations.of(context)!.accept,
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

      // ✅ [FIX] StorageService.ensureInitialized() بدل Hive.initFlutter()
      // المباشرة — main.dart يستدعي نفس الدالة بالتوازي تقريباً (fire-and-
      // forget بعد runApp())، فيتقاسم الاثنان نتيجة تهيئة واحدة بدل
      // تكرارها. auth_box وdownloads_box يبقيان يُفتحان هنا كما كانا: هذه
      // الشاشة هي المالك الفعلي لهما عند الإقلاع (تحتاج auth_box فوراً
      // لقراءة terms_accepted/is_guest/user_id)، وmain.dart لم يعد يفتحهما
      // بنفسه (راجع _initStorageAfterAppReady في main.dart).
      await StorageService.ensureInitialized();
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
    } on StorageKeyUnavailableException catch (e, stack) {
      // ✅ [FIX - جذر مشكلة "شاشة تسجيل دخول تظهر بدون سبب"] هذا الاستثناء
      // تحديداً يعني: المفتاح موجود ومزوّد مسبقاً على هذا الجهاز (المستخدم
      // مسجّل دخول فعلياً وبياناته سليمة)، لكن تعذّرت قراءته من Keychain
      // في هذه اللحظة بالذات — وهي غالباً حالة عابرة جداً (مللي ثوانٍ) وليست
      // "المستخدم غير مسجل دخول". من قبل، كانت هذه الحالة تسقط في الـ catch
      // العام أدناه وتُرسل المستخدم مباشرة لشاشة تسجيل الدخول دون أي محاولة
      // لاستدعاء get-app-init-data — وهذا بالضبط ما وصفتَه: "لا يوجد نداء
      // لـ API فشاشة البداية تذهب لشاشة تسجيل الدخول مباشرة".
      //
      // الآن: نعيد محاولة كامل التهيئة (والتي تتضمن إعادة قراءة المفتاح عبر
      // StorageService، بما في ذلك مسار الترحيل بين صنفي الحماية) عدداً
      // محدوداً من المرات ضمن نفس فتحة التطبيق قبل الاستسلام، بدل الحكم على
      // أول فشل بأنه "غير مسجل دخول".
      FirebaseCrashlytics.instance.log(
        "Splash: StorageKeyUnavailableException, retry "
        "${_storageUnavailableRetryCount + 1}/$_maxStorageUnavailableRetries: $e",
      );

      if (_storageUnavailableRetryCount < _maxStorageUnavailableRetries) {
        _storageUnavailableRetryCount++;
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) await _initializeApp();
        return;
      }

      // استنفدنا المحاولات ضمن هذه الفتحة — نسجّل الحدث (وليس كخطأ فادح،
      // فالبيانات سليمة ولم تُحذف) وننتقل لشاشة تسجيل الدخول كحل أخير، مع
      // ترك مسار last-resort reset داخل StorageService (بعد 3 إقلاعات
      // متتالية فاشلة) ليتعامل مع الحالة النادرة لفقدان المفتاح الفعلي.
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason:
            'Splash: exhausted in-session retries for StorageKeyUnavailableException, falling back to Login (data preserved)',
        fatal: false,
      );
      if (mounted) {
        if (!await SecurityManager.instance.checkSecurity()) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e, stack) {
      // أي خطأ آخر غير متوقع (تلف بيانات فعلي، فشل Hive، إلخ) — نحافظ على
      // السلوك الأصلي: تسجيل الخطأ والذهاب لشاشة تسجيل الدخول.
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
        title: Text(AppLocalizations.of(context)!.appUpdateTitle),
        content: Text(result.message),
        actions: [
          if (result.status == UpdateStatus.optional)
            TextButton(
              onPressed: () {
                Navigator.pop(context); 
              },
              child: Text(AppLocalizations.of(context)!.updateLater),
            ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(result.storeUrl);
              // ✅ إصلاح Crash فادح: launchUrl() على iOS يفتح الرابط
              // افتراضيًا داخل SafariViewController مضمّن داخل التطبيق. إذا
              // فشل تحميل الصفحة داخل هذا العرض المضمّن (لا يوجد اتصال،
              // إعادة توجيه غير متوقعة، إلخ)، يرمي url_launcher_ios
              // استثناءً. بما أن هذا الاستدعاء يقع داخل onPressed غير
              // منتظر (unawaited) بلا try/catch، كان الاستثناء يهرب إلى
              // معالج الأخطاء غير الملتقطة في الـ Zone ويُسقط التطبيق
              // بالكامل (Fatal Exception كما ظهر في Crashlytics).
              //
              // الحل: (1) استخدام LaunchMode.externalApplication لأن رابط
              // المتجر (App Store / Play Store) يجب أن يفتح التطبيق
              // الأصلي للمتجر مباشرة وليس متصفحًا مضمّنًا — وهو الأنسب هنا
              // على أي حال، و(2) لف الاستدعاء بـ try/catch حتى لا يسقط أي
              // فشل غير متوقع التطبيق، مع تسجيله كخطأ غير فادح وإعلام
              // المستخدم بدلاً من ذلك.
              try {
                final launched = await canLaunchUrl(uri) &&
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!launched && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .couldNotOpenStoreLink)),
                  );
                }
              } catch (e, stack) {
                FirebaseCrashlytics.instance.recordError(
                  e,
                  stack,
                  reason: 'Update store link launch failed',
                  fatal: false,
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.updateNow),
          ),
        ],
      ),
    );
  }

  Future<void> _initAsGuest(String deviceId, Box box) async {
    try {
      // ✅ استرجاع توكن الإشعارات
      String? fcmToken = box.get('fcm_token');

      // الاعتماد على ApiClient دون حقن الهيدرز يدوياً باستثناء الهيدرز الخاصة بهذه العملية
      final response = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            'x-user-id': '0', // للزائر (Guest)
            if (fcmToken != null) 'x-fcm-token': fcmToken, // توكن الإشعارات
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        AppState().updateFromInitData(response.data);

        bool serverFreeMode = response.data['freeModeV7'] ?? false;
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
      // ✅ استرجاع توكن الإشعارات
      String? fcmToken = box.get('fcm_token');

      // الاعتماد الكامل على ApiClient لحقن الهيدرز والتوكنز بشكل مركزي مع إضافة توكن الإشعارات
      final response = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-app-init-data',
        options: Options(
          headers: {
            if (fcmToken != null) 'x-fcm-token': fcmToken, // توكن الإشعارات
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        AppState().updateFromInitData(response.data);

        bool serverFreeMode = response.data['freeModeV7'] ?? false;
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

          if (userData['email'] != null) {
            await box.put('email', userData['email']);
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
              content: Text(AppLocalizations.of(context)!.offlineModeEnteredMessage),
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
            SnackBar(
                content: Text(AppLocalizations.of(context)!.offlineModeLimitedMessage),
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

    // ✅ النص العربي (حروف متصلة) يحتاج خطاً أكبر وتباعد أحرف أقل
    // ليبقى مقروءاً، بعكس النص الإنجليزي المتباعد بتصميمه.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final taglineFontSize = isArabic ? 14.0 : 10.0;
    final taglineLetterSpacing = isArabic ? 1.0 : 4.0;
    final loadingFontSize = isArabic ? 12.0 : 9.0;
    final loadingLetterSpacing = isArabic ? 2.0 : 6.0;

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
                AppLocalizations.of(context)!.splashTagline,
                style: TextStyle(
                  fontSize: taglineFontSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentOrange,
                  letterSpacing: taglineLetterSpacing,
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
                    AppLocalizations.of(context)!.splashLoadingSystem,
                    style: TextStyle(
                      fontSize: loadingFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: loadingLetterSpacing,
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
