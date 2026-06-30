import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                      ),
                      child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "الشروط والأحكام\nTERMS & CONDITIONS",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      _buildSection(
                        "1. استخدام الحساب",
                        "1. Account Usage",
                        "الحساب شخصي وغير قابل للمشاركة. يتم ربط الحساب بجهازك، وأي محاولة للدخول من جهاز آخر ستؤدي إلى إغلاق الحساب.",
                        "Your account is personal and non-transferable. It is linked to your device, and attempting to log in from another device will lock your account."
                      ),
                      Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 40),
                      
                      _buildSection(
                        "2. الأنشطة المحظورة",
                        "2. Prohibited Activities",
                        "يُمنع منعاً باتاً استخدام التطبيق في بيئة Root أو Jailbreak، أو تفعيل خيارات المطور، أو محاولة الهندسة العكسية للتطبيق. يحق لنا إيقاف الخدمة نهائياً دون سابق إنذار في حال اكتشاف ذلك.",
                        "It is strictly prohibited to use the app in a Rooted/Jailbroken environment, enable Developer Options, or attempt reverse engineering. We reserve the right to terminate service immediately without notice if detected."
                      ),
                      Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 40),

                      // ✅ تم التعديل هنا لإزالة أي ذكر للدفع
                      _buildSection(
                        "3. الوصول للمحتوى",
                        "3. Content Access",
                        "يتم تفعيل الوصول للمحتوى التعليمي (الكورسات والمواد) عن طريق الإدارة أو أكواد التفعيل المخصصة. تحتفظ الإدارة بحق تنظيم الوصول وإدارة الصلاحيات.",
                        "Access to educational content (courses and subjects) is activated via administration or specific activation codes. The administration reserves the right to regulate access and manage permissions."
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String arTitle, String enTitle, String arBody, String enBody) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Arabic Section
        Text(
          arTitle,
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          arBody,
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.textPrimary, height: 1.6, fontSize: 14),
        ),
        
        const SizedBox(height: 16),
        
        // English Section
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enTitle,
                style: TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                enBody,
                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), height: 1.4, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
