import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
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
        displayLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        headlineLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary,
          fontSize: 16,
        ),
        bodyMedium: GoogleFonts.roboto(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelLarge: GoogleFonts.roboto(
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
