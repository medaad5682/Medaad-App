import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../core/constants/app_colors.dart';
import 'exam_result_screen.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';

class ExamViewScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final bool isCompleted;

  const ExamViewScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.isCompleted,
  });

  @override
  State<ExamViewScreen> createState() => _ExamViewScreenState();
}

class _ExamViewScreenState extends State<ExamViewScreen> {
  bool _loading = true;
  List<dynamic> _questions = [];

  bool _isModelAnswerMode = false;

  int currentIdx = 0;

  // MCQ answers: questionId -> optionId
  Map<String, int> userMcqAnswers = {};
  // Essay answers: questionId -> text
  Map<String, String> userEssayAnswers = {};

  // Controllers for essay TextFields — one per question index
  final Map<int, TextEditingController> _essayControllers = {};

  Set<String> flaggedQuestions = {};

  int timeLeft = 0;
  Timer? _timer;
  String? _attemptId;

  String? _userId;
  String? _deviceId;
  String? _token;
  String? _appCheckToken;
  final String _appSecret = const String.fromEnvironment('APP_SECRET');

  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Opened Exam: ${widget.examId}");
    _startExamAttempt();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final ctrl in _essayControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _essayController(int index) {
    return _essayControllers.putIfAbsent(index, () => TextEditingController());
  }

  bool get _isEssayQuestion {
    if (_questions.isEmpty) return false;
    return _questions[currentIdx]['question_type'] == 'essay';
  }

  // Returns true if question at given index is an essay type
  bool _isEssay(int index) {
    if (index >= _questions.length) return false;
    return _questions[index]['question_type'] == 'essay';
  }

