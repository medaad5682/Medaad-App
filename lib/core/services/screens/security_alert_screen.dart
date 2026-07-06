import 'package:Medaad/core/services/security_manager.dart';
import 'package:Medaad/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SecurityAlertScreen extends StatelessWidget {
  const SecurityAlertScreen({
    super.key,
    required MethodChannel settingsChannel,
    required this.breachReason,
  }) : _settingsChannel = settingsChannel;

  final String breachReason;
  final MethodChannel _settingsChannel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: Container(
        color: Colors.red.shade900, // لون أحمر داكن للتحذير
        width: double.infinity,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.shieldAlert, color: Colors.white, size: 80),
            const SizedBox(height: 24),
            const Text(
              "SECURITY ALERT",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 16),

            // ✅ عرض سبب المشكلة الفعلي القادم من SecurityManager
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                breachReason, // هنا سيظهر النص المحدد (مثلاً: خيارات المطور مفعلة)
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none),
              ),
            ),
            const SizedBox(height: 32),

            // ⚠️ صندوق التهديد بالحظر
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.yellow, width: 2),
              ),
              child: const Column(
                children: [
                  Text(
                    "⚠️ تنويه",
                    style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "يرجى إغلاق التطبيقات المخالفة أو إيقاف خيارات المطور لضمان عمل التطبيق بأمان.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        decoration: TextDecoration.none),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
            // ElevatedButton(
            //   onPressed: () => exit(0), // إغلاق التطبيق فوراً
            //   style: ElevatedButton.styleFrom(
            //     backgroundColor: Colors.white,
            //     foregroundColor: Colors.red.shade900,
            //     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            //   ),
            //   child: const Text("إغلاق التطبيق / EXIT", style: TextStyle(fontWeight: FontWeight.bold)),
            // )
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    // 1. تصفير القيمة أولاً لإجبار الواجهة على الاستعداد (التخلص من الحالة القديمة)
                    SecurityManager.instance.securityBreachReason.value = null;

                    // 2. انتظار بسيط جداً لضمان معالجة الـ Reset
                    await Future.delayed(const Duration(milliseconds: 100));

                    // 3. استدعاء الفحص الشامل فوراً
                    bool isSafe = await SecurityManager.instance.forceReCheck();

                    if (isSafe) {
                      // إذا أصبح آمناً، الـ Overlay سيختفي تلقائياً لأن القيمة أصبحت null
                      snackbarKey.currentState?.showSnackBar(
                        const SnackBar(
                            content: Text("تم تحديث الحالة: الجهاز آمن الآن")),
                      );
                    } else {
                      // إذا لا زال هناك خرق، سيقوم forceReCheck بتحديث القيمة وظهور الشاشة الحمراء مجدداً
                      snackbarKey.currentState?.showSnackBar(
                        const SnackBar(
                            content: Text("فشل التحقق: لا تزال المشكلة قائمة"),
                            backgroundColor: Colors.red),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                  ),
                  child: const Text(
                    "إعادة المحاولة",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),

                // زر اختياري لفتح الإعدادات
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _settingsChannel.invokeMethod("openSettings");
                    } catch (e) {
                      debugPrint("Failed to open settings: $e");
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                  ),
                  child: const Text(
                    "فتح الإعدادات",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
