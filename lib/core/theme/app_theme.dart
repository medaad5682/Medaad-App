import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  // ✅ [CRASH-FIX v2.1.2] تم التخلي عن حزمة google_fonts (كانت تنهار بسبب
  // غياب ملفات الخط داخل الـ assets مع تعطيل التحميل من الشبكة). الآن Roboto
  // مُضمَّن فعليًا في pubspec.yaml (assets/fonts) ويُطبَّق على كامل التطبيق عبر
  // ThemeData.fontFamily، فيظهر متطابقًا على Android و iOS ولا يحتاج إنترنت.
  // الأوزان المتوفرة: 400 / 500 / 700 / 900 (الوزن 600 يُختار له 700 تلقائيًا).
  static const String _fontFamily = 'Roboto';

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      // ملاحظة: سيتم تجاوز brightness في main.dart بناءً على الوضع الحالي
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundPrimary,
      primaryColor: AppColors.accentYellow,
      
      // ❌ تم إزالة const من هنا لتسمح بتغيير الألوان
      colorScheme: ColorScheme.dark(
        primary: AppColors.accentYellow,
        onPrimary: AppColors.backgroundPrimary,
        secondary: AppColors.accentOrange,
        surface: AppColors.backgroundSecondary,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),

      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        headlineLarge: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.textPrimary,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelLarge: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),

      // ✅ تم حذف CardTheme لتجنب تعارض الأنواع
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentYellow,
          foregroundColor: AppColors.backgroundPrimary,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          // ❌ تم إزالة const من هنا لأن accentYellow متغير
          borderSide: BorderSide(color: AppColors.accentYellow, width: 1),
        ),
        // ❌ تم إزالة const من هنا
        hintStyle: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
