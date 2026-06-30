import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // ✅ إضافة مكتبة Hive
import 'package:lucide_icons/lucide_icons.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class CourseCard extends StatelessWidget {
  final CourseModel course;
  final VoidCallback onTap;
  final bool isTeacher; // ✅ متغير لتحديد الصلاحية
  final VoidCallback? onEdit; // ✅ دالة عند الضغط على زر التعديل

  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    this.isTeacher = false, // القيمة الافتراضية
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ 1. قراءة حالة الوضع المجاني من الذاكرة المحلية
    // (يتم فتح الصندوق في Splash Screen لذلك يمكن استدعاؤه مباشرة هنا)
    final box = Hive.box('auth_box');
    final bool isFreeMode = box.get('free_mode', defaultValue: false);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. صورة الكورس
            Container(
              height: 140,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  // صورة الخلفية
                  if (course.imageUrl != null && course.imageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.network(
                        course.imageUrl!,
                        width: double.infinity,
                        height: 140,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(LucideIcons.image,
                              color: Colors.white10, size: 48),
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(LucideIcons.image,
                          color: Colors.white10, size: 48),
                    ),

                  // Badge للمادة (يسار علوي)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        course.subject.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.accentYellow,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // كود الكورس (أسفل يمين الصورة)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppColors.accentOrange.withOpacity(0.3),
                            width: 0.5),
                      ),
                      child: Text(
                        "#${course.code}",
                        style: const TextStyle(
                          color: AppColors.accentOrange,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),

                  // 🟢 زر التعديل (يمين علوي - يظهر للمعلم فقط)
                  if (isTeacher)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onEdit, // استدعاء دالة التعديل
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4),
                            ],
                          ),
                          child: const Icon(LucideIcons.edit2,
                              size: 16, color: Colors.black),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 2. تفاصيل الكورس
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Icon(LucideIcons.user,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        course.instructorName,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),

                  // السعر وزر السهم
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ✅ منطق إخفاء السعر
                      isFreeMode
                          ? Text(
                              AppLocalizations.of(context)!.freeAccessLabel,
                              style: TextStyle(
                                color: AppColors.success, // لون أخضر مميز
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            )
                          : Text(
                              "${course.fullPrice.toInt()} EGP",
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),

                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DirectionalFlip(child: Icon(LucideIcons.arrowRight,
                            size: 16, color: Colors.black)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
