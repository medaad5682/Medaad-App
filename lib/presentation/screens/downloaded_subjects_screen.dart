import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'downloaded_chapters_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class DownloadedSubjectsScreen extends StatelessWidget {
  final String courseTitle;

  const DownloadedSubjectsScreen({super.key, required this.courseTitle});

  @override
  Widget build(BuildContext context) {
    // 1. جلب صندوق التخزين
    var box = Hive.box('downloads_box');
     
    // 2. تصفية وتجميع المواد الخاصة بالكورس الحالي
    // Map<SubjectName, FileCount>
    final Map<String, int> groupedSubjects = {};
     
    for (var key in box.keys) {
      final item = box.get(key);
      if (item['course'] == courseTitle) {
        final subject = item['subject'] ?? AppLocalizations.of(context)!.unknownSubjectFallback;
        groupedSubjects[subject] = (groupedSubjects[subject] ?? 0) + 1;
      }
    }

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
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courseTitle.toUpperCase(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            overflow: TextOverflow.ellipsis,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)!.downloadedSubjectsLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentYellow.withOpacity(0.8),
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: groupedSubjects.isEmpty
                  ? Center(child: Text(AppLocalizations.of(context)!.noSubjectsFound, style: TextStyle(color: Colors.white.withOpacity(0.5))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: groupedSubjects.length,
                      itemBuilder: (context, index) {
                        final subjectName = groupedSubjects.keys.elementAt(index);
                        final fileCount = groupedSubjects.values.elementAt(index);

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DownloadedChaptersScreen(
                                courseTitle: courseTitle,
                                subjectTitle: subjectName,
                              ),
                            ),
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundPrimary,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                  ),
                                  child: Icon(LucideIcons.layers, color: AppColors.accentYellow, size: 18),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subjectName.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                          letterSpacing: -0.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppLocalizations.of(context)!.filesCountLabel(fileCount),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textSecondary.withOpacity(0.7),
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DirectionalFlip(child: Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: 18)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