  // Count answered questions (both MCQ and essay with non-empty text)
  int get _answeredCount {
    int count = 0;
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final qId = q['id'].toString();
      if (_isEssay(i)) {
        final ctrl = _essayControllers[i];
        final text = ctrl?.text.trim() ?? userEssayAnswers[qId]?.trim() ?? '';
        if (text.isNotEmpty) count++;
      } else {
        if (userMcqAnswers.containsKey(qId)) count++;
      }
    }
    return count;
  }

  Future<void> _startExamAttempt() async {
    try {
      var box = await StorageService.openBox('auth_box');
      _userId = box.get('user_id');
      _deviceId = box.get('device_id');
      _token = box.get('jwt_token');
      final name = box.get('first_name') ?? 'Student';

      try {
        _appCheckToken = await FirebaseAppCheck.instance.getToken();
      } catch (e) {
        debugPrint("App Check Error: $e");
      }

      final res = await ApiClient.instance.post(
        '$_baseUrl/api/exams/start-attempt',
        data: {'examId': widget.examId, 'studentName': name},
      );

      if (mounted && res.statusCode == 200) {
        final data = res.data;

        if (data['mode'] == 'model_answer') {
          setState(() {
            _isModelAnswerMode = true;
            _questions = data['questions'] ?? [];
            timeLeft = 0;
            _loading = false;
          });
        } else {
          int apiDuration = data['durationMinutes'] ?? 30;

          setState(() {
            _isModelAnswerMode = false;
            _questions = data['questions'] ?? [];
            _attemptId = data['attemptId'].toString();
            timeLeft = apiDuration * 60;
            _loading = false;
          });

          _startTimer();
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'Start Exam Failed');
      if (mounted) {
        String msg = AppLocalizations.of(context)!.failedToStartExam;
        if (e is DioException) {
          if (e.response?.statusCode == 403)
            msg = e.response?.data['error'] ?? AppLocalizations.of(context)!.accessDeniedFallback;
          if (e.response?.statusCode == 409) {
            final data = e.response?.data;
            if (data != null && data['isPendingGrading'] == true) {
              msg = data['error'] ?? AppLocalizations.of(context)!.examPendingReviewMessage;
            } else {
              msg = AppLocalizations.of(context)!.examAlreadyCompleted;
            }
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppColors.error));
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft <= 0) {
        timer.cancel();
        _submitExam(autoSubmit: true);
      } else {
        setState(() => timeLeft--);
      }
    });
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return "0:00";
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  /// Sync essay controller text into the answers map before submitting
  void _syncEssayAnswers() {
    for (int i = 0; i < _questions.length; i++) {
      if (_isEssay(i)) {
        final ctrl = _essayControllers[i];
        if (ctrl != null) {
          final qId = _questions[i]['id'].toString();
          userEssayAnswers[qId] = ctrl.text.trim();
        }
      }
    }
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isModelAnswerMode) {
      Navigator.pop(context);
      return;
    }

    // Sync essay text fields into the map
    _syncEssayAnswers();

    if (!autoSubmit) {
      final int answered = _answeredCount;
      if (answered < _questions.length) {
        final int unanswered = _questions.length - answered;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.cannotSubmitUnanswered(unanswered),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    _timer?.cancel();

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
            child: CircularProgressIndicator(color: AppColors.accentYellow)));

    try {
      // Merge MCQ and essay answers into a single map for the API
      // MCQ: questionId -> optionId (int)
      // Essay: questionId -> text (String)
      final Map<String, dynamic> combinedAnswers = {};
      userMcqAnswers.forEach((k, v) => combinedAnswers[k] = v);
      userEssayAnswers.forEach((k, v) {
        if (v.isNotEmpty) combinedAnswers[k] = v;
      });

      final res = await ApiClient.instance.post(
        '$_baseUrl/api/exams/submit-attempt',
        data: {
          'attemptId': _attemptId,
          'answers': combinedAnswers,
          'examId': widget.examId,
        },
      );

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
              attemptId: _attemptId!,
              examTitle: widget.examTitle,
              practiceResults:
                  _attemptId == 'temp_retake_mode' ? res.data : null,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToSubmitTryAgain),
            backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _showExitWarningDialog() async {
    final shouldSubmit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(AppLocalizations.of(context)!.exitExamTitle,
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
            AppLocalizations.of(context)!.exitExamWarningMessage,
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(AppLocalizations.of(context)!.stayButton, style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(AppLocalizations.of(context)!.submitAndExitButton,
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldSubmit == true) {
      _submitExam(autoSubmit: true);
    }
  }

  void _showZoomableImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
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
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build essay question widget
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildEssayQuestion(String questionId, int index) {
    final ctrl = _essayController(index);

    // In model_answer mode for essay, just show a placeholder (essays have no
    // is_correct on options — the model answer is shown as text if present)
    if (_isModelAnswerMode) {
      final modelAnswer = _questions[index]['model_answer'] as String?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accentYellow.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentYellow.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.pencilLine,
                    color: AppColors.accentYellow, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    modelAnswer?.isNotEmpty == true
                        ? modelAnswer!
                        : AppLocalizations.of(context)!.noModelAnswerProvided,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Normal exam mode: text field
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.accentYellow.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.accentYellow.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.pencilLine,
                  color: AppColors.accentYellow, size: 16),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.writtenQuestionInstructions,
                style: TextStyle(
                    color: AppColors.accentYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: ctrl,
          maxLines: 8,
          minLines: 4,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.5),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.writeAnswerHint,
            hintStyle:
                TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppColors.accentYellow, width: 1.5),
            ),
          ),
          onChanged: (val) {
            // Keep the map in sync while typing
            setState(() {
              userEssayAnswers[questionId] = val.trim();
            });
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            AppLocalizations.of(context)!.charactersCountLabel(ctrl.text.trim().length),
            style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.5), fontSize: 11),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child:
                  CircularProgressIndicator(color: AppColors.accentYellow)));

    final questionData = _questions[currentIdx];
    final String questionId = questionData['id'].toString();
    final String? imageFileId = questionData['image_file_id'];
    final bool isEssay = _isEssay(currentIdx);
    final options = isEssay
        ? <Map<String, dynamic>>[]
        : (questionData['options'] as List).cast<Map<String, dynamic>>();

    bool isFlagged = flaggedQuestions.contains(questionId);

    return PopScope(
      canPop: _isModelAnswerMode,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _showExitWarningDialog();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!_isModelAnswerMode)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            if (isFlagged) {
                              flaggedQuestions.remove(questionId);
                            } else {
                              flaggedQuestions.add(questionId);
                            }
                          });
                        },
                        icon: Icon(
                          LucideIcons.flag,
                          color:
                              isFlagged ? AppColors.accentOrange : Colors.grey,
                        ),
                        tooltip: AppLocalizations.of(context)!.markQuestionTooltip,
                      ),

                    Text(AppLocalizations.of(context)!.questionCounterLabel(currentIdx + 1, _questions.length),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary)),

                    if (!_isModelAnswerMode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: timeLeft < 60
                              ? AppColors.error.withOpacity(0.2)
                              : AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: timeLeft < 60
                                  ? AppColors.error
                                  : Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.clock,
                                size: 14,
                                color: timeLeft < 60
                                    ? AppColors.error
                                    : AppColors.accentYellow),
                            const SizedBox(width: 6),
                            Text(_formatTime(timeLeft),
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: timeLeft < 60
                                        ? AppColors.error
                                        : AppColors.textPrimary)),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppColors.accentYellow.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(AppLocalizations.of(context)!.modelAnswerLabel,
                            style: TextStyle(
                                color: AppColors.accentYellow,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),

              // ── Question Navigator ──────────────────────────────────────────
              Container(
                height: 50,
                width: double.infinity,
                padding: const EdgeInsets.only(bottom: 8),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _questions.length,
                  separatorBuilder: (ctx, index) => const SizedBox(width: 8),
                  itemBuilder: (ctx, index) {
                    final q = _questions[index];
                    final qIdStr = q['id'].toString();
                    final bool isQEssay = _isEssay(index);

                    bool isCurrent = index == currentIdx;
                    bool isAnswered;
                    if (isQEssay) {
                      final ctrl = _essayControllers[index];
                      isAnswered = (ctrl?.text.trim().isNotEmpty == true) ||
                          (userEssayAnswers[qIdStr]?.isNotEmpty == true);
                    } else {
                      isAnswered = userMcqAnswers.containsKey(qIdStr);
                    }
                    bool isMarked = flaggedQuestions.contains(qIdStr);

                    Color boxColor = AppColors.backgroundSecondary;
                    Color textColor = AppColors.textSecondary;
                    Color borderColor = Colors.white.withOpacity(0.1);

                    if (isCurrent) {
                      boxColor = AppColors.accentYellow;
                      borderColor = AppColors.accentYellow;
                      textColor = AppColors.backgroundPrimary;
                    } else if (isMarked) {
                      boxColor = AppColors.accentOrange.withOpacity(0.15);
                      borderColor = AppColors.accentOrange;
                      textColor = AppColors.accentOrange;
                    } else if (isAnswered) {
                      boxColor = AppColors.success.withOpacity(0.2);
                      borderColor = Colors.transparent;
                      textColor = AppColors.success;
                    }

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          currentIdx = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: boxColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: borderColor,
                              width: isMarked ? 2.0 : 1.5),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              "${index + 1}",
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            // Small pencil badge for essay questions
                            if (isQEssay)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Icon(
                                  LucideIcons.pencilLine,
                                  size: 8,
                                  color: textColor.withOpacity(0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              // ── Question Body ───────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question image
                      if (imageFileId != null && imageFileId.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            final imageUrl =
                                '$_baseUrl/api/exams/get-image?file_id=$imageFileId';
                            _showZoomableImage(imageUrl);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            constraints: const BoxConstraints(maxHeight: 250),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
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
                                        const Icon(Icons.error,
                                            color: AppColors.error),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius:
                                            BorderRadius.circular(4)),
                                    child: const Icon(LucideIcons.maximize2,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Question type badge
                      if (isEssay)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.writtenQuestionBadge,
                            style: TextStyle(
                                color: AppColors.accentYellow,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0),
                          ),
                        ),

                      Text(
                        questionData['question_text'] ?? AppLocalizations.of(context)!.questionTextFallback,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            height: 1.4),
                      ),

                      const SizedBox(height: 32),

                      // Essay OR MCQ widget
                      if (isEssay)
                        _buildEssayQuestion(questionId, currentIdx)
                      else
                        ...options.map((opt) {
                          final int optId = opt['id'];
                          bool isSelected = false;
                          bool isCorrectModel = false;

                          if (_isModelAnswerMode) {
                            isCorrectModel = opt['is_correct'] == true;
                          } else {
                            isSelected = userMcqAnswers[questionId] == optId;
                          }

                          Color bgColor = AppColors.backgroundSecondary;
                          Color borderColor = Colors.white.withOpacity(0.05);

                          if (_isModelAnswerMode && isCorrectModel) {
                            bgColor = AppColors.success.withOpacity(0.2);
                            borderColor = AppColors.success;
                          } else if (isSelected) {
                            bgColor =
                                AppColors.accentYellow.withOpacity(0.1);
                            borderColor = AppColors.accentYellow;
                          }

                          return GestureDetector(
                            onTap: () {
                              if (_isModelAnswerMode) return;
                              setState(
                                  () => userMcqAnswers[questionId] = optId);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: borderColor,
                                  width:
                                      (isSelected || isCorrectModel) ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: (isSelected || isCorrectModel)
                                              ? (_isModelAnswerMode &&
                                                      isCorrectModel
                                                  ? AppColors.success
                                                  : AppColors.accentYellow)
                                              : Colors.white24,
                                          width: 2),
                                      color: (isSelected || isCorrectModel)
                                          ? (_isModelAnswerMode &&
                                                  isCorrectModel
                                              ? AppColors.success
                                              : AppColors.accentYellow)
                                          : Colors.transparent,
                                    ),
                                    child: (isSelected || isCorrectModel)
                                        ? Icon(Icons.check,
                                            size: 16,
                                            color:
                                                AppColors.backgroundPrimary)
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      opt['option_text'],
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: (isSelected ||
                                                isCorrectModel)
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: (isSelected || isCorrectModel)
                                            ? AppColors.textPrimary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),

              // ── Navigation Buttons ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white10))),
                child: Row(
                  children: [
                    if (currentIdx > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => currentIdx--),
                          style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: Colors.white10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          child: Text(AppLocalizations.of(context)!.backButton,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    if (currentIdx > 0) const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          if (currentIdx == _questions.length - 1) {
                            if (_isModelAnswerMode) {
                              Navigator.pop(context);
                            } else {
                              _submitExam();
                            }
                          } else {
                            setState(() => currentIdx++);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _isModelAnswerMode
                                ? Colors.grey[800]
                                : AppColors.accentYellow,
                            foregroundColor: _isModelAnswerMode
                                ? Colors.white
                                : AppColors.backgroundPrimary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        child: Text(
                            currentIdx == _questions.length - 1
                                ? (_isModelAnswerMode ? AppLocalizations.of(context)!.examCloseButton : AppLocalizations.of(context)!.examFinishButton)
                                : AppLocalizations.of(context)!.examNextButton,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
