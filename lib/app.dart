import 'package:Medaad/core/services/app_state.dart';
import 'package:Medaad/core/services/audio_protection_service.dart';
import 'package:Medaad/core/services/screens/security_alert_screen.dart';
import 'package:Medaad/core/services/security_manager.dart';
import 'package:Medaad/core/theme/app_theme.dart';
import 'package:Medaad/main.dart';
import 'package:Medaad/presentation/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EduVantageApp extends StatefulWidget {
  const EduVantageApp({super.key});

  @override
  State<EduVantageApp> createState() => _EduVantageAppState();
}

class _EduVantageAppState extends State<EduVantageApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // ScreenshotProtection.enable();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ScreenshotProtection.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة تفعيل الحظر عند العودة للتطبيق
      AudioProtectionService().blockAudioCapture();
      
      // ✅ أضف تأخير بسيط (500 ملي ثانية) لتجنب مشكلة الـ Race Condition مع النظام
      Future.delayed(const Duration(milliseconds: 500), () {
        SecurityManager.instance.checkSecurity();
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    const MethodChannel _settingsChannel = MethodChannel("app.settings");
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState().themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: snackbarKey,
          debugShowCheckedModeBanner: false,
          title: 'مــــداد',
          theme: AppTheme.darkTheme.copyWith(
            brightness: currentMode == ThemeMode.dark
                ? Brightness.dark
                : Brightness.light,
          ),
          themeMode: currentMode,

          // ✅ هنا نطبق "الشاشة الحمراء" كطبقة فوق كل التطبيق (Global Overlay)
          builder: (context, child) {
            return Stack(
              textDirection: TextDirection.ltr,
              children: [
                if (child != null) child, // التطبيق الطبيعي

                // ✅ التعديل: الاستماع لمتغير النص (String?) بدلاً من البوليان
                ValueListenableBuilder<String?>(
                  valueListenable:
                      SecurityManager.instance.securityBreachReason,
                  builder: (context, breachReason, _) {
                    // إذا كان السبب null (لا يوجد اختراق)، نخفي الطبقة
                    if (breachReason == null) return const SizedBox.shrink();

                    // 🛑 إذا وجد نص، نظهر الشاشة الحمراء مع السبب المحدد
                    return Material(
                      type: MaterialType.transparency,
                      child: SecurityAlertScreen(
                          settingsChannel: _settingsChannel,
                          breachReason: breachReason),
                    );
                  },
                ),
              ],
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
