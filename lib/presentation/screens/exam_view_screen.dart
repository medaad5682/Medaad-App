import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';
import 'exam_result_screen.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';

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

  // متغير لتحديد ما إذا كنا في وضع "نموذج الإجابة"
  bool _isModelAnswerMode = false;

  int currentIdx = 0;
  Map<String, int> userAnswers = {};

  // قائمة لتخزين الأسئلة التي تم وضع علامة عليها (Flagged)
  Set<String> flaggedQuestions = {};

  int timeLeft = 0;
  Timer? _timer;
  String? _attemptId;

  String? _userId;
  String? _deviceId;
  String? _token;
  final String _appSecret = const String.fromEnvironment('APP_SECRET');

  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Opened Exam: ${widget.examId}");
    _startExamAttempt();
  }

  Future<void> _startExamAttempt() async {
    try {
      // جلب البيانات الأساسية من التخزين المحلي لاستخدامها إذا لزم الأمر (مثل الصور)
      var box = await StorageService.openBox('auth_box');
      _userId = box.get('user_id');
      _deviceId = box.get('device_id');
      _token = box.get('jwt_token');
      final name = box.get('first_name') ?? 'Student';

      // تم الاعتماد على ApiClient ولن نحتاج لتمرير الـ Headers يدوياً
      final res = await ApiClient.instance.post(
        '$_baseUrl/api/exams/start-attempt',
        data: {'examId': widget.examId, 'studentName': name},
      );

      if (mounted && res.statusCode == 200) {
        final data = res.data;

        // التحقق من وضع نموذج الإجابة
        if (data['mode'] == 'model_answer') {
          setState(() {
            _isModelAnswerMode = true;
            _questions = data['questions'] ?? [];
            timeLeft = 0;
            _loading = false;
          });
        } else {
          // الوضع الطبيعي (بدء امتحان أو إعادة تدريب)
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
        String msg = "Failed to start exam";
        if (e is DioException) {
          if (e.response?.statusCode == 403)
            msg = e.response?.data['error'] ?? "Access Denied";
          if (e.response?.statusCode == 409) msg = "Exam already completed";
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return "0:00";
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    // في وضع نموذج الإجابة، هذا الزر يعمل كزر خروج فقط
    if (_isModelAnswerMode) {
      Navigator.pop(context);
      return;
    }

    // منع تسليم الامتحان إذا كانت هناك أسئلة فارغة (إلا في حالة انتهاء الوقت autoSubmit)
    if (!autoSubmit) {
      if (userAnswers.length < _questions.length) {
        int unanswered = _questions.length - userAnswers.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Cannot submit yet. You have $unanswered unanswered questions!",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
        return; // إيقاف العملية
      }
    }

    _timer?.cancel();

    // إظهار Loading
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
            child: CircularProgressIndicator(color: AppColors.accentYellow)));

    try {
      Map<String, int> finalAnswers = {};
      userAnswers.forEach((k, v) => finalAnswers[k] = v);

      // تم الاعتماد على ApiClient وإزالة الـ Headers اليدوية
      final res = await ApiClient.instance.post(
        '$_baseUrl/api/exams/submit-attempt',
        data: {
          'attemptId': _attemptId, 
          'answers': finalAnswers,
          'examId': widget.examId, // مهم جداً لوضع التدريب (temp_retake_mode)
        },
      );

      if (mounted) {
        Navigator.pop(context); // إغلاق Loading
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
              attemptId: _attemptId!, 
              examTitle: widget.examTitle,
              // ✅ تمرير النتائج مباشرة إذا كان في وضع التدريب لتجنب الفشل في جلبها من السيرفر
              practiceResults: _attemptId == 'temp_retake_mode' ? res.data : null,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Failed to submit. Try again."),
            backgroundColor: AppColors.error));
      }
    }
  }

  // دالة لإظهار تحذير الخروج
  Future<void> _showExitWarningDialog() async {
    final shouldSubmit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text("Exit Exam?",
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
            "Leaving the exam screen now will AUTOMATICALLY SUBMIT your current answers and you cannot return.\n\nAre you sure?",
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // البقاء في الامتحان
            child:
                Text("Stay", style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), // تسليم وخروج
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Submit & Exit",
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

  // دالة لتكبير الصورة
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
                // نترك الهيدرز هنا لأن CachedNetworkImage لا يستخدم Dio (بالتالي لا يمر على الـ Interceptor)
                httpHeaders: {
                  'Authorization': 'Bearer $_token',
                  'x-device-id': _deviceId ?? '',
                  'x-app-secret': _appSecret,
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

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow)));

    final questionData = _questions[currentIdx];
    final String questionId = questionData['id'].toString();
    final String? imageFileId = questionData['image_file_id'];
    final options =
        (questionData['options'] as List).cast<Map<String, dynamic>>();

    // التحقق مما إذا كان السؤال الحالي معلم عليه
    bool isFlagged = flaggedQuestions.contains(questionId);

    return PopScope(
      canPop:
          _isModelAnswerMode, // السماح بالخروج مباشرة فقط إذا كان نموذج إجابة
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // إذا حاول المستخدم الخروج أثناء الامتحان، نعرض التحذير
        await _showExitWarningDialog();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          child: Column(
            children: [
              // Header & Timer & Flag
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // زر وضع العلامة (Flag)
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
                        tooltip: "Mark Question",
                      ),

                    Text("Q ${currentIdx + 1}/${_questions.length}",
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
                        child: Text("MODEL ANSWER",
                            style: TextStyle(
                                color: AppColors.accentYellow,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),

              // شريط التنقل بين الأسئلة (Horizontal Navigator)
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

                    bool isCurrent = index == currentIdx;
                    bool isAnswered = userAnswers.containsKey(qIdStr);
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
                              color: borderColor, width: isMarked ? 2.0 : 1.5),
                        ),
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                // أيقونة صغيرة لتوضيح إمكانية التكبير
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Icon(LucideIcons.maximize2,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      Text(
                        questionData['question_text'] ?? "Question Text",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            height: 1.4),
                      ),

                      const SizedBox(height: 32),

                      // الخيارات
                      ...options.map((opt) {
                        final int optId = opt['id'];

                        bool isSelected = false;
                        bool isCorrectModel = false;

                        if (_isModelAnswerMode) {
                          isCorrectModel = opt['is_correct'] == true;
                        } else {
                          isSelected = userAnswers[questionId] == optId;
                        }

                        Color bgColor = AppColors.backgroundSecondary;
                        Color borderColor = Colors.white.withOpacity(0.05);

                        if (_isModelAnswerMode && isCorrectModel) {
                          bgColor = AppColors.success.withOpacity(0.2);
                          borderColor = AppColors.success;
                        } else if (isSelected) {
                          bgColor = AppColors.accentYellow.withOpacity(0.1);
                          borderColor = AppColors.accentYellow;
                        }

                        return GestureDetector(
                          onTap: () {
                            if (_isModelAnswerMode) return;
                            setState(() => userAnswers[questionId] = optId);
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
                                width: (isSelected || isCorrectModel) ? 1.5 : 1,
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
                                        ? (_isModelAnswerMode && isCorrectModel
                                            ? AppColors.success
                                            : AppColors.accentYellow)
                                        : Colors.transparent,
                                  ),
                                  child: (isSelected || isCorrectModel)
                                      ? Icon(Icons.check,
                                          size: 16,
                                          color: AppColors.backgroundPrimary)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    opt['option_text'],
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: (isSelected || isCorrectModel)
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

              // أزرار التنقل
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
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: Colors.white10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          child: Text("BACK",
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        child: Text(
                            currentIdx == _questions.length - 1
                                ? (_isModelAnswerMode ? "CLOSE" : "FINISH")
                                : "NEXT",
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
