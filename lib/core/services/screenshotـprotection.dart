import 'package:flutter/services.dart';

// ✅ إضافة دالة آمنة للطباعة تظهر فقط في وضع التطوير (Debug)
void _safePrint(Object? message) {
  assert(() {
    print(message);
    return true;
  }());
}

class ScreenshotProtection {
  static const _channel = MethodChannel('screenshot_protection');

  // تفعيل الحماية
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enableProtection');
      _safePrint('✅ Screenshot protection enabled'); // ✅ استخدام الطباعة الآمنة
    } catch (e) {
      _safePrint('❌ Error enabling protection: $e'); // ✅ استخدام الطباعة الآمنة
    }
  }

  // تعطيل الحماية
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disableProtection');
      _safePrint('✅ Screenshot protection disabled'); // ✅ استخدام الطباعة الآمنة
    } catch (e) {
      _safePrint('❌ Error disabling protection: $e'); // ✅ استخدام الطباعة الآمنة
    }
  }
}
