import 'package:flutter/material.dart';
import '../services/app_state.dart';

class AppColors {
  // ========================================================
  // 🌑 الوضع الليلي (ألوانك القديمة)
  // ========================================================
  static const Color _darkBgPrimary = Color(0xFF1a1b1e);
  static const Color _darkBgSecondary = Color(0xFF2a2b2f);
  static const Color _darkTextPrimary = Color(0xFFE2E8F0);
  static const Color _darkTextSecondary = Color(0xFF94A3B8);
  static const Color _darkAccentYellow = Color(0xFFdba91d); // زر قديم

  // ========================================================
  // ☀️ الوضع النهاري (الألوان الجديدة المطلوبة)
  // ========================================================
  static const Color _lightBgPrimary = Color(0xFFE0E5EC); // الخلفية الأساسية
  static const Color _lightBgSecondary = Color(0xFFF8F9FA); // اللون الثانوي
  static const Color _lightTextPrimary = Color(0xFF354F52); // لون النصوص
  static const Color _lightTextSecondary = Color(0xFF5F7D81); // لون نصوص فرعي (مشتق)
  static const Color _lightBtnInteractive = Color(0xFFA85832); // الأزرار التفاعلية

  // ========================================================
  // 🚀 المحول الذكي (Getters)
  // ========================================================
  
  // الخلفيات
  static Color get backgroundPrimary => AppState.isDark ? _darkBgPrimary : _lightBgPrimary;
  static Color get backgroundSecondary => AppState.isDark ? _darkBgSecondary : _lightBgSecondary;

  // النصوص
  static Color get textPrimary => AppState.isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary => AppState.isDark ? _darkTextSecondary : _lightTextSecondary;

  // الأزرار (Accent)
  // سنقوم بتغيير اللون الأصفر في الداكن إلى اللون الطوبي في الفاتح تلقائياً
  static Color get accentYellow => AppState.isDark ? _darkAccentYellow : _lightBtnInteractive;

  // حدود بطاقات الكورسات المتفرعة تحت مجلد باقة (nested):
  // - الداكن: نفس الحد الشفاف القديم (بدون أي تغيير).
  // - الفاتح: حد واضح، لأن لون البطاقة يطابق الخلفية فلا يظهر أي حد فاصل.
  static Color get nestedCardBorder => AppState.isDark
      ? Colors.white.withOpacity(0.05)
      : _lightTextSecondary.withOpacity(0.45);

  // ألوان ثابتة لا تتغير (إلا إذا أردت تغييرها أيضاً)
  static const Color accentOrange = Color(0xFFb45309);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
}
