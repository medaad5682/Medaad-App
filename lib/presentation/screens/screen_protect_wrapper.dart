import 'package:flutter/material.dart';

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
      setState(() => _isProtected = true);
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _isProtected = false);
    }
  }

  @override
Widget build(BuildContext context) {
  // إرجاع الـ child مباشرة بدون الـ Stack الذي يحتوي على الكونتينر الأسود
  return widget.child;
}
}
