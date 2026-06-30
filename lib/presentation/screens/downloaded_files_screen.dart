import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import '../../core/constants/app_colors.dart';
import '../../core/services/local_proxy.dart';
import '../../core/services/download_manager.dart'; 
import 'downloaded_subjects_screen.dart';
import '../../core/services/storage_service.dart';
import '../../l10n/generated/app_localizations.dart';
// أو المسار المناسب حسب مكان الملف

class DownloadedFilesScreen extends StatefulWidget {
  const DownloadedFilesScreen({super.key});

  @override
  State<DownloadedFilesScreen> createState() => _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends State<DownloadedFilesScreen> {
  final LocalProxyService _proxy = LocalProxyService();
   
  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("User opened DownloadedFilesScreen");
    _init();
  }

  Future<void> _init() async {
    try {
      FirebaseCrashlytics.instance.log("Initializing Downloads Box and Proxy...");

      if (!Hive.isBoxOpen('downloads_box')) {
        await StorageService.openBox('downloads_box');
      }
       
      await _proxy.start();
       
      if (mounted) setState(() {});

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error initializing DownloadedFilesScreen', fatal: false);
    }
  }

  @override
  void dispose() {
    try {
      _proxy.stop();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Error stopping Local Proxy');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: Icon(LucideIcons.downloadCloud, color: AppColors.accentYellow, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.downloadsTitle,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              height: 1.0,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!.localCoursesLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Active Downloads Badge
                  ValueListenableBuilder<Map<String, double>>(
                    valueListenable: DownloadManager.downloadingProgress,
                    builder: (context, progressMap, _) {
                      if (progressMap.isEmpty) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.activeCountLabel(progressMap.length),
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentYellow),
                        ),
                      );
                    }
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: Hive.box('downloads_box').listenable(),
                builder: (context, Box box, _) {
                  final Map<String, int> groupedCourses = {};
                  try {
                    for (var key in box.keys) {
                      final item = box.get(key);
                      final courseName = item['course'] ?? AppLocalizations.of(context)!.unknownCourseFallback;
                      groupedCourses[courseName] = (groupedCourses[courseName] ?? 0) + 1;
                    }
                  } catch (e) {}

                  return ValueListenableBuilder<Map<String, double>>(
                    valueListenable: DownloadManager.downloadingProgress,
                    builder: (context, progressMap, child) {
                       
                      if (groupedCourses.isEmpty && progressMap.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 80),
                            child: Text(
                              AppLocalizations.of(context)!.noStoredFiles,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary.withOpacity(0.5), letterSpacing: 2.0),
                            ),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ✅ قسم التحميلات النشطة المعدل
                            if (progressMap.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 12),
                                child: Text(
                                  AppLocalizations.of(context)!.activeDownloadsLabel,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                                ),
                              ),
                              ...progressMap.entries.map((entry) {
                                final percent = (entry.value * 100).toInt();
                                final id = entry.key;
                                
                                // محاولة جلب الاسم (يتطلب إضافة خريطة titles في DownloadManager)
                                // أو سيظهر المعرف مؤقتاً
                                String title = AppLocalizations.of(context)!.downloadingItemPlaceholder;
                                if (DownloadManager().activeTitles.containsKey(id)) {
                                   title = DownloadManager().activeTitles[id]!;
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.accentYellow.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // اسم الملف
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          
                                          // النسبة وزر الإلغاء
                                          Row(
                                            children: [
                                              Text(AppLocalizations.of(context)!.downloadPercentLabel(percent), style: TextStyle(color: AppColors.accentYellow, fontSize: 12, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 12),
                                              
                                              // ✅ زر الإلغاء (X)
                                              GestureDetector(
                                                onTap: () {
                                                  // استدعاء دالة الإلغاء من المدير
                                                  DownloadManager().cancelDownload(id);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error.withOpacity(0.2),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(LucideIcons.x, size: 14, color: AppColors.error),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: entry.value,
                                        backgroundColor: Colors.black26,
                                        color: AppColors.accentYellow,
                                        minHeight: 4,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 24),
                            ],

                            // قسم الكورسات المحملة (كما هو)
                            if (groupedCourses.isNotEmpty) ...[
                              ...groupedCourses.entries.map((entry) => GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DownloadedSubjectsScreen(courseTitle: entry.key),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(
                                          color: AppColors.backgroundPrimary,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                        ),
                                        child: const Icon(LucideIcons.book, color: AppColors.accentOrange, size: 24),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.key.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 15, 
                                                fontWeight: FontWeight.bold, 
                                                color: AppColors.textPrimary, 
                                                letterSpacing: -0.5
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              AppLocalizations.of(context)!.filesDownloadedCountLabel(entry.value),
                                              style: TextStyle(
                                                fontSize: 9, 
                                                fontWeight: FontWeight.bold, 
                                                color: AppColors.textSecondary.withOpacity(0.7), 
                                                letterSpacing: 1.5
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: 20),
                                    ],
                                  ),
                                ),
                              )),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
   
  Widget _buildMetaTag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.9), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
