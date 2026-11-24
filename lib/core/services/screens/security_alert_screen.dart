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

  // إعادة الفحص (نفس منطق الزر السابق بدون أي تغيير)
  Future<void> _retry() async {
    // 1. تصفير القيمة أولاً لإجبار الواجهة على الاستعداد (التخلص من الحالة القديمة)
    SecurityManager.instance.securityBreachReason.value = null;

    // 2. انتظار بسيط جداً لضمان معالجة الـ Reset
    await Future.delayed(const Duration(milliseconds: 100));

    // 3. استدعاء الفحص الشامل فوراً
    bool isSafe = await SecurityManager.instance.forceReCheck();

    if (isSafe) {
      // إذا أصبح آمناً، الـ Overlay سيختفي تلقائياً لأن القيمة أصبحت null
      snackbarKey.currentState?.showSnackBar(
        const SnackBar(content: Text("تم تحديث الحالة: الجهاز آمن الآن")),
      );
    } else {
      // إذا لا زال هناك خرق، سيقوم forceReCheck بتحديث القيمة وظهور الشاشة الحمراء مجدداً
      snackbarKey.currentState?.showSnackBar(
        const SnackBar(
            content: Text("فشل التحقق: لا تزال المشكلة قائمة"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openSettings() async {
    try {
      await _settingsChannel.invokeMethod("openSettings");
    } catch (e) {
      debugPrint("Failed to open settings: $e");
    }
  }

  Widget _buildNotice({required bool compact}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 32),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "⚠️ تنويه",
            style: TextStyle(
                color: Colors.yellow,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none),
          ),
          const SizedBox(height: 8),
          Text(
            "يرجى إغلاق التطبيقات المخالفة أو إيقاف خيارات المطور لضمان عمل التطبيق بأمان.",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 14,
                decoration: TextDecoration.none),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  Widget _buildButtons({required bool compact}) {
    final padding =
        EdgeInsets.symmetric(horizontal: compact ? 20 : 32, vertical: 12);
    // Wrap بدل Row: لو العرض ضاق ينزل الزر الثاني لسطر جديد بدل ما يتقطع
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        ElevatedButton(
          onPressed: _retry,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.red.shade900,
            padding: padding,
          ),
          child: const Text(
            "إعادة المحاولة",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          onPressed: _openSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: padding,
          ),
          child: const Text(
            "فتح الإعدادات",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildReason({required double fontSize}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        breachReason, // النص المحدد لسبب الخرق (مثلاً: خيارات المطور مفعلة)
        textAlign: TextAlign.center,
        style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none),
      ),
    );
  }

  // 📱 الوضع الرأسي: نفس التصميم السابق
  Widget _buildPortrait() {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildReason(fontSize: 20),
        ),
        const SizedBox(height: 32),
        _buildNotice(compact: false),
        const SizedBox(height: 40),
        _buildButtons(compact: false),
      ],
    );
  }

  // 🖥️ الوضع الأفقي (مشغلات الفيديو): عمودان جنب بعض، والأزرار تحت التنويه
  // مباشرة بدون ما تحتاج سكرول، ولو الشاشة صغيرة جداً يشتغل السكرول.
  Widget _buildLandscape() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.shieldAlert,
                    color: Colors.white, size: 48),
                const SizedBox(height: 12),
                const Text(
                  "SECURITY ALERT",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                _buildReason(fontSize: 16),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNotice(compact: true),
                const SizedBox(height: 16),
                _buildButtons(compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.red.shade900, // لون أحمر داكن للتحذير
      body: SafeArea(
        // ✅ SafeArea + سكرول: في الوضع الأفقي (ارتفاع قليل) كان الـ Column
        // يتجاوز ارتفاع الشاشة فتخرج الأزرار خارجها ولا تظهر.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: isLandscape ? _buildLandscape() : _buildPortrait(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
