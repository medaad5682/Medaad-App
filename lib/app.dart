import 'package:Medaad/core/services/app_state.dart';
import 'package:Medaad/core/services/audio_protection_service.dart';
import 'package:Medaad/core/services/floating_video_controller.dart';
import 'package:Medaad/core/services/screens/security_alert_screen.dart';
import 'package:Medaad/core/services/security_manager.dart';
import 'package:Medaad/core/theme/app_theme.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';
import 'package:Medaad/main.dart';
import 'package:Medaad/presentation/screens/splash_screen.dart';
import 'package:Medaad/presentation/widgets/floating_video_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================
// ✅ إصلاح: النافذة العائمة كانت تمنع أي لمسة من الوصول للشاشة التي
// تطفو فوقها (تعذّر الضغط على أي زر آخر أو الانتقال بين الشاشات).
//
// السبب: كنا نستخدم PageRouteBuilder كمسار للـ Navigator المحلي الذي
// يوفر سلف Navigator صالح لِـ BetterPlayer فقط. لكن PageRouteBuilder
// يرث من ModalRoute، وModalRoute — بغض النظر عن opaque أو barrierColor
// أو barrierDismissible — يُنشئ دائمًا "ModalBarrier" خفي بحجم الشاشة
// كاملة (MouseRegion بخاصية opaque=true) يمتص كل لمسة موجهة لأي شيء
// خلفه. بما أن هذا الـ Navigator المحلي يُرسم فوق شجرة التطبيق الحقيقية
// في app.dart، فإن هذا الحاجز غير المرئي كان يمتص كل اللمسات المتجهة
// للشاشة الأصلية (باستثناء منطقة النافذة العائمة نفسها التي تُرسم فوقه).
//
// الحل: استبدال PageRouteBuilder بمسار مخصص خفيف الوزن يرث مباشرة من
// OverlayRoute (الأب الحقيقي لِـ ModalRoute) دون المرور بـ ModalRoute
// إطلاقًا — وبالتالي لا يتم إنشاء أي ModalBarrier من الأساس.
// ============================================================
class _NoBarrierOverlayRoute extends OverlayRoute<void> {
  _NoBarrierOverlayRoute({required this.pageBuilder});

  final WidgetBuilder pageBuilder;

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    return <OverlayEntry>[
      OverlayEntry(builder: pageBuilder, maintainState: true),
    ];
  }
}

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
    return ValueListenableBuilder<Locale>(
      valueListenable: AppState().localeNotifier,
      builder: (context, currentLocale, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: AppState().themeNotifier,
          builder: (context, currentMode, child) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              scaffoldMessengerKey: snackbarKey,
              debugShowCheckedModeBanner: false,
              title: 'مــــداد',

              // ✅ اللغة: تتحكم في الـ Directionality (RTL/LTR) تلقائياً عبر كامل التطبيق
              locale: currentLocale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,

              theme: AppTheme.darkTheme.copyWith(
                brightness: currentMode == ThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light,
              ),
              themeMode: currentMode,

              // ✅ هنا نطبق "الشاشة الحمراء" كطبقة فوق كل التطبيق (Global Overlay)
              builder: (context, child) {
                // ⚠️ ملاحظة: لا نستخدم Directionality.of(context) هنا لأن
                // الـ context الخاص بـ MaterialApp.builder قد يقع فوق
                // الـ Directionality التي يبنيها MaterialApp داخلياً من اللغة،
                // لذا نشتق الاتجاه مباشرة من currentLocale المتوفرة بالفعل.
                final overlayDirection = currentLocale.languageCode == 'ar'
                    ? TextDirection.rtl
                    : TextDirection.ltr;
                return Stack(
                  textDirection: overlayDirection,
                  children: [
                    if (child != null) child, // التطبيق الطبيعي

                    // ✅ الفيديو العائم: طبقة عالمية فوق كل شاشات التطبيق،
                    // تبقى ظاهرة أثناء التنقل بين الشاشات (push/pop) لأنها
                    // مثبّتة هنا فوق الـ Navigator وليس داخل شاشة واحدة.
                    ListenableBuilder(
                      listenable: FloatingVideoController.instance,
                      builder: (context, _) {
                        if (FloatingVideoController.instance.isFloating) {
                          // ✅ الفيديو العائم موضوع فوق الـ Navigator وليس من
                          // ذريته (انظر الملاحظة أعلاه)، لذا فإن BetterPlayer
                          // بداخله لا يجد أي Navigator كسلف. مكتبة
                          // better_player تستدعي Navigator.of(context) داخلياً
                          // بشكل غير مشروط عند didChangeDependencies (حتى مع
                          // enableFullscreen: false)، مما يسبب:
                          // "Navigator operation requested with a context
                          // that does not include a Navigator" فور الضغط على
                          // زر PIP. نلف الطبقة بـ Navigator محلي معزول تماماً
                          // عن تنقل التطبيق الفعلي — فقط ليوفر سلف Navigator
                          // صالح لِـ BetterPlayer.
                          // ✅ إصلاح: منع اللمسات من الوصول للشاشة أسفل النافذة
                          // العائمة. نستخدم الآن _NoBarrierOverlayRoute بدلاً من
                          // PageRouteBuilder — انظر التعليق التوضيحي أعلى الملف
                          // بجانب تعريف الكلاس لشرح السبب الكامل (ModalBarrier
                          // خفي بحجم الشاشة كان يمتص كل اللمسات).
                          return HeroControllerScope.none(
                            child: Navigator(
                            onGenerateRoute: (settings) =>
                                _NoBarrierOverlayRoute(
                              pageBuilder: (context) =>
                                  // ✅ الـ Overlay يلف محتوى الـ OverlayEntry تلقائياً بـ
                                  // Positioned.fill (سلوك خاص بـ Overlay/Theatre نفسه،
                                  // مستقل عن نوع الـ Route). ولأن FloatingVideoOverlay
                                  // يُرجع AnimatedPositioned كجذر (يتوقع أن يكون
                                  // ابنًا مباشرًا لِـ Stack)، فإن هذا يخلق
                                  // ParentDataWidget متعارضين (Positioned.fill من
                                  // الـ Overlay + AnimatedPositioned من الودجت) يتنافسان
                                  // على نفس الـ RenderObject — وهو ما كان يجعل
                                  // الفيديو يملأ الشاشة كاملة بدلاً من التموضع
                                  // الصغير المطلوب. نضيف Stack خاص بنا هنا حتى
                                  // يجد AnimatedPositioned سلف Stack صحيح يتموضع
                                  // بالنسبة له، بمعزل عن Positioned.fill الخاص
                                  // بالـ Overlay.
                                  Stack(
                                children: const [FloatingVideoOverlay()],
                              ),
                            ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                    // ✅ التعديل: الاستماع لمتغير النص (String?) بدلاً من البوليان
                    ValueListenableBuilder<String?>(
                      valueListenable:
                          SecurityManager.instance.securityBreachReason,
                      builder: (context, breachReason, _) {
                        // إذا كان السبب null (لا يوجد اختراق)، نخفي الطبقة
                        if (breachReason == null) {
                          return const SizedBox.shrink();
                        }

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
      },
    );
  }
}
