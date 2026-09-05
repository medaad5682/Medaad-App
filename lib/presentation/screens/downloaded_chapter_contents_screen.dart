import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // ✅ نحتاج Dio لفحص الاتصال بالسيرفر المحلي فقط
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/local_proxy.dart'; // ✅ استيراد خدمة البروكسي
import 'video_player_screen.dart';
import 'pdf_viewer_screen.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/video_screenshot_service.dart';
import 'video_screenshots_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
import 'package:Medaad/presentation/widgets/marquee_text.dart';

class DownloadedChapterContentsScreen extends StatefulWidget {
  final String courseTitle;
  final String subjectTitle;
  final String chapterTitle;

  const DownloadedChapterContentsScreen({
    super.key,
    required this.courseTitle,
    required this.subjectTitle,
    required this.chapterTitle,
  });

  @override
  State<DownloadedChapterContentsScreen> createState() =>
      _DownloadedChapterContentsScreenState();
}

class _DownloadedChapterContentsScreenState
    extends State<DownloadedChapterContentsScreen> {
  String activeTab = 'videos';

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log(
        "📂 Opened Downloaded Chapter: ${widget.chapterTitle} (Course: ${widget.courseTitle})");
  }

  // ===========================================================================
  // ✅ المنطق الجديد: التجهيز المسبق (Pre-warming)
  // ===========================================================================
  Future<void> _prepareAndPlayOfflineVideo(Map<dynamic, dynamic> item) async {
    // 1. إظهار ديالوج التحميل فوراً لمنع تفاعل المستخدم المتكرر
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: AppColors.accentYellow),
      ),
    );

    try {
      final String filePath = item['path'] ?? '';
      if (filePath.isEmpty) throw Exception("Video path is empty or null");

      FirebaseCrashlytics.instance
          .log("🚀 Pre-warming offline video: ${item['title']}");

      // 2. تشغيل السيرفر المحلي (البروكسي) وانتظار استعداده
      // لن يعيد التشغيل إذا كان يعمل بالفعل (بفضل تعديلات Keep-Alive)
      final proxy = LocalProxyService();
      await proxy.start();

      // 3. تجهيز الروابط (Video & Audio) باستخدام المنافذ الديناميكية
      // ✅ تعديل: استخدام videoPort بدلاً من port لتوجيه الفيديو للخيط المخصص
      String playUrl = proxy.getSignedUrl(filePath, isAudio: false);
      String? audioUrl;

      // محاولة العثور على ملف الصوت المرتبط
      if (item['audioPath'] != null) {
        final String audioPath = item['audioPath'];
        final File audioFile = File(audioPath);
        if (await audioFile.exists()) {
          // ✅ تعديل: استخدام audioPort بدلاً من port لتوجيه الصوت للخيط المعزول
          audioUrl = proxy.getSignedUrl(audioPath, isAudio: true);
          FirebaseCrashlytics.instance.log(
              "✅ Audio found and prepared on dedicated port: ${proxy.audioPort}");
        }
      }

      // 4. (خطوة أمان) إجراء "Ping" سريع جداً للتأكد أن البروكسي يرد
      try {
        final dio = Dio(); // استخدام نسخة مستقلة للاتصال المحلي
        // Timeout قصير جداً (500ms) لأننا نتصل محلياً
        await dio.head(playUrl).timeout(const Duration(milliseconds: 500));
        FirebaseCrashlytics.instance.log("✅ Proxy Ping Success");
      } catch (e) {
        FirebaseCrashlytics.instance
            .log("⚠️ Proxy Ping Warning: $e (Proceeding anyway)");
      }

      // 5. إغلاق ديالوج التحميل
      if (mounted) Navigator.pop(context);

      // 6. الانتقال للمشغل بالروابط الجاهزة
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              // نمرر رابط الفيديو الجاهز
              streams: {"Offline": playUrl},
              title: item['title'] ?? AppLocalizations.of(context)!.offlineVideoFallbackTitle,

              // ✅✅ هام جداً: نمرر رابط الصوت الجاهز هنا
              preReadyAudioUrl: audioUrl,

              // ✅ [SCREENSHOT FEATURE] نمرر lessonId (نفس المعرّف المخزَّن
              // في downloads_box كـ 'id') حتى تُربط أي لقطة فيديو تُلتقط
              // أثناء التشغيل الأوفلاين بنفس الدرس — فتظهر في معرض هذا
              // الفصل بغض النظر عن كون المشاهدة كانت أونلاين أو أوفلاين.
              lessonId: item['id']?.toString(),
            ),
          ),
        );
      }
    } catch (e, stack) {
      // في حال حدوث خطأ، نغلق التحميل ونظهر رسالة
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Offline Preparation Failed');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.errorPreparingVideoPlayback),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  // --- تشغيل PDF أوفلاين ---
  void _openOfflinePdf(String id, String title) {
    try {
      FirebaseCrashlytics.instance
          .log("📄 User requested offline PDF: $title (ID: $id)");
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(pdfId: id, title: title),
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Failed to open offline PDF');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.errorOpeningPdf),
            backgroundColor: AppColors.error),
      );
    }
  }

  // --- حذف الملف ---
  Future<void> _deleteFile(String key) async {
    try {
      var box = await StorageService.openBox('downloads_box');
      if (box.containsKey(key)) {
        await box.delete(key);
        FirebaseCrashlytics.instance.log("✅ File deleted: $key");
      }
      // التحديث يتم تلقائياً عبر ValueListenableBuilder
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.fileRemoved),
            backgroundColor: AppColors.accentOrange));
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Failed to delete file');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToDeleteFile),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: Hive.box('downloads_box').listenable(),
        builder: (context, Box box, _) {
          List<Map<String, dynamic>> videoItems = [];
          List<Map<String, dynamic>> pdfItems = [];

          try {
            for (var key in box.keys) {
              final item = box.get(key);
              if (item['course'] == widget.courseTitle &&
                  item['subject'] == widget.subjectTitle &&
                  item['chapter'] == widget.chapterTitle) {
                final itemMap = Map<String, dynamic>.from(item);
                itemMap['key'] = key;

                if (item['type'] == 'pdf') {
                  pdfItems.add(itemMap);
                } else {
                  videoItems.add(itemMap);
                }
              }
            }
          } catch (e, stack) {
            FirebaseCrashlytics.instance
                .recordError(e, stack, reason: 'Error parsing Hive data');
          }

          // ✅ [SCREENSHOT FEATURE] معرّفات الدروس (نفس lessonId المُمرَّر
          // لـ VideoPlayerScreen عند التشغيل) الخاصة بفيديوهات هذا الفصل
          // فقط — تُستخدم لتصفية معرض اللقطات ليعرض لقطات هذا الفصل حصراً.
          final Set<String> chapterLessonIds = videoItems
              .map((item) => item['id']?.toString())
              .whereType<String>()
              .toSet();

          return Scaffold(
            backgroundColor: AppColors.backgroundPrimary,
            body: SafeArea(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    color: AppColors.backgroundPrimary.withOpacity(0.95),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft,
                              color: AppColors.accentYellow, size: 24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MarqueeText(
                                widget.chapterTitle.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${widget.courseTitle} > ${widget.subjectTitle}",
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary
                                        .withOpacity(0.7)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // ✅ [SCREENSHOT FEATURE] فتح معرض لقطات الفيديو
                        // الخاصة بهذا الفصل (مصفّاة عبر lessonId).
                        IconButton(
                          tooltip: AppLocalizations.of(context)!
                              .videoScreenshotsTooltip,
                          icon: Icon(LucideIcons.image,
                              color: AppColors.accentYellow, size: 22),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VideoScreenshotsScreen(
                                  title: widget.chapterTitle,
                                  lessonIds: chapterLessonIds,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Tab Switcher
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Row(
                        children: [
                          _buildTab(AppLocalizations.of(context)!.videosTabWithCount(videoItems.length), 'videos'),
                          _buildTab(AppLocalizations.of(context)!.pdfsTabWithCount(pdfItems.length), 'pdfs'),
                        ],
                      ),
                    ),
                  ),

                  // List
                  Expanded(
                    child: activeTab == 'videos'
                        ? _buildFileList(videoItems, LucideIcons.play)
                        : _buildFileList(pdfItems, LucideIcons.fileText),
                  ),
                ],
              ),
            ),
          );
        });
  }

  Widget _buildTab(String title, String key) {
    final isActive = activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => activeTab = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.backgroundPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: isActive
                ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                : [],
          ),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color:
                  isActive ? AppColors.accentYellow : AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(List<Map<String, dynamic>> items, IconData icon) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                activeTab == 'videos'
                    ? LucideIcons.monitorPlay
                    : LucideIcons.fileSearch,
                size: 48,
                color: AppColors.textSecondary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              activeTab == 'videos'
                  ? AppLocalizations.of(context)!.noVideosDownloaded
                  : AppLocalizations.of(context)!.noPdfsDownloaded,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final key = item['key'];

        final sizeBytes = item['size'] ?? 0;
        final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
        final duration = item['duration'] ?? "--:--";
        final quality =
            activeTab == 'videos' ? (item['quality'] ?? "SD") : null;

        return GestureDetector(
          onTap: () {
            if (activeTab == 'videos') {
              // ✅ استدعاء الدالة الجديدة التي تقوم بالتحضير
              _prepareAndPlayOfflineVideo(item);
            } else {
              // ✅ التعديل هنا: تمرير الـ ID الأصلي فقط بدلاً من المفتاح الكامل
              // هذا لأن شاشة PdfViewerScreen تضيف البادئة 'pdf_' تلقائياً
              _openOfflinePdf(item['id'].toString(),
                  item['title'] ?? AppLocalizations.of(context)!.documentFallbackTitle);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon,
                          color: activeTab == 'videos'
                              ? AppColors.accentOrange
                              : AppColors.accentYellow,
                          size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item['title'].toString(),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            height: 1.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteFile(key.toString()),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.transparent,
                        child: const Icon(LucideIcons.trash2,
                            size: 18, color: AppColors.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildMetaTag(LucideIcons.hardDrive, AppLocalizations.of(context)!.sizeInMb(sizeMB)),
                    const SizedBox(width: 16),
                    if (activeTab == 'videos') ...[
                      _buildMetaTag(LucideIcons.clock, duration),
                      const SizedBox(width: 16),
                      if (quality != null)
                        _buildMetaTag(LucideIcons.monitor, quality),
                    ] else ...[
                      _buildMetaTag(LucideIcons.fileText, "PDF"),
                    ]
                  ],
                ),
              ],
            ),
          ),
        );
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
          style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withOpacity(0.9),
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
