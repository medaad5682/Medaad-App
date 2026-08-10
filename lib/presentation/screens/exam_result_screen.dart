import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';

class ExamResultScreen extends StatefulWidget {
  final String attemptId;
  final String examTitle;
  final Map<String, dynamic>? practiceResults;

  const ExamResultScreen({
    super.key,
    required this.attemptId,
    required this.examTitle,
    this.practiceResults,
  });

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  bool _loading = true;
  Map<String, dynamic>? _resultData;

  String? _userId;
  String? _deviceId;
  String? _token;
  String? _appCheckToken;
  final String _appSecret = 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only';
  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("View Result: ${widget.attemptId}");
    _initData();
  }

  Future<void> _initData() async {
    try {
      var box = await StorageService.openBox('auth_box');
      _userId = box.get('user_id');
      _deviceId = box.get('device_id');
      _token = box.get('jwt_token');

      try {
        _appCheckToken = await FirebaseAppCheck.instance.getToken().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint("App Check Error: $e");
      }
    } catch (e) {
      debugPrint("Error loading auth tokens: $e");
    }

    if (widget.practiceResults != null) {
      if (mounted) {
        setState(() {
          _resultData = widget.practiceResults;
          _loading = false;
        });
      }
    } else {
      await _fetchResults();
    }
  }

  Future<void> _fetchResults() async {
    try {
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/exams/get-results',
        queryParameters: {'attemptId': widget.attemptId},
      );

      if (mounted && res.statusCode == 200) {
        setState(() {
          _resultData = res.data;
          _loading = false;
        });

        _cacheResultLocally(res.data);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Fetch Results Error');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cacheResultLocally(Map<String, dynamic> data) async {
    try {
      var historyBox = await StorageService.openBox('exams_history_box');
      await historyBox.put(widget.attemptId, data);
    } catch (e) {
      debugPrint("Failed to cache result: $e");
    }
  }

  void _showEnlargedImage(String imageFileId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl:
                      '$_baseUrl/api/exams/get-image?file_id=$imageFileId',
                  httpHeaders: {
                    'Authorization': 'Bearer $_token',
                    'x-device-id': _deviceId ?? '',
                    'x-app-secret': _appSecret,
                    if (_appCheckToken != null)
                      'X-Firebase-AppCheck': _appCheckToken!,
                  },
                  placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentYellow)),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.error, color: AppColors.error),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build the essay question result card
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildEssayResultCard(Map<String, dynamic> q, int index) {
    final userAnswer = q['user_answer'] as Map<String, dynamic>?;
    final String studentText = userAnswer?['text_answer']?.toString() ??
        AppLocalizations.of(context)!.noAnswerSubmittedFallback;
    final dynamic rawScore = q['earned_score'];
    final int? earnedScore =
        rawScore != null ? (rawScore as num).toInt() : null;
    final int? maxScore =
        q['max_score'] != null ? (q['max_score'] as num).toInt() : null;
    final String? teacherFeedback = q['teacher_feedback']?.toString();
    final String? imageFileId = q['image_file_id']?.toString();
    final String? modelAnswer = q['model_answer']?.toString();

    final bool isGraded = earnedScore != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isGraded
                ? AppColors.accentYellow.withOpacity(0.4)
                : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: question number + WRITTEN badge + score
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.writtenBadgeShort,
                    style: TextStyle(
                        color: AppColors.accentYellow,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                    AppLocalizations.of(context)!
                        .questionNumberLabel(index + 1),
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                if (maxScore != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isGraded
                          ? AppColors.success.withOpacity(0.15)
                          : AppColors.backgroundPrimary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isGraded
                              ? AppColors.success.withOpacity(0.4)
                              : Colors.white12),
                    ),
                    child: Text(
                      isGraded
                          ? AppLocalizations.of(context)!
                              .pointsScoredLabel(earnedScore!, maxScore)
                          : AppLocalizations.of(context)!
                              .pointsPendingLabel(maxScore),
                      style: TextStyle(
                          color: isGraded
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Optional image
          if (imageFileId != null && imageFileId.isNotEmpty)
            GestureDetector(
              onTap: () => _showEnlargedImage(imageFileId),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl:
                        '$_baseUrl/api/exams/get-image?file_id=$imageFileId',
                    httpHeaders: {
                      'Authorization': 'Bearer $_token',
                      'x-device-id': _deviceId ?? '',
                      'x-app-secret': _appSecret,
                      if (_appCheckToken != null)
                        'X-Firebase-AppCheck': _appCheckToken!,
                    },
                    placeholder: (context, url) => Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accentYellow)),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error, color: AppColors.error),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

          // Question text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(q['question_text'] ?? "",
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4)),
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),

          // Student's answer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(AppLocalizations.of(context)!.yourAnswerLabel,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                studentText,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, height: 1.5),
              ),
            ),
          ),

          // Model answer (reference answer set by the teacher, if any)
          if (modelAnswer != null && modelAnswer.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle,
                      color: AppColors.success, size: 14),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context)!.modelAnswerLabel,
                      style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withOpacity(0.2)),
                ),
                child: Text(
                  modelAnswer,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ],

          // Teacher feedback (only visible when graded)
          if (teacherFeedback != null && teacherFeedback.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Icon(LucideIcons.messageSquare,
                      color: AppColors.accentYellow, size: 14),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context)!.teacherFeedbackLabel,
                      style: TextStyle(
                          color: AppColors.accentYellow,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accentYellow.withOpacity(0.2)),
                ),
                child: Text(
                  teacherFeedback,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow)));

    if (_resultData == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: AppColors.textPrimary)),
        body: Center(
            child: Text(AppLocalizations.of(context)!.failedToLoadResults,
                style: TextStyle(color: AppColors.error))),
      );
    }

    // ── Pending grading state ─────────────────────────────────────────────────
    if (_resultData!['pending_grading'] == true) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text(widget.examTitle,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          backgroundColor: AppColors.backgroundSecondary,
          leading: IconButton(
            icon: Icon(LucideIcons.x, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.clipboardPen,
                      color: AppColors.accentYellow, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.awaitingTeacherReview,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _resultData!['message'] ??
                      AppLocalizations.of(context)!.examUnderReviewMessage,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(
                        AppLocalizations.of(context)!.backToCourseButton,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Normal result display ────────────────────────────────────────────────
    final scoreDetails = _resultData!['score_details'] ?? _resultData!;
    final List questions = _resultData!['corrected_questions'] ?? [];
    final double percentage = (scoreDetails['percentage'] ?? 0) / 100.0;
    final bool isPractice = _resultData!['is_practice'] == true;

    // Check if exam has any essay questions
    final bool hasEssayQuestions =
        questions.any((q) => q['question_type'] == 'essay');

    // For score display — MCQ only
    final int mcqCorrect = scoreDetails['correct'] ?? 0;
    final int mcqTotal = scoreDetails['total'] ?? 0;

    // For essay score display
    final dynamic rawTotalScore = scoreDetails['score'];
    final int? totalScore =
        rawTotalScore != null ? (rawTotalScore as num).toInt() : null;

    // ── Final points display, e.g. "8/10" ──────────────────────────────────
    // Real graded exams: backend sends total_points (mcq count + essay max scores).
    // Practice mode: only MCQ is auto-graded, so score/total already represent points.
    final dynamic rawTotalPoints = scoreDetails['total_points'];
    final int displayPoints =
        isPractice ? mcqCorrect : (totalScore ?? mcqCorrect);
    final int displayMaxPoints = isPractice
        ? mcqTotal
        : (rawTotalPoints != null ? (rawTotalPoints as num).toInt() : mcqTotal);

    Color statusColor = percentage >= 0.5 ? AppColors.success : AppColors.error;
    String statusMsg = percentage >= 0.5
        ? AppLocalizations.of(context)!.examPassedLabel
        : AppLocalizations.of(context)!.examFailedLabel;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
            isPractice
                ? AppLocalizations.of(context)!.practiceResultTitle
                : AppLocalizations.of(context)!.examResultsTitle,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundSecondary,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Practice mode notice
            if (isPractice)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.accentYellow.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info,
                        color: AppColors.accentYellow, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.practiceModeNotice,
                        style: TextStyle(
                            color: Colors.white, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Score summary card ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  CircularPercentIndicator(
                    radius: 60.0,
                    lineWidth: 10.0,
                    percent: percentage.clamp(0.0, 1.0),
                    center: Text("${(percentage * 100).toInt()}%",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            color: statusColor)),
                    progressColor: statusColor,
                    backgroundColor: Colors.black26,
                    circularStrokeCap: CircularStrokeCap.round,
                  ),
                  const SizedBox(height: 16),
                  Text(statusMsg,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 2.0)),
                  const SizedBox(height: 10),

                  // ── Final points "8/10" style ──────────────────────────────
                  if (displayMaxPoints > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        "$displayPoints / $displayMaxPoints",
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Essay pending notice inside summary
                  if (hasEssayQuestions && totalScore == null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.pencilLine,
                              color: AppColors.accentYellow, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.of(context)!
                                .writtenQuestionsPendingGrading,
                            style: TextStyle(
                                color: AppColors.accentYellow, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Detailed Analysis ──────────────────────────────────────────
            if (questions.isNotEmpty) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(AppLocalizations.of(context)!.detailedAnalysisLabel,
                    style: TextStyle(
                        color: AppColors.accentYellow,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(height: 16),
              ...List.generate(questions.length, (index) {
                final q = questions[index];
                final String? qType = q['question_type']?.toString();

                // ── Essay card ──────────────────────────────────────────────
                if (qType == 'essay') {
                  return _buildEssayResultCard(q, index);
                }

                // ── MCQ card ────────────────────────────────────────────────
                final userAnsId = q['user_answer']?['selected_option_id'];
                final correctOptId = q['correct_option_id'];
                final bool isCorrect = userAnsId != null &&
                    userAnsId.toString() == correctOptId.toString();
                final String? imageFileId = q['image_file_id']?.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isCorrect
                            ? AppColors.success.withOpacity(0.3)
                            : AppColors.error.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                              isCorrect
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.xCircle,
                              color: isCorrect
                                  ? AppColors.success
                                  : AppColors.error,
                              size: 20),
                          const SizedBox(width: 10),
                          Text(
                              AppLocalizations.of(context)!
                                  .questionNumberLabel(index + 1),
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (imageFileId != null && imageFileId.isNotEmpty)
                        GestureDetector(
                          onTap: () => _showEnlargedImage(imageFileId),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl:
                                    '$_baseUrl/api/exams/get-image?file_id=$imageFileId',
                                httpHeaders: {
                                  'Authorization': 'Bearer $_token',
                                  'x-device-id': _deviceId ?? '',
                                  'x-app-secret': _appSecret,
                                  if (_appCheckToken != null)
                                    'X-Firebase-AppCheck': _appCheckToken!,
                                },
                                placeholder: (context, url) => Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accentYellow)),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error,
                                        color: AppColors.error),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      Text(q['question_text'] ?? "",
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      ...(q['options'] as List).map((opt) {
                        final bool isSelected =
                            opt['id'].toString() == userAnsId.toString();
                        final bool isTheCorrectOne =
                            opt['id'].toString() == correctOptId.toString();

                        Color bgColor = Colors.transparent;
                        Color borderColor = Colors.white10;
                        IconData? icon;
                        Color iconColor = Colors.transparent;

                        if (isTheCorrectOne) {
                          bgColor = AppColors.success.withOpacity(0.1);
                          borderColor = AppColors.success;
                          icon = Icons.check_circle;
                          iconColor = AppColors.success;
                        } else if (isSelected && !isTheCorrectOne) {
                          bgColor = AppColors.error.withOpacity(0.1);
                          borderColor = AppColors.error;
                          icon = Icons.cancel;
                          iconColor = AppColors.error;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              if (icon != null) ...[
                                Icon(icon, size: 16, color: iconColor),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                  child: Text(opt['option_text'],
                                      style: TextStyle(
                                          color: isTheCorrectOne
                                              ? AppColors.success
                                              : AppColors.textSecondary,
                                          fontWeight: isTheCorrectOne
                                              ? FontWeight.bold
                                              : FontWeight.normal))),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
