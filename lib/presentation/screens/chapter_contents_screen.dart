import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/download_manager.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/services/teacher_service.dart';
import 'video_player_screen.dart';
import 'youtube_player_screen.dart';
import 'pdf_viewer_screen.dart';
import 'teacher/manage_content_screen.dart';
import '../../core/constants/api_constants.dart';
import '../../data/models/player_settings_model.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class ChapterContentsScreen extends StatefulWidget {
  final Map<String, dynamic> chapter;
  final String courseTitle;
  final String subjectTitle;
  final String subjectId;
  final Map<String, dynamic>? playerSettings;

  const ChapterContentsScreen({
    super.key,
    required this.chapter,
    required this.courseTitle,
    required this.subjectTitle,
    required this.subjectId,
    this.playerSettings,
  });

  @override
  State<ChapterContentsScreen> createState() => _ChapterContentsScreenState();
}

class _ChapterContentsScreenState extends State<ChapterContentsScreen> {
  String activeTab = 'videos';
  final String _baseUrl = ApiConstants.baseUrl;
  final TeacherService _teacherService = TeacherService();
  bool _isTeacher = false;
  late Map<String, dynamic> _currentChapter;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapter;
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });

      if (_isTeacher) {
        _refreshChapterData();
      }
    }
  }

  Future<void> _refreshChapterData() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/secure/get-subject-content',
        queryParameters: {'subjectId': widget.subjectId},
      );

      if (mounted && res.statusCode == 200) {
        final chapters = res.data['chapters'] as List;
        final updatedChapter = chapters.firstWhere(
          (c) => c['id'].toString() == _currentChapter['id'].toString(),
          orElse: () => _currentChapter,
        );

        setState(() {
          _currentChapter = Map<String, dynamic>.from(updatedChapter);
        });
      }
    } catch (e) {
      FirebaseCrashlytics.instance
          .recordError(e, StackTrace.current, reason: 'Refresh Chapter Failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleReturnData(dynamic result) {
    if (result == true) {
      _refreshChapterData();
    }
  }

  // ---------------------------------------------------------------------------
  // 🟢 دوال مساعدة لفك الإعدادات وتطبيق الشروط (Players & Downloads)
  // ---------------------------------------------------------------------------

  bool _isVideoDownloadEnabled() {
    final settings = PlayerSettings.fromJson(widget.playerSettings);
    return settings.downloads.videoEnabled;
  }

  bool _isPdfDownloadEnabled() {
    final settings = PlayerSettings.fromJson(widget.playerSettings);
    return settings.downloads.pdfEnabled;
  }

  // ---------------------------------------------------------------------------
  // 🟢 دوال مساعدة لحساب الحجم وتنسيقه
  // ---------------------------------------------------------------------------

  int _getFileSizeFromUrl(String? url) {
    if (url == null) return 0;
    try {
      final uri = Uri.parse(url);
      final clen = uri.queryParameters['clen'];
      return int.tryParse(clen ?? '0') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return ""; // إرجاع نص فارغ تماماً بدلاً من Unknown Size
    
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  // ===========================================================================
  // 1. منطق المشاهدة (Watch Logic) واختيار المشغل
  // ===========================================================================

  void _showPlayerSelectionDialog(Map<String, dynamic> video) {
    final bool hasYoutubeId = video['hasId'] == true || 
        (video['youtube_video_id'] != null && video['youtube_video_id'].toString().isNotEmpty);
    
    final settings = PlayerSettings.fromJson(widget.playerSettings);
    final players = settings.getSortedEnabledPlayers(hasYoutubeId);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.selectPlayerTitle,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 24),
              if (players.isEmpty)
                 Padding(
                   padding: const EdgeInsets.all(16.0),
                   child: Text(AppLocalizations.of(context)!.noActivePlayersAvailable, style: const TextStyle(color: Colors.white54)),
                 ),
              ...players.map((player) {
                IconData icon = LucideIcons.playCircle;
                if (player.id == 'player_1') icon = LucideIcons.rocket;
                if (player.id == 'player_2') icon = LucideIcons.server;
                if (player.id == 'player_3') icon = LucideIcons.playSquare; 

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildOptionTile(
                    icon: icon,
                    title: player.name,
                    subtitle: player.description,
                    onTap: () {
                      Navigator.pop(context);
                      if (player.id == 'player_1') {
                        _fetchAndPlayWithExplode(video);
                      } else if (player.id == 'player_2') {
                        _fetchAndPlayVideo(video, useYoutube: false);
                      } else if (player.id == 'player_3') {
                        _fetchAndPlayVideo(video, useYoutube: true);
                      }
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchAndPlayVideo(Map<String, dynamic> video, {required bool useYoutube}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': video['id'].toString()},
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(minutes: 3),
        ),
      );

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = res.data;
        final String videoTitle = data['db_video_title'] ?? video['title'];

        if (useYoutube) {
          String? youtubeId = data['youtube_video_id'];
          if (youtubeId != null && youtubeId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => YoutubePlayerScreen(videoId: youtubeId, title: videoTitle),
              ),
            );
          } else {
            FirebaseCrashlytics.instance.log("YouTube ID missing for lesson: ${video['id']}");
            _showErrorSnackBar("Not a YouTube video or ID missing.");
          }
        } else {
          Map<String, String> qualities = {};
          if (data['availableQualities'] != null) {
            for (var q in data['availableQualities']) {
              if (q['url'] != null) {
                qualities["${q['quality']}p"] = q['url'];
              }
            }
          }
          if (qualities.isEmpty && data['url'] != null) {
            qualities["Auto"] = data['url'];
          }

          if (qualities.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(streams: qualities, title: videoTitle),
              ),
            );
          } else {
            FirebaseCrashlytics.instance.log("No streamable URLs found for lesson: ${video['id']}");
            _showErrorSnackBar("No playable stream found.");
          }
        }
      } else {
        _showErrorSnackBar(res.data['message'] ?? "Access Denied");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context);
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Play Video Exception');
      _showErrorSnackBar("Connection Error: Please check internet");
    }
  }

  Future<void> _fetchAndPlayWithExplode(Map<String, dynamic> video) async {
    FirebaseCrashlytics.instance.log("🚀 Starting Direct Play (Explode) for: ${video['title']}");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/secure/get-stream-proxy',
        queryParameters: {'lessonId': video['id'].toString()},
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(minutes: 3),
        ),
      );

      if (mounted) Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = res.data;
        final String videoTitle = data['db_video_title'] ?? video['title'];
        final List<dynamic> rawQualities = data['availableQualities'] ?? [];

        if (rawQualities.isNotEmpty) {
          Map<String, String> processedQualities = {};

          String? bestAudioUrl;
          try {
            final audioObj = rawQualities.firstWhere(
                (q) => q['type'] == 'audio_only',
                orElse: () => null);
            bestAudioUrl = audioObj?['url'];
          } catch (_) {}

          for (var item in rawQualities) {
            String url = item['url'];
            String qualityKey = "${item['quality']}p";
            String type = item['type'];

            if (type == 'audio_only') continue;

            if (type == 'video_only' && bestAudioUrl != null) {
              processedQualities[qualityKey] = "$url|$bestAudioUrl";
            } else {
              processedQualities[qualityKey] = url;
            }
          }

          if (processedQualities.isNotEmpty) {
            FirebaseCrashlytics.instance.log("✅ Streams processed. Launching player.");
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  streams: processedQualities,
                  title: videoTitle,
                ),
              ),
            );
          } else {
            FirebaseCrashlytics.instance.log("⚠️ No valid video qualities processed.");
            _showErrorSnackBar("No playable streams found.");
          }
        } else {
          _showErrorSnackBar("Video streams unavailable.");
        }
      } else {
        FirebaseCrashlytics.instance.log("❌ Server Error: ${res.statusCode}");
        _showErrorSnackBar("Server Error: ${res.statusCode}");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context);
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "Direct Stream Error");
      _showErrorSnackBar("Connection Error or Timeout.");
    }
  }

  // ===========================================================================
  // 2. منطق التحميل (Download Logic) - مع دعم الـ Fallback
  // ===========================================================================

  Future<void> _prepareVideoDownload(String videoId, String videoTitle, String duration) async {
    FirebaseCrashlytics.instance.log("⬇️ Fetching download info for: $videoTitle");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
    );

    try {
      // 1. المحاولة الأولى عبر السيرفر الأساسي (get-stream-proxy)
      try {
        final res = await ApiClient.instance.get(
          '$_baseUrl/api/secure/get-stream-proxy',
          queryParameters: {'lessonId': videoId},
          options: Options(
            receiveTimeout: const Duration(minutes: 3),
            sendTimeout: const Duration(minutes: 3),
          ),
        );

        if (res.statusCode == 200) {
          final data = res.data;
          List<dynamic> rawQualities = data['availableQualities'] ?? [];
          var videoOptions = rawQualities.where((q) => q['type'] != 'audio_only').toList();

          if (videoOptions.isNotEmpty) {
            String? bestAudioUrl;
            int audioSize = 0; 
            try {
              final audioObj = rawQualities.firstWhere(
                  (q) => q['type'] == 'audio_only',
                  orElse: () => null);
              if (audioObj != null) {
                bestAudioUrl = audioObj['url'];
                audioSize = _getFileSizeFromUrl(bestAudioUrl);
              }
            } catch (_) {}

            if (mounted) Navigator.pop(context); // إغلاق نافذة التحميل
            _showQualitySelectionDialog(videoId, videoTitle, videoOptions, duration, bestAudioUrl, audioSize);
            return; // الخروج من الدالة بنجاح
          }
        }
      } catch (primaryError) {
        FirebaseCrashlytics.instance.log("⚠️ Primary proxy failed for download. Proceeding to fallback.");
      }

      // 2. المحاولة الاحتياطية (Fallback) عبر سيرفر المانيفست (get-video-id)
      FirebaseCrashlytics.instance.log("🔄 Trying Fallback Manifest API for download...");
      final fallbackRes = await ApiClient.instance.get(
        '$_baseUrl/api/secure/get-video-id',
        queryParameters: {'lessonId': videoId},
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(minutes: 3),
        ),
      );

      if (mounted) Navigator.pop(context); // إغلاق نافذة التحميل بعد انتهاء المحاولات

      if (fallbackRes.statusCode == 200) {
        final data = fallbackRes.data;
        List<dynamic> rawQualities = data['availableQualities'] ?? [];

        if (rawQualities.isNotEmpty) {
          _showQualitySelectionDialog(videoId, videoTitle, rawQualities, duration, null, 0);
        } else if (data['url'] != null) {
          _showQualitySelectionDialog(videoId, videoTitle, [
            {'quality': 'Auto', 'url': data['url'], 'type': 'video_audio'}
          ], duration, null, 0);
        } else {
          _showErrorSnackBar("No compatible video streams found.");
        }
      } else {
        _showErrorSnackBar("Server Error: ${fallbackRes.statusCode}");
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context); // إغلاق النافذة في حالة الفشل التام
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Both Download APIs Failed');
      _showErrorSnackBar("Failed to fetch download info. Please check internet.");
    }
  }

  void _showQualitySelectionDialog(
      String videoId,
      String title,
      List<dynamic> qualities,
      String duration,
      String? audioUrl,
      int audioSize) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.selectDownloadQualityTitle,
                style: const TextStyle(
                  color: Colors.black, 
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: qualities.map((q) {
                      int videoSize = _getFileSizeFromUrl(q['url']);
                      int totalSize = videoSize + audioSize;
                      String sizeText = _formatBytes(totalSize, 1);

                      return ListTile(
                        leading: const Icon(LucideIcons.download, color: Colors.black), 
                        title: Text(
                          "${q['quality']}p",
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold), 
                        ),
                        subtitle: sizeText.isNotEmpty
                            ? Text(
                                sizeText,
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              )
                            : null,
                        trailing: DirectionalFlip(child: Icon(LucideIcons.chevronRight, color: Colors.black54, size: 16)), 
                        onTap: () {
                          Navigator.pop(context);
                          String? targetAudio = (q['type'] == 'video_only') ? audioUrl : null;
                          _startVideoDownload(videoId, title, q['url'], targetAudio, "${q['quality']}p", duration);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startVideoDownload(String videoId, String videoTitle,
      String? downloadUrl, String? audioUrl, String quality, String duration) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.downloadStartedMessage)));
    FirebaseCrashlytics.instance.log("⬇️ Starting download: $videoTitle ($quality)");

    DownloadManager().startDownload(
      lessonId: videoId,
      videoTitle: videoTitle,
      subjectId: widget.subjectId,
      courseName: widget.courseTitle,
      subjectName: widget.subjectTitle,
      chapterName: _currentChapter['title'] ?? AppLocalizations.of(context)!.chapterFallbackTitle,
      downloadUrl: downloadUrl,
      audioUrl: audioUrl,
      quality: quality,
      duration: duration,
      onProgress: (p) {},
      onComplete: () {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.downloadCompletedMessage),
              backgroundColor: AppColors.success));
      },
      onError: (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.downloadFailedMessage),
              backgroundColor: AppColors.error));
      },
    );
  }

  void _startPdfDownload(String pdfId, String pdfTitle) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.pdfDownloadStartedMessage)));
    FirebaseCrashlytics.instance.log("⬇️ Starting PDF download: $pdfTitle");

    DownloadManager().startDownload(
      lessonId: pdfId,
      videoTitle: pdfTitle,
      subjectId: widget.subjectId,
      courseName: widget.courseTitle,
      subjectName: widget.subjectTitle,
      chapterName: _currentChapter['title'] ?? AppLocalizations.of(context)!.chapterFallbackTitle,
      isPdf: true,
      quality: "PDF",
      onProgress: (p) {},
      onComplete: () {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.pdfDownloadCompletedMessage),
              backgroundColor: AppColors.success));
      },
      onError: (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.downloadFailedMessage),
              backgroundColor: AppColors.error));
      },
    );
  }

  // ===========================================================================
  // UI Building Methods
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final videos = (_currentChapter['videos'] as List? ?? []).cast<Map<String, dynamic>>();
    final pdfs = (_currentChapter['pdfs'] as List? ?? []).cast<Map<String, dynamic>>();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _currentChapter);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                color: AppColors.backgroundPrimary.withOpacity(0.95),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context, _currentChapter);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundSecondary,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: AppColors.textSecondary
                                              .withOpacity(0.1)),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 4)
                                      ],
                                    ),
                                    child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft,
                                        color: AppColors.accentYellow,
                                        size: 20)),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Text(
                                          _currentChapter['title']
                                              .toString()
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                            letterSpacing: -0.5,
                                          ),
                                          maxLines: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${widget.courseTitle} > ${widget.subjectTitle}",
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accentYellow
                                              .withOpacity(0.8),
                                          letterSpacing: 1.0,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_isTeacher) ...[
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                ContentType type = activeTab == 'videos'
                                    ? ContentType.video
                                    : ContentType.pdf;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ManageContentScreen(
                                      contentType: type,
                                      parentId: _currentChapter['id']
                                          .toString(), 
                                    ),
                                  ),
                                ).then((val) =>
                                    _handleReturnData(val)); 
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.accentYellow.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(
                                      color: AppColors.accentYellow
                                          .withOpacity(0.5)),
                                ),
                                child: Icon(
                                    activeTab == 'videos'
                                        ? LucideIcons.video
                                        : LucideIcons.filePlus,
                                    color: AppColors.accentYellow,
                                    size: 22),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Tabs
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 8.0),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                              color: AppColors.textSecondary.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            _buildTab(AppLocalizations.of(context)!.videosTabLabel, 'videos'),
                            _buildTab(AppLocalizations.of(context)!.pdfsTabLabel, 'pdfs'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content List
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentYellow))
                    : activeTab == 'videos'
                        ? _buildVideosList(videos)
                        : _buildPdfsList(pdfs),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildVideosList(List<Map<String, dynamic>> videos) {
    if (videos.isEmpty)
      return _buildEmptyState(LucideIcons.monitorPlay, AppLocalizations.of(context)!.noVideoLessonsMessage);

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final String videoId = video['id'].toString();
        final String duration = video['duration']?.toString() ?? "--:--";
        // ✅ فيديوهات Bunny التي ما زالت "في انتظار المعالجة" أو "قيد المعالجة"
        // لا يمكن مشاهدتها أو تحميلها بعد — نخفي الزرين للمعلم في هذه الحالة
        // (فيديوهات يوتيوب جاهزة دائماً فور إضافتها، فلا تتأثر بهذا الشرط)
        final String? encodingStatus = video['encoding_status']?.toString();
        final bool isBunnyVideo = video['bunny_video_id'] != null;
        final bool isVideoNotReadyYet =
            _isTeacher && isBunnyVideo && encodingStatus != 'ready';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 2)
                        ],
                      ),
                      child: Icon(LucideIcons.play,
                          color: AppColors.accentOrange, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video['title'].toString().toUpperCase(),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context)!.videoLabel,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary.withOpacity(0.7)),
                              ),
                              if (duration != "--:--" && duration != "00:00" && duration.trim().isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                  child: Icon(LucideIcons.clock, 
                                      size: 10, color: AppColors.textSecondary.withOpacity(0.5)),
                                ),
                                Text(
                                  duration,
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accentYellow.withOpacity(0.9)),
                                ),
                              ]
                            ],
                          ),

                          // ✅ حالة معالجة الفيديو على Bunny Stream — تظهر للمعلم فقط
                          // (تماماً كما تظهر في لوحة تحكم الويب: في انتظار المعالجة /
                          // قيد المعالجة / جاهز) — تُقرأ من حقل encoding_status
                          if (_isTeacher && video['bunny_video_id'] != null) ...[
                            const SizedBox(height: 6),
                            _buildEncodingStatusBadge(videoId, video['encoding_status']?.toString()),
                          ],

                        ],
                      ),
                    ),

                    if (_isTeacher)
                      IconButton(
                        icon: Icon(LucideIcons.edit2,
                            size: 18, color: AppColors.accentYellow),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageContentScreen(
                                contentType: ContentType.video,
                                initialData: video,
                                parentId: _currentChapter['id'].toString(),
                              ),
                            ),
                          ).then(
                              (val) => _handleReturnData(val)); 
                        },
                      ),
                  ],
                ),
              ),
              Divider(
                  height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
              // ✅ بينما الفيديو "في انتظار المعالجة" أو "قيد المعالجة" على
              // Bunny Stream لا يمكن مشاهدته أو تحميله بعد — نخفي الزرين
              // ونعرض رسالة توضيحية بدلاً منهما (للمعلم فقط).
              if (isVideoNotReadyYet)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.videoProcessingNotice,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        AppLocalizations.of(context)!.watchNowButton,
                        AppColors.accentYellow,
                        () => _showPlayerSelectionDialog(video),
                      ),
                    ),
                    Container(
                        width: 1,
                        height: 48,
                        color: AppColors.textSecondary.withOpacity(0.1)),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: DownloadManager.downloadingProgress,
                        builder:
                            (context, Map<String, double> progresses, child) {
                          return ValueListenableBuilder(
                            valueListenable:
                                Hive.box('downloads_box').listenable(),
                            builder: (context, Box box, _) {
                              String storageKey = 'vid_$videoId';
                              bool isDownloaded = box.containsKey(storageKey);
                              bool isDownloading = progresses.containsKey(videoId);

                              String? sizeStr;
                              if (isDownloaded) {
                                final item = box.get(storageKey);
                                if (item != null) {
                                  int bytes = item['size'] ?? 0;
                                  sizeStr =
                                      "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
                                }
                              }

                              if (isDownloaded) {
                                return _buildStatusButton(
                                    "${AppLocalizations.of(context)!.savedLabel}${sizeStr != null ? ' ($sizeStr)' : ''}",
                                    AppColors.success,
                                    LucideIcons.checkCircle);
                              }
                              else if (isDownloading) {
                                return _buildStatusButton(AppLocalizations.of(context)!.processingLabel,
                                    AppColors.accentYellow, LucideIcons.loader);
                              } else {
                                // ✅ إخفاء زر التحميل بناءً على الإعدادات
                                if (!_isVideoDownloadEnabled()) {
                                  return _buildStatusButton(AppLocalizations.of(context)!.downloadDisabledLabel,
                                      AppColors.textSecondary, LucideIcons.lock);
                                }
                                return _buildActionButton(
                                    AppLocalizations.of(context)!.downloadButton,
                                    AppColors.textSecondary,
                                    () => _prepareVideoDownload(
                                        videoId, video['title'], duration));
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 🎬 شارة حالة معالجة الفيديو على Bunny Stream — مطابقة تماماً للوحة التحكم
  // (pages/admin/teacher/content.js STATUS_MAP): waiting / encoding / ready
  // ✅ قابلة للضغط لتحديث الحالة يدوياً طالما لم تصل بعد لـ "جاهز"
  // ===========================================================================
  final Set<String> _refreshingVideoIds = {};

  Future<void> _refreshSingleVideoStatus(String videoId) async {
    if (_refreshingVideoIds.contains(videoId)) return;
    setState(() => _refreshingVideoIds.add(videoId));
    try {
      final result = await _teacherService.getVideoStatus(videoId);
      final newStatus = result['encoding_status']?.toString();
      if (mounted && newStatus != null) {
        setState(() {
          final videos = (_currentChapter['videos'] as List?) ?? [];
          for (final v in videos) {
            if (v is Map && v['id'].toString() == videoId) {
              v['encoding_status'] = newStatus;
              if (result['duration'] != null) {
                v['duration'] = result['duration'];
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar(AppLocalizations.of(context)!.videoStatusRefreshFailed);
    } finally {
      if (mounted) setState(() => _refreshingVideoIds.remove(videoId));
    }
  }

  Widget _buildEncodingStatusBadge(String videoId, String? encodingStatus) {
    late String label;
    late Color color;
    late IconData icon;

    switch (encodingStatus) {
      case 'encoding':
        label = AppLocalizations.of(context)!.encodingStatusEncoding;
        color = AppColors.accentYellow;
        icon = LucideIcons.loader;
        break;
      case 'ready':
        label = AppLocalizations.of(context)!.encodingStatusReady;
        color = AppColors.success;
        icon = LucideIcons.checkCircle;
        break;
      case 'waiting':
      default:
        // أي قيمة غير معروفة (أو null) تُعامل كـ "waiting" تماماً كما في
        // لوحة التحكم على الويب (STATUS_MAP[v.encoding_status] || waiting)
        label = AppLocalizations.of(context)!.encodingStatusWaiting;
        color = AppColors.textSecondary;
        icon = LucideIcons.clock;
        break;
    }

    final bool isReady = encodingStatus == 'ready';
    final bool isRefreshing = _refreshingVideoIds.contains(videoId);

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRefreshing) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            ),
            const SizedBox(width: 5),
            Text(AppLocalizations.of(context)!.updatingLabel,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
          ] else ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
            if (!isReady) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.refreshCw, size: 10, color: color.withOpacity(0.7)),
            ],
          ],
        ],
      ),
    );

    if (isReady || isRefreshing) return badge;

    return GestureDetector(
      onTap: () => _refreshSingleVideoStatus(videoId),
      child: badge,
    );
  }

  Widget _buildPdfsList(List<Map<String, dynamic>> pdfs) {
    if (pdfs.isEmpty)
      return _buildEmptyState(LucideIcons.fileText, AppLocalizations.of(context)!.noPdfFilesMessage);

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: pdfs.length,
      itemBuilder: (context, index) {
        final pdf = pdfs[index];
        final String pdfId = pdf['id'].toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 2)
                        ],
                      ),
                      child: Icon(LucideIcons.fileText,
                          color: AppColors.accentYellow, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pdf['title'].toString().toUpperCase(),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(AppLocalizations.of(context)!.studyMaterialLabel,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary
                                      .withOpacity(0.7))),
                        ],
                      ),
                    ),

                    if (_isTeacher)
                      IconButton(
                        icon: Icon(LucideIcons.edit2,
                            size: 18, color: AppColors.accentYellow),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageContentScreen(
                                contentType: ContentType.pdf,
                                initialData: pdf,
                                parentId: _currentChapter['id'].toString(),
                              ),
                            ),
                          ).then(
                              (val) => _handleReturnData(val));
                        },
                      ),
                  ],
                ),
              ),
              Divider(
                  height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                        AppLocalizations.of(context)!.openFileButton, AppColors.accentYellow, () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PdfViewerScreen(
                                  pdfId: pdfId, title: pdf['title'])));
                    }),
                  ),
                  Container(
                      width: 1,
                      height: 48,
                      color: AppColors.textSecondary.withOpacity(0.1)),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: DownloadManager.downloadingProgress,
                      builder:
                          (context, Map<String, double> progresses, child) {
                        return ValueListenableBuilder(
                          valueListenable:
                              Hive.box('downloads_box').listenable(),
                          builder: (context, Box box, _) {
                            String storageKey = 'pdf_$pdfId';
                            bool isDownloaded = box.containsKey(storageKey);
                            bool isDownloading = progresses.containsKey(pdfId);

                            if (isDownloaded) {
                              return _buildStatusButton(AppLocalizations.of(context)!.savedLabel,
                                  AppColors.success, LucideIcons.checkCircle);
                            }
                            else if (isDownloading) {
                              return _buildStatusButton(AppLocalizations.of(context)!.processingLabel,
                                  AppColors.accentYellow, LucideIcons.loader);
                            }
                            else {
                              // ✅ التحقق من إعدادات زر تحميل الـ PDF
                              if (!_isPdfDownloadEnabled()) {
                                return _buildStatusButton(AppLocalizations.of(context)!.downloadDisabledLabel,
                                    AppColors.textSecondary, LucideIcons.lock);
                              }
                              return _buildActionButton(
                                  AppLocalizations.of(context)!.downloadButton,
                                  AppColors.textSecondary,
                                  () => _startPdfDownload(pdfId, pdf['title']));
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Widgets مساعدة ---

  Widget _buildOptionTile(
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accentYellow, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.5),
                          fontSize: 10)),
                ],
              ),
            ),
            DirectionalFlip(child: Icon(LucideIcons.chevronRight,
                color: AppColors.textSecondary.withOpacity(0.6), size: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: color)),
        ),
      ),
    );
  }

  Widget _buildStatusButton(String label, Color color, IconData icon) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(message.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: AppColors.textSecondary.withOpacity(0.5))),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error));
  }
}
