import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/chapter_model.dart';

class ChapterAccordion extends StatelessWidget {
  final Chapter chapter;
  final int index;

  const ChapterAccordion({
    super.key,
    required this.chapter,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedIconColor: AppColors.textSecondary,
          iconColor: AppColors.accentYellow,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          // رقم الفصل
          leading: Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "${index + 1}`.padLeft(2, '0')",
              style:  TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold),
            ),
          ),
          // عنوان الفصل
          title: Text(
            chapter.title,
            style:  TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          // عدد الدروس
          subtitle: Text(
            chapter.subtitle,
            style:  TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          // قائمة الدروس داخل الفصل
          children: chapter.lessons.map((lesson) {
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                color: Colors.black.withOpacity(0.2), // لون أغمق قليلاً للدروس
              ),
              child: ListTile(
                contentPadding: const EdgeInsetsDirectional.only(start: 64, end: 16),
                title: Text(
                  lesson.title,
                  style:  TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
                subtitle: Text(
                  lesson.duration,
                  style:  TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                trailing: lesson.isFree
                    ? const Icon(LucideIcons.playCircle, color: AppColors.success, size: 20)
                    :  Icon(LucideIcons.lock, color: AppColors.textSecondary, size: 16),
                onTap: () {
                  if (lesson.isFree) {
                    // تشغيل الفيديو المجاني
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
