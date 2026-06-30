import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
                      "سياسة الخصوصية\nPRIVACY POLICY",
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
                        "1. جمع البيانات والأذونات",
                        "1. Data Collection & Permissions",
                        "نقوم بجمع معرّف فريد يتم إنشاؤه داخل التطبيق للمساعدة في تأمين حسابك وربطه بجهاز واحد فقط. يتم استخدام هذا المعرّف لأغراض الأمان ووظائف التطبيق فقط، ولا يتم استخدامه للتتبع أو الإعلانات.\n\nنستخدم الإشعارات لإعلامك بحالة تحميل الدروس والتحديثات المهمة، لضمان استمرار التحميل وبقائك على اطلاع حتى عند تشغيل التطبيق في الخلفية.",
                        "We collect a unique app-generated identifier to help secure your account and associate it with a single device. This identifier is used solely for security and functionality purposes and is not used for tracking or advertising.\n\nWe use Notifications to inform you about lesson download status and important updates, ensuring downloads can continue and you stay informed even when the app is in the background."
                      ),
                      Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 40),
                      
                      _buildSection(
                        "2. متطلبات أمان الجهاز",
                        "2. Device Security Requirements",
                        "لحماية المحتوى والخدمات، قد لا تعمل بعض الميزات بشكل صحيح على الأجهزة التي تم تعديل نظامها (مثل الأجهزة التي تم عمل Root أو Jailbreak لها) أو التي تم تفعيل بعض الإعدادات على مستوى النظام. لا يمكننا ضمان أمان أو استقرار التطبيق في هذه الحالات.",
                        "To help protect our content and services, some features may not function properly on devices that have been modified (such as rooted or jailbroken devices) or where certain system-level settings are enabled. We cannot guarantee the security or stability of the app in these environments."
                      ),
                      Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 40),

                      _buildSection(
                        "3. حماية المحتوى",
                        "3. Content Protection",
                        "جميع الفيديوهات والمواد التعليمية مخصصة للاستخدام الشخصي غير التجاري فقط. نطبق إجراءات تقنية وتنظيمية مناسبة للمساعدة في حماية المحتوى من الوصول أو النسخ أو إعادة التوزيع غير المصرح بها، مع الحفاظ على تجربة تعلم سلسة للمستخدمين.",
                        "All educational videos and materials are provided for personal, non-commercial use only. We apply reasonable technical and organizational measures to help protect our content from unauthorized access, copying, or redistribution, while ensuring a smooth learning experience for our users."
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
      crossAxisAlignment: CrossAxisAlignment.end, // العربية محاذاة لليمين
      children: [
        // العربية
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
        
        // الإنجليزية
        Align(
          alignment: Alignment.centerLeft, // الإنجليزية محاذاة لليسار
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
