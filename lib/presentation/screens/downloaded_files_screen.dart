import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/local_proxy.dart';
import '../../core/services/download_manager.dart'; 
import 'downloaded_subjects_screen.dart';
import 'video_screenshots_screen.dart';
import '../../core/services/storage_service.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
// أو المسار المناسب حسب مكان الملف

class DownloadedFilesScreen extends StatefulWidget {
  const DownloadedFilesScreen({super.key});

  @override
  State<DownloadedFilesScreen> createState() => _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends State<DownloadedFilesScreen> {
  final LocalProxyService _proxy = LocalProxyService();

  // 📦 معرّفات مجلدات الباقات المفتوحة حالياً (أكورديون) — بنفس فكرة شاشة
  // المكتبة: الضغط على مجلد باقة يفتح/يطوي قائمة كورساتها المحمّلة في نفس
  // المكان، بدون أي تنقّل لشاشة جديدة.
  final Set<String> _expandedPackageIds = {};

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
                  
                  // ✅ [SCREENSHOT FEATURE] فتح معرض كل لقطات الفيديو
                  // المحفوظة على الجهاز (بدون تصفية حسب فصل/تنزيل معيّن) —
                  // موضوعة هنا في شاشة "التنزيلات" الرئيسية بدل شاشة محتوى
                  // كل فصل على حدة، حتى تُتاح دائماً بغض النظر عن كون
                  // الفيديو الذي أُخذت منه اللقطة مُنزَّلاً أصلاً أم لا.
                  Row(
                    children: [
                      // ✅ [SCREENSHOT FEATURE] لقطات الفيديو متاحة على أندرويد
                      // فقط (طابق شرط زر الالتقاط نفسه في
                      // native_video_player_screen.dart)، لذا أيقونة المعرض
                      // تظهر على أندرويد فقط.
                      if (Platform.isAndroid) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VideoScreenshotsScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.05)),
                              boxShadow: const [
                                BoxShadow(color: Colors.black12, blurRadius: 4)
                              ],
                            ),
                            child: Icon(LucideIcons.image,
                                color: AppColors.accentYellow, size: 22),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],

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
                ],
              ),
            ),

            // ✅ Warning banner shown only while a download is actively in
            // progress — closing the app or backgrounding it can interrupt
            // the connection mid-chunk, so users are told up front instead
            // of finding out later from a stalled/failed download.
            ValueListenableBuilder<Map<String, double>>(
              valueListenable: DownloadManager.downloadingProgress,
              builder: (context, progressMap, _) {
                if (progressMap.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accentYellow.withOpacity(0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.alertCircle,
                            color: AppColors.accentYellow, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!
                                .keepAppOpenDuringDownloadWarning,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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

                  // 📦 نفس منطق تجميع الباقات في صفحة المكتبة: إن كان عنوان
                  // الكورس المُحمَّل تابعاً لباقة (أو أكثر من باقة) يملكها
                  // الطالب، يظهر داخل مجلد كل باقة منها. والكورس الواحد
                  // التابع لباقتين يظهر مرتين (مرة تحت كل باقة).
                  final Map<String, String> packageTitles = {}; // id -> title
                  final Map<String, List<String>> packageCourseTitles = {};
                  final Set<String> coursesInAnyPackage = {};

                  for (var libItem in AppState().myLibrary) {
                    if (libItem['type'] == 'package' &&
                        libItem['courses'] is List) {
                      final String pkgId = libItem['id'].toString();
                      final String pkgTitle =
                          libItem['title']?.toString() ?? '';
                      for (var course in libItem['courses']) {
                        if (course is! Map || course['title'] == null) {
                          continue;
                        }
                        final String courseTitle = course['title'].toString();
                        // لا نعرض إلا الكورسات التي لها تنزيلات فعلية
                        if (!groupedCourses.containsKey(courseTitle)) continue;

                        packageTitles[pkgId] = pkgTitle;
                        final list = packageCourseTitles.putIfAbsent(
                            pkgId, () => <String>[]);
                        if (!list.contains(courseTitle)) list.add(courseTitle);
                        coursesInAnyPackage.add(courseTitle);
                      }
                    }
                  }

                  // إجمالي الملفات المحمّلة داخل كل باقة
                  final Map<String, int> groupedPackages = {};
                  packageCourseTitles.forEach((pkgId, titles) {
                    groupedPackages[pkgId] = titles.fold<int>(
                        0, (sum, t) => sum + (groupedCourses[t] ?? 0));
                  });

                  final Map<String, int> ungroupedCourses = {
                    for (final e in groupedCourses.entries)
                      if (!coursesInAnyPackage.contains(e.key)) e.key: e.value
                  };

                  return ValueListenableBuilder<Map<String, double>>(
                    valueListenable: DownloadManager.downloadingProgress,
                    builder: (context, progressMap, child) {
                      // ✅ [MOVED] Paused/interrupted downloads (connection
                      // dropped, auto-retries exhausted, etc.) used to only
                      // surface a "Resume" button back on the chapter
                      // screen. They now show here instead, right next to
                      // the active-download progress bars, driven by the
                      // same pending_downloads_box the manager already
                      // maintains. A pending id that's also actively
                      // downloading (progressMap) is excluded here since
                      // it's already shown in the "active" section above.
                      return ValueListenableBuilder(
                        valueListenable:
                            Hive.box('pending_downloads_box').listenable(),
                        builder: (context, Box pendingBox, __) {
                      final List<MapEntry<String, dynamic>> pausedEntries =
                          pendingBox.keys
                              .cast<String>()
                              .where((id) => !progressMap.containsKey(id))
                              .map((id) => MapEntry(id, pendingBox.get(id)))
                              .toList();

                      if (groupedCourses.isEmpty &&
                          progressMap.isEmpty &&
                          pausedEntries.isEmpty) {
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
                                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 12),
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

                                              // ✅ زر الإيقاف المؤقت (Pause)
                                              GestureDetector(
                                                onTap: () {
                                                  DownloadManager().pauseDownload(id);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.textSecondary.withOpacity(0.15),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(LucideIcons.pause, size: 14, color: AppColors.textSecondary),
                                                ),
                                              ),
                                              const SizedBox(width: 8),

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

                            // ✅ [MOVED] قسم التحميلات المتوقفة - يحتوي على
                            // زر الاستئناف الذي كان سابقاً في شاشة الفصل
                            if (pausedEntries.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 12),
                                child: Text(
                                  AppLocalizations.of(context)!.pausedDownloadsLabel,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                                ),
                              ),
                              ...pausedEntries.map((entry) {
                                final id = entry.key;
                                final Map data = entry.value is Map
                                    ? Map.from(entry.value as Map)
                                    : {};
                                final String title = (data['videoTitle'] ??
                                        AppLocalizations.of(context)!.downloadingItemPlaceholder)
                                    .toString();
                                final bool isPdf = data['isPdf'] == true;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.backgroundPrimary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isPdf ? LucideIcons.fileText : LucideIcons.pause,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              AppLocalizations.of(context)!.downloadPausedStatusLabel,
                                              style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // ✅ زر الاستئناف - انتقل هنا من شاشة الفصل
                                      GestureDetector(
                                        onTap: () => _resumeDownload(id, title),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: AppColors.accentYellow,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.play, size: 12, color: AppColors.backgroundPrimary),
                                              const SizedBox(width: 6),
                                              Text(
                                                AppLocalizations.of(context)!.resumeDownloadAction,
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.backgroundPrimary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 24),
                            ],

                            // 📦 قسم مجلدات الباقات (كورسات محمّلة تابعة لنفس الباقة)
                            // أكورديون: الضغط على المجلد يفتح/يطوي كورساته
                            // مباشرة أسفله في نفس القائمة (بدون شاشة جديدة).
                            if (groupedPackages.isNotEmpty) ...[
                              ...groupedPackages.entries.expand((entry) {
                                final packageId = entry.key;
                                final packageTitle =
                                    packageTitles[packageId] ?? '';
                                final isExpanded =
                                    _expandedPackageIds.contains(packageId);
                                final titlesInPackage = List<String>.from(
                                    packageCourseTitles[packageId] ?? []);

                                return [
                                  _buildPackageFolderCard(
                                    context,
                                    packageId: packageId,
                                    title: packageTitle,
                                    fileCount: entry.value,
                                    isExpanded: isExpanded,
                                  ),
                                  // كورسات الباقة تظهر هنا مباشرة عند الفتح فقط،
                                  // كصف واحد بخط شجرة متصل يجمعها كلها معاً
                                  // (بدل خط منفصل لكل بطاقة).
                                  if (isExpanded)
                                    _buildNestedDownloadedCoursesGroup(
                                      context,
                                      titlesInPackage,
                                      groupedCourses,
                                    ),
                                ];
                              }),
                              const SizedBox(height: 12),
                            ],

                            // قسم الكورسات المحملة (كما هو، فيما عدا ما انضم منها لمجلد باقة أعلاه)
                            if (ungroupedCourses.isNotEmpty) ...[
                              ...ungroupedCourses.entries.map((entry) =>
                                  _buildDownloadedCourseCard(
                                      context, entry.key, entry.value)),
                            ],
                          ],
                        ),
                      );
                        },
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

  /// ✅ [MOVED] Resumes a previously started (but interrupted) download from
  /// this screen — same lessonId, all other metadata (quality, course,
  /// subject/chapter placement, resolved URL) is read back from
  /// `pending_downloads_box` inside DownloadManager.resumeDownload() itself,
  /// so nothing else needs to be passed in here.
  void _resumeDownload(String lessonId, String title) {
    FirebaseCrashlytics.instance.log("▶️ Resuming download from Downloads screen: $title");
    DownloadManager().resumeDownload(
      lessonId,
      onProgress: (p) {},
      onComplete: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.downloadCompletedMessage),
              backgroundColor: AppColors.success));
        }
      },
      onError: (e) {
        debugPrint("Resume failed for $title: $e");
      },
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

  // 📦 بطاقة مجلد الباقة — نسخة طبق الأصل من بطاقة المكتبة
  // (my_courses_screen.dart → _buildPackageFolderCard): إطار متدرج +
  // أيقونة صندوق مكدّسة + شارة "PACKAGE"، مع اختلاف واحد فقط: السطر
  // الفرعي يعرض عدد الملفات المحمّلة بدل عدد الكورسات.
  Widget _buildPackageFolderCard(
    BuildContext context, {
    required String packageId,
    required String title,
    required int fileCount,
    required bool isExpanded,
  }) {
    final bool isArabic = AppState.isArabic;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedPackageIds.remove(packageId);
          } else {
            _expandedPackageIds.add(packageId);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accentYellow.withOpacity(0.9),
              AppColors.accentOrange.withOpacity(0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentOrange.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    Positioned(
                      left: 4,
                      top: 6,
                      child: Icon(LucideIcons.layers,
                          size: 22,
                          color: AppColors.accentYellow.withOpacity(0.35)),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.accentYellow.withOpacity(0.4)),
                        ),
                        child: Icon(LucideIcons.package,
                            color: AppColors.accentYellow, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isArabic ? 'باقة' : 'PACKAGE',
                        style: TextStyle(
                          color: AppColors.accentYellow,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!
                          .filesDownloadedCountLabel(fileCount),
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: DirectionalFlip(
                  child: Icon(LucideIcons.chevronRight,
                      color: AppColors.textSecondary.withOpacity(0.6),
                      size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🌳 صف كورسات باقة مفتوحة: خط شجرة رأسي واحد متصل يمتد على طول كل
  // الكورسات المتفرّعة منه معاً (بدل خط منفصل لكل بطاقة)، بنفس أسلوب
  // شاشة المكتبة.
  Widget _buildNestedDownloadedCoursesGroup(BuildContext context,
      List<String> courseTitles, Map<String, int> fileCounts) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14),
              child: Container(
                width: 2,
                color: AppColors.accentYellow.withOpacity(0.25),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: courseTitles
                    .map((courseTitle) => _buildDownloadedCourseCard(
                          context,
                          courseTitle,
                          fileCounts[courseTitle] ?? 0,
                          nested: true,
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بطاقة كورس محمّل عادية — تُستخدم لكورس منفرد في القائمة الرئيسية، أو
  // لكورس ظاهر تحت مجلد باقة مفتوح عند nested=true (بنفس فتح
  // DownloadedSubjectsScreen بالضبط، فقط بحجم أصغر — ارتفاع أقل — ليبدو
  // بصرياً كعنصر تابع للمجلد أعلاه. خط الشجرة يُرسم مرة واحدة لكل
  // الكورسات معاً من _buildNestedDownloadedCoursesGroup، وليس هنا.
  Widget _buildDownloadedCourseCard(
      BuildContext context, String courseTitle, int fileCount,
      {bool nested = false}) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadedSubjectsScreen(courseTitle: courseTitle),
        ),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: nested ? 10 : 12),
        padding: EdgeInsets.all(nested ? 12 : 20),
        decoration: BoxDecoration(
          color: nested
              ? AppColors.backgroundPrimary
              : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(nested ? 14 : 20),
          // ☀️ نفس حد بطاقة الكورس التابع لباقة في المكتبة (واضح في الفاتح،
          // ونفس الحد القديم في الداكن).
          border: Border.all(
            color: nested
                ? AppColors.nestedCardBorder
                : Colors.white.withOpacity(0.05),
            width: nested && !AppState.isDark ? 1.2 : 1.0,
          ),
          boxShadow: nested
              ? null
              : const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            Container(
              width: nested ? 34 : 48,
              height: nested ? 34 : 48,
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(nested ? 10 : 12),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: nested ? 4 : 2)],
              ),
              child: Icon(LucideIcons.book, color: AppColors.accentOrange, size: nested ? 16 : 24),
            ),
            SizedBox(width: nested ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    courseTitle.toUpperCase(),
                    style: TextStyle(
                      fontSize: nested ? 12 : 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!nested) ...[
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.filesDownloadedCountLabel(fileCount),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary.withOpacity(0.7),
                        letterSpacing: 1.5
                      ),
                    ),
                  ],
                ],
              ),
            ),
            DirectionalFlip(child: Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: nested ? 16 : 20)),
          ],
        ),
      ),
    );
  }
}
