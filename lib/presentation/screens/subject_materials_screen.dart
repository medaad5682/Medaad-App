import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import 'chapter_contents_screen.dart';
import 'exam_view_screen.dart';
import 'exam_result_screen.dart';
import 'teacher/manage_content_screen.dart';
import 'teacher/create_exam_screen.dart';
import 'teacher/exam_stats_screen.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
import 'package:Medaad/presentation/widgets/marquee_text.dart';

class SubjectMaterialsScreen extends StatefulWidget {
  final String subjectId;
  final String subjectTitle;

  const SubjectMaterialsScreen({
    super.key,
    required this.subjectId,
    required this.subjectTitle,
  });

  @override
  State<SubjectMaterialsScreen> createState() => _SubjectMaterialsScreenState();
}

class _SubjectMaterialsScreenState extends State<SubjectMaterialsScreen> {
  String _activeTab = 'chapters'; // chapters | exams
  bool _loading = true;
  String? _error;
  // ⏳ [Feature B] سبب رفض الوصول عندما يرجعه get-subject-content صراحة:
  // 'expired' (كان مملوكاً وانتهت صلاحيته) أو 'not_owned' (لم يشترك أبداً)،
  // أو null إن كان الخطأ اتصال حقيقي وليس رفض وصول من السيرفر.
  String? _accessDenialReason;
  Map<String, dynamic>? _content;
  bool _isTeacher = false;
  // ✅ [جديد] أسماء المجلدات المطوية حالياً. المجلدات تكون مطوية (مغلقة)
  // بشكل افتراضي عند ظهورها لأول مرة — انظر _syncFolderDefaults.
  final Set<String> _collapsedFolders = {};
  // أسماء المجلدات التي سبق رصدها من قبل، لتفادي إعادة طي مجلد فتحه
  // المستخدم يدوياً كلما تم تحديث البيانات (بعد تعديل/إضافة فصل مثلاً).
  final Set<String> _knownFolderNames = {};

  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance
        .log("Opened Subject: ${widget.subjectTitle} (${widget.subjectId})");
    _checkUserRole();
    _fetchContent();
  }

  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
      });
    }
  }

  Future<void> _fetchContent() async {
    try {
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/secure/get-subject-content',
        queryParameters: {'subjectId': widget.subjectId},
      );

      if (mounted) {
        setState(() {
          _content = res.data;
          _loading = false;
          _error = null;
          _accessDenialReason = null;
          _syncFolderDefaults();
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Fetching Subject Content Failed');

      // ⏳ [Feature B] get-subject-content يُرجع 403 مع { reason: 'expired' |
      // 'not_owned' } عند رفض الوصول (راجع authHelper.js/checkUserAccess).
      // Dio يرمي استثناءً لأي رد غير 2xx، فنقرأ التفاصيل هنا بدل التعامل مع
      // كل رفض وصول كـ "فشل تحميل" عام لا يفرّق بين "انتهت صلاحيتك" و"لم
      // تشترك أصلاً".
      String? reason;
      String? serverMessage;
      if (e is DioException && e.response != null) {
        final data = e.response!.data;
        if (data is Map) {
          reason = data['reason']?.toString();
          serverMessage = (data['message'] ?? data['error'])?.toString();
        }
      }

      if (mounted) {
        setState(() {
          _accessDenialReason = reason;
          _error = reason == 'expired'
              ? (AppState.isArabic
                  ? 'انتهت صلاحية اشتراكك في هذه المادة'
                  : 'Your access to this subject has expired')
              : reason == 'not_owned'
                  ? (AppState.isArabic
                      ? 'لا تملك اشتراكاً في هذه المادة'
                      : 'You don\'t have access to this subject')
                  : (serverMessage ??
                      AppLocalizations.of(context)!.failedToLoadContent);
          _loading = false;
        });
      }
    }
  }

  // ✅ [جديد] عند ظهور مجلد جديد لأول مرة (لم يُرصد من قبل)، يُضاف إلى
  // قائمة المجلدات المطوية افتراضياً. المجلدات التي فتحها المستخدم يدوياً
  // من قبل (أُزيلت من _collapsedFolders) لا تتأثر بإعادة جلب البيانات.
  void _syncFolderDefaults() {
    final chapters = _content?['chapters'] as List? ?? [];
    for (final ch in chapters) {
      final String name = ((ch['folder_name'] as String?) ?? '').trim();
      if (name.isEmpty) continue;
      if (!_knownFolderNames.contains(name)) {
        _knownFolderNames.add(name);
        _collapsedFolders.add(name);
      }
    }
  }

  // ✅ [جديد] أسماء المجلدات المستخدمة بالفعل في هذه المادة (بدون تكرار)،
  // بترتيب أول ظهور، لعرضها كاقتراحات سريعة عند إضافة/تعديل فصل.
  List<String> _existingFolderNames() {
    final chapters = _content?['chapters'] as List? ?? [];
    final List<String> result = [];
    for (final ch in chapters) {
      final String name = ((ch['folder_name'] as String?) ?? '').trim();
      if (name.isNotEmpty && !result.contains(name)) {
        result.add(name);
      }
    }
    return result;
  }


  void _updateChapterList(dynamic result) {
    if (result == true) {
      _fetchContent();
      return;
    }

    if (result == null || _content == null) return;

    setState(() {
      List chapters = List.from(_content!['chapters'] ?? []);

      if (result is Map && result['deleted'] == true) {
        chapters
            .removeWhere((c) => c['id'].toString() == result['id'].toString());
      } else if (result is Map<String, dynamic>) {
        int index = chapters
            .indexWhere((c) => c['id'].toString() == result['id'].toString());
        if (index != -1) {
          chapters[index] = result;
        } else {
          chapters.add(result);
        }
      }
      _content!['chapters'] = chapters;
      _syncFolderDefaults();
    });
  }

  // ===========================================================================
  // 🟢 نظام الآراء المجهولة (Anonymous Feedback)
  // ===========================================================================

  void _showStudentFeedbackDialog(String chapterId) {
    final TextEditingController feedbackController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.backgroundSecondary,
            title: Text(AppLocalizations.of(context)!.studentFeedbackDialogTitle,
                style: TextStyle(color: AppColors.textPrimary)),
            content: TextField(
              controller: feedbackController,
              maxLines: 4,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.studentFeedbackHint,
                hintStyle:
                    TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.textSecondary.withOpacity(0.3))),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accentYellow)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.cancel,
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (feedbackController.text.trim().isEmpty) return;
                        setState(() => isSubmitting = true);

                        try {
                          final res = await ApiClient.instance.post(
                            '$_baseUrl/api/student/submit-feedback',
                            data: {
                              'chapter_id': chapterId,
                              'content': feedbackController.text.trim(),
                            },
                          );

                          if (res.statusCode == 200) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(AppLocalizations.of(context)!
                                        .studentFeedbackSuccessMessage),
                                    backgroundColor: AppColors.success));
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(AppLocalizations.of(context)!
                                      .studentFeedbackConnectionError),
                                  backgroundColor: AppColors.error));
                        } finally {
                          setState(() => isSubmitting = false);
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : Text(AppLocalizations.of(context)!.submitLabel,
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  void _showTeacherFeedbackDialog(String chapterId) {
    List<dynamic> feedbacks = [];
    int currentPage = 1;
    bool isInitialLoading = true;
    bool isFetchingMore = false;
    bool hasMoreData = true;
    bool isInit = true;

    final ScrollController scrollController = ScrollController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> fetchFeedbacks() async {
              try {
                final res = await ApiClient.instance.get(
                  '$_baseUrl/api/teacher/get-feedback',
                  queryParameters: {
                    'chapter_id': chapterId,
                    'page': currentPage,
                    'limit': 10,
                  },
                );

                if (res.statusCode == 200) {
                  List newData = res.data['data'];
                  setState(() {
                    feedbacks.addAll(newData);
                    hasMoreData = res.data['hasMore'] ?? false;
                    isInitialLoading = false;
                    isFetchingMore = false;
                  });
                }
              } catch (e) {
                setState(() {
                  isInitialLoading = false;
                  isFetchingMore = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.teacherFeedbackFetchFailed),
                    backgroundColor: AppColors.error));
              }
            }

            if (isInit) {
              isInit = false;
              fetchFeedbacks();

              scrollController.addListener(() {
                if (scrollController.position.pixels >=
                        scrollController.position.maxScrollExtent - 50 &&
                    !isFetchingMore &&
                    hasMoreData) {
                  setState(() {
                    isFetchingMore = true;
                    currentPage++;
                  });
                  fetchFeedbacks();
                }
              });
            }

            return AlertDialog(
              backgroundColor: AppColors.backgroundSecondary,
              title: Text(AppLocalizations.of(context)!.teacherFeedbackDialogTitle,
                  style: TextStyle(color: AppColors.textPrimary)),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.5,
                child: isInitialLoading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentYellow))
                    : feedbacks.isEmpty
                        ? Center(
                            child: Text(
                                AppLocalizations.of(context)!
                                    .teacherFeedbackEmptyState,
                                style:
                                    TextStyle(color: AppColors.textSecondary)))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount:
                                feedbacks.length + (isFetchingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == feedbacks.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16.0),
                                    child: CircularProgressIndicator(
                                        color: AppColors.accentYellow,
                                        strokeWidth: 2),
                                  ),
                                );
                              }

                              return Card(
                                color: AppColors.backgroundPrimary,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(LucideIcons.messageSquare,
                                          color: AppColors.accentYellow,
                                          size: 20),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          feedbacks[index]['content'],
                                          style: TextStyle(
                                              color: AppColors.textPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.close,
                      style: TextStyle(color: AppColors.accentYellow)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // واجهة المستخدم (UI)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow)));
    }
    if (_error != null) {
      final bool isArabic = AppState.isArabic;
      final bool isExpired = _accessDenialReason == 'expired';
      final bool isAccessDenial = _accessDenialReason != null;

      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          appBar: AppBar(
              backgroundColor: Colors.transparent,
              leading: BackButton(color: AppColors.accentYellow)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpired ? LucideIcons.clock : LucideIcons.shieldAlert,
                    size: 48,
                    color: isAccessDenial
                        ? AppColors.accentYellow
                        : AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error)),
                  // ⏳ [Feature B] عندما يكون سبب الرفض "انتهت الصلاحية" تحديداً،
                  // نعرض زراً يوجّه الطالب للعودة (لتجديد الاشتراك من المتجر)
                  // بدل تركه أمام رسالة رفض بلا أي إجراء ممكن.
                  if (isExpired) ...[
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isArabic ? 'تجديد الاشتراك' : 'Renew subscription',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ));
    }

    final chapters = _content!['chapters'] as List;
    final exams = _content!['exams'] as List;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.05)),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black12, blurRadius: 4)
                                  ],
                                ),
                                child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft,
                                    color: AppColors.accentYellow, size: 20)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      widget.subjectTitle.toUpperCase(),
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
                                    AppLocalizations.of(context)!
                                        .subjectContentsLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accentYellow,
                                      letterSpacing: 2.0,
                                    ),
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
                            if (_activeTab == 'chapters') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ManageContentScreen(
                                    contentType: ContentType.chapter,
                                    parentId: widget.subjectId,
                                    existingFolders: _existingFolderNames(),
                                  ),
                                ),
                              ).then((val) {
                                if (val == true) _fetchContent();
                              });
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CreateExamScreen(
                                      subjectId: widget.subjectId),
                                ),
                              ).then((_) => _fetchContent());
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color:
                                      AppColors.accentYellow.withOpacity(0.5)),
                            ),
                            child: Icon(
                                _activeTab == 'chapters'
                                    ? LucideIcons.folderPlus
                                    : LucideIcons.filePlus,
                                color: AppColors.accentYellow,
                                size: 22),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tab Switcher
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildTab(
                            AppLocalizations.of(context)!.chaptersTabLabel,
                            'chapters'),
                        _buildTab(
                            AppLocalizations.of(context)!
                                .examsTabLabel(exams.length),
                            'exams'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _activeTab == 'chapters'
                  ? _buildChaptersList(chapters)
                  : _buildExamsList(exams),
            ),
          ],
        ),
      ),
    );
  }

  // --- قائمة الامتحانات ---
  Widget _buildExamsList(List allExams) {
    final visibleExams = allExams.where((exam) {
      if (_isTeacher) return true;

      if (exam['start_time'] != null) {
        final DateTime startTime = DateTime.parse(exam['start_time']).toLocal();
        if (DateTime.now().isBefore(startTime)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (visibleExams.isEmpty) {
      return _buildEmptyState(
          LucideIcons.fileCheck, AppLocalizations.of(context)!.noExamsAvailable);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: visibleExams.length,
      itemBuilder: (context, index) {
        final exam = visibleExams[index];
        final bool isCompleted = exam['isCompleted'] ?? false;
        final bool isExpired = exam['isExpired'] ?? false;
        // ✅ حالة جديدة: الامتحان مُسلَّم وبانتظار تصحيح المعلم اليدوي (أسئلة مقالية)
        final bool isPendingGrading = exam['isPendingGrading'] ?? false;
        
        // ✅ 1. التعديل هنا: قراءة المتغير بأمان تام لدعم جميع أنواع البيانات
        final bool allowRetake = exam['allow_retake'] == true || exam['allow_retake'] == 'true' || exam['allow_retake'] == 1;

        Color statusColor = AppColors.accentOrange;
        String statusText = AppLocalizations.of(context)!.examStatusUnsolved;
        IconData statusIcon = LucideIcons.fileX;

        if (isPendingGrading) {
          // الامتحان مُسلَّم ويحتوي على أسئلة مقالية بانتظار تصحيح المعلم
          statusColor = AppColors.accentYellow;
          statusText = AppLocalizations.of(context)!.examStatusPending;
          statusIcon = LucideIcons.clipboardPen;
        } else if (isCompleted) {
          // ✅ 2. التعديل هنا: إزالة شرط (!_isTeacher) لكي يرى المعلم زر التدريب
          if (allowRetake) {
            statusColor = AppColors.accentYellow;
            statusText = AppLocalizations.of(context)!.examStatusPractice;
            statusIcon = LucideIcons.refreshCcw;
          } else {
            statusColor = AppColors.success;
            statusText = AppLocalizations.of(context)!.examStatusCompleted;
            statusIcon = LucideIcons.checkCircle2;
          }
        } else if (isExpired) {
          statusColor = AppColors.error;
          statusText = AppLocalizations.of(context)!.examStatusExpired;
          statusIcon = LucideIcons.clock;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              // الأيقونة
              GestureDetector(
                onTap: () => _openExam(exam, isCompleted, isExpired),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 20),
                ),
              ),
              const SizedBox(width: 16),

              // التفاصيل
              Expanded(
                child: GestureDetector(
                  onTap: () => _openExam(exam, isCompleted, isExpired),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (exam['title'] ??
                                AppLocalizations.of(context)!
                                    .untitledExamFallback)
                            .toString()
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            AppLocalizations.of(context)!.examDurationMinutes(
                                (exam['duration_minutes'] ?? 0).toString()),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary.withOpacity(0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 🟢 أزرار التحكم للمعلم
              if (_isTeacher)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(LucideIcons.edit,
                          color: AppColors.accentOrange, size: 20),
                      tooltip: AppLocalizations.of(context)!.editExamTooltip,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateExamScreen(
                              subjectId: widget.subjectId,
                              examId: exam['id'].toString(),
                            ),
                          ),
                        ).then((val) {
                          if (val == true) _fetchContent();
                        });
                      },
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.barChart2,
                          color: AppColors.accentYellow, size: 20),
                      tooltip: AppLocalizations.of(context)!.statisticsTooltip,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExamStatsScreen(
                              examId: exam['id'].toString(),
                              examTitle: exam['title'] ??
                                  AppLocalizations.of(context)!
                                      .examFallbackTitle,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                )
              else
                IconButton(
                  icon: DirectionalFlip(child: Icon(LucideIcons.chevronRight,
                      size: 20, color: statusColor.withOpacity(0.5))),
                  onPressed: () => _openExam(exam, isCompleted, isExpired),
                ),
            ],
          ),
        );
      },
    );
  }

  // ✅ التعديل هنا: الدالة الخاصة بفتح الامتحان والتوجيه الصحيح في حالة الإعادة
  void _openExam(Map exam, bool isCompleted, bool isExpired) {
    // ✅ قراءة المتغير بأمان تام
    final bool allowRetake = exam['allow_retake'] == true || exam['allow_retake'] == 'true' || exam['allow_retake'] == 1;
    // ✅ حالة الامتحان بانتظار تصحيح المعلم اليدوي
    final bool isPendingGrading = exam['isPendingGrading'] ?? false;

    // ✅ إذا كان الامتحان بانتظار التصحيح اليدوي، نظهر رسالة توضيحية
    if (isPendingGrading) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: Row(
            children: [
              Icon(LucideIcons.clipboardPen, color: AppColors.accentYellow, size: 20),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.examPendingReviewTitle,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            ],
          ),
          content: Text(
            AppLocalizations.of(context)!.examPendingReviewMessage,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.ok,
                  style: TextStyle(color: AppColors.accentYellow)),
            ),
          ],
        ),
      );
      return;
    }

    // دوال مساعدة للتوجيه
    void navigateToResult() {
      final attemptId = exam['last_attempt_id'] ??
          exam['first_attempt_id'] ??
          exam['attempt_id'];
      if (attemptId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
              attemptId: attemptId.toString(),
              examTitle: exam['title'] ??
                  AppLocalizations.of(context)!.examResultFallbackTitle,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.examResultLoadError),
            backgroundColor: AppColors.error));
      }
    }

    void navigateToExamView() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExamViewScreen(
            examId: exam['id'].toString(),
            examTitle:
                exam['title'] ?? AppLocalizations.of(context)!.examFallbackTitle,
            isCompleted: isCompleted,
          ),
        ),
      ).then((_) => _fetchContent());
    }

    if (isCompleted) {
      // ✅ تم إزالة شرط (!_isTeacher) ليتمكن المعلم أيضاً من اختبار وضع الإعادة
      if (allowRetake) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.backgroundSecondary,
            title: Text(AppLocalizations.of(context)!.examOptionsDialogTitle,
                style: TextStyle(color: AppColors.textPrimary)),
            content: Text(
                AppLocalizations.of(context)!.examRetakeOptionsMessage,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  navigateToResult();
                },
                child: Text(AppLocalizations.of(context)!.viewResultButton,
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow),
                onPressed: () {
                  Navigator.pop(ctx);
                  navigateToExamView();
                },
                child: Text(
                    AppLocalizations.of(context)!.retakeForPracticeButton,
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        // الامتحان محلول ولا يوجد إعادة -> اذهب للنتيجة مباشرة
        navigateToResult();
      }
    } else if (isExpired) {
      // إذا كان الامتحان منتهي الصلاحية، يفتح مباشرة لرؤية نموذج الإجابة بدون نافذة تأكيد
      navigateToExamView();
    } else {
      // إذا كان الامتحان "غير محلول" (Unsolved) ومتاحاً
      // يتم إظهار نافذة التأكيد قبل بدء التايمر
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: Text(
            AppLocalizations.of(context)!.confirmStartExamTitle,
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            AppLocalizations.of(context)!.confirmStartExamMessage,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel,
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow),
              onPressed: () {
                Navigator.pop(ctx); // إغلاق النافذة المنبثقة
                navigateToExamView(); // الذهاب للامتحان وبدء الوقت
              },
              child: Text(AppLocalizations.of(context)!.startExamButton,
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildChaptersList(List chapters) {
    if (chapters.isEmpty) {
      return _buildEmptyState(
          LucideIcons.bookOpen, AppLocalizations.of(context)!.noChaptersFound);
    }

    // ✅ [جديد] تجميع اختياري بالكامل: لو المدرس لم يستخدم المجلدات إطلاقاً
    // (لا يوجد أي فصل بحقل folder_name)، تُعرض القائمة تماماً كما كانت من
    // قبل — صفر تغيير بصرياً أو سلوكياً على أي كورس/مادة قديمة أو جديدة
    // لا يستخدم هذه الميزة.
    final bool hasAnyFolder = chapters.any((c) =>
        ((c['folder_name'] as String?)?.trim().isNotEmpty ?? false));

    if (!hasAnyFolder) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: chapters.length,
        itemBuilder: (context, index) =>
            _buildChapterCard(chapters[index], index),
      );
    }

    // 🗂️ نبني قائمة عناصر معروضة بالحفاظ على ترتيب الظهور الأصلي
    // (حسب sort_order القادم من السيرفر): كل فصل بدون مجلد يبقى عنصراً
    // منفرداً في مكانه، وكل مجموعة فصول تشترك بنفس اسم المجلد تُجمع في
    // أول مكان ظهر فيه اسم هذا المجلد.
    final List<_ChapterEntry> entries = [];
    final Map<String, int> folderPosition = {};

    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final String folderName =
          (chapter['folder_name'] as String?)?.trim() ?? '';

      if (folderName.isEmpty) {
        entries.add(_ChapterEntry.single(chapter, i));
        continue;
      }

      if (folderPosition.containsKey(folderName)) {
        entries[folderPosition[folderName]!]
            .items!
            .add(MapEntry(chapter, i));
      } else {
        folderPosition[folderName] = entries.length;
        entries.add(_ChapterEntry.folder(folderName, [MapEntry(chapter, i)]));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        if (!entry.isFolder) {
          return _buildChapterCard(entry.chapter!, entry.originalIndex!);
        }
        return _buildFolderGroup(entry.folderName!, entry.items!);
      },
    );
  }

  // 🗂️ [جديد] رأس مجلد قابل للطي يحتوي على فصوله بنفس تصميم بطاقة الفصل
  // العادية تماماً — لا تغيير على أي شيء آخر غير طريقة العرض/التجميع.
  Widget _buildFolderGroup(String folderName, List<MapEntry> items) {
    final bool isCollapsed = _collapsedFolders.contains(folderName);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                if (isCollapsed) {
                  _collapsedFolders.remove(folderName);
                } else {
                  _collapsedFolders.add(folderName);
                }
              });
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.accentYellow.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.folder,
                      size: 18, color: AppColors.accentYellow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MarqueeText(
                      folderName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Text(
                    "${items.length}",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isCollapsed
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronUp,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 10),
            // 🌳 [جديد] خط دليل رفيع يربط بصرياً بين رأس المجلد وفصوله،
            // ليكون واضحاً للعين مباشرة أن هذه البطاقات "متداخلة" داخل
            // مجلد وليست فصولاً مستقلة في نفس مستوى القائمة الرئيسية.
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 2,
                      margin: const EdgeInsetsDirectional.only(end: 14),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: items
                            .map<Widget>((e) => _buildChapterCard(
                                e.key, e.value as int,
                                compact: true))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 🔵 بطاقة فصل واحدة — نفس التصميم الأصلي بالحرف، فقط تم استخراجه في
  // دالة مستقلة ليُستخدم سواء داخل القائمة العادية أو داخل مجموعة مجلد.
  Widget _buildChapterCard(dynamic chapter, int index, {bool compact = false}) {
    final videosCount = (chapter['videos'] as List? ?? []).length;
    final pdfsCount = (chapter['pdfs'] as List? ?? []).length;

    // 🗜️ [محدَّث] أبعاد أصغر وأكثر إحكاماً لبطاقة فصل داخل مجلد (ارتفاع أقل
    // بوضوح)، بدون أي تأثير على شكل الفصول المستقلة (بدون مجلد) والتي
    // تحتفظ بحجمها الأصلي بالكامل.
    final double cardPadding = compact ? 9 : 16;
    final double cardMarginBottom = compact ? 6 : 12;
    final double cardRadius = compact ? 10 : 16;
    final double badgeSize = compact ? 26 : 40;
    final double badgeRadius = compact ? 6 : 8;
    final double badgeFontSize = compact ? 9 : 12;
    final double gapWidth = compact ? 10 : 16;
    final double titleFontSize = compact ? 12 : 15;
    final double hashIconSize = compact ? 8 : 10;
    final double countsFontSize = compact ? 7 : 9;
    final double actionIconSize = compact ? 16 : 20;
    final double editIconSize = compact ? 14 : 18;
    final double chevronSize = compact ? 14 : 18;

    return GestureDetector(
      onTap: () {
        final String courseTitle = _content?['course_title'] ??
            AppLocalizations.of(context)!.unknownCourseFallback;

        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ChapterContentsScreen(
                    chapter: Map<String, dynamic>.from(chapter),
                    courseTitle: courseTitle,
                    subjectTitle: widget.subjectTitle,
                    subjectId: widget.subjectId,
                    playerSettings: _content?['player_settings'],
                  )),
        ).then((updatedChapter) {
          if (updatedChapter != null && updatedChapter is Map) {
            _updateChapterList(Map<String, dynamic>.from(updatedChapter));
          } else {
            _fetchContent();
          }
        });
      },
      child: Container(
        margin: EdgeInsets.only(bottom: cardMarginBottom),
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          // 🎨 [جديد] البطاقات داخل مجلد تأخذ لوناً أهدأ وأكثر تسطحاً
          // (بدون ظل) لتمييزها بصرياً فوراً عن الفصول المستقلة خارج أي
          // مجلد، والتي تحتفظ بمظهرها الأصلي البارز مع الظل الخفيف.
          color: compact
              ? AppColors.backgroundSecondary.withOpacity(0.55)
              : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(
            color: compact
                ? AppColors.accentYellow.withOpacity(0.12)
                : Colors.white.withOpacity(0.05),
          ),
          boxShadow: compact
              ? []
              : const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(badgeRadius),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 2)
                ],
              ),
              child: Center(
                child: Text(
                  "${index + 1}".padLeft(2, '0'),
                  style: TextStyle(
                    color: AppColors.accentYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: badgeFontSize,
                  ),
                ),
              ),
            ),
            SizedBox(width: gapWidth),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    (chapter['title'] ??
                            AppLocalizations.of(context)!
                                .chapterFallbackTitle)
                        .toString()
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(LucideIcons.hash,
                          size: hashIconSize, color: AppColors.accentOrange),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)!
                            .contentsCountLabel(videosCount + pdfsCount),
                        style: TextStyle(
                          fontSize: countsFontSize,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 🟢 أزرار الشابتر (التقييم بجوار القلم أو السهم)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 💬 زر تقييم الشابتر
                IconButton(
                  icon: Icon(LucideIcons.messageCircle,
                      size: actionIconSize, color: AppColors.textSecondary),
                  onPressed: () {
                    if (_isTeacher) {
                      _showTeacherFeedbackDialog(chapter['id'].toString());
                    } else {
                      _showStudentFeedbackDialog(chapter['id'].toString());
                    }
                  },
                ),

                if (_isTeacher)
                  IconButton(
                    icon: Icon(LucideIcons.edit2,
                        size: editIconSize, color: AppColors.accentYellow),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManageContentScreen(
                            contentType: ContentType.chapter,
                            initialData: chapter,
                            parentId: widget.subjectId,
                            existingFolders: _existingFolderNames(),
                          ),
                        ),
                      ).then((val) {
                        if (val == true) _fetchContent();
                      });
                    },
                  )
                else
                  DirectionalFlip(child: Icon(LucideIcons.chevronRight,
                      size: chevronSize, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, String key) {
    final isActive = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeTab = key);
          FirebaseCrashlytics.instance.log("Switched tab to: $key");
        },
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

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message.toUpperCase(),
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
}

// ============================================================
// 🗂️ [جديد] عنصر مساعد بسيط لعرض قائمة الفصول: إما فصل منفرد (بدون
// مجلد) أو مجموعة فصول تشترك في نفس اسم المجلد الاختياري. يُستخدم فقط
// داخل _buildChaptersList لتحديد شكل العرض ولا يخزَّن أو يُرسل لأي API.
// ============================================================
class _ChapterEntry {
  final bool isFolder;
  final dynamic chapter; // للفصل المنفرد فقط
  final int? originalIndex; // ترقيم الفصل الأصلي (للفصل المنفرد فقط)
  final String? folderName; // لمجموعة المجلد فقط
  final List<MapEntry<dynamic, int>>? items; // فصول المجلد + ترقيمها الأصلي

  _ChapterEntry.single(this.chapter, this.originalIndex)
      : isFolder = false,
        folderName = null,
        items = null;

  _ChapterEntry.folder(this.folderName, this.items)
      : isFolder = true,
        chapter = null,
        originalIndex = null;
}
