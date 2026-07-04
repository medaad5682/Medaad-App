import 'package:flutter/material.dart';
// ✅ [FIX F-11] استدعاء مكتبة حماية النوافذ
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

class ScreenProtectWrapper extends StatefulWidget {
  final Widget child;
  const ScreenProtectWrapper({super.key, required this.child});

  @override
  State<ScreenProtectWrapper> createState() => _ScreenProtectWrapperState();
}

class _ScreenProtectWrapperState extends State<ScreenProtectWrapper>
    with WidgetsBindingObserver {
  bool _isProtected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ✅ [FIX F-11] تفعيل الحماية فوراً من مستوى نظام التشغيل قبل رسم أي إطار
    _secureScreen(); 
  }

  Future<void> _secureScreen() async {
    try {
      // هذا الأمر يمنع أخذ لقطات شاشة أو تصوير فيديو من الخلفية (App Switcher)
      // ويقضي على ثغرة الـ Race Condition الزمني تماماً
      
      // ** تم التهميش مؤقتاً لتصوير الفيديو **
      // await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
    } catch (e) {
      debugPrint("Failed to secure screen: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // لو التطبيق راح للخلفية
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
          
      // ** تم التهميش مؤقتاً لتصوير الفيديو لمنع الشاشة السوداء عند سحب الإشعارات **
      // setState(() => _isProtected = true);
      
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _isProtected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // ✅ طبقة بصرية إضافية (Fallback) تحجب المحتوى تماماً باللون الأسود
        if (_isProtected)
          Positioned.fill(
            child: Container(color: Colors.black),
          ),
      ],
    );
  }
}
