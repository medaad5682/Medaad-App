import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';

class ExamResultScreen extends StatefulWidget {
  final String attemptId;
  final String examTitle;
  // ✅ حقل النتائج المباشرة الممررة من شاشة الامتحان (لحالة التدريب)
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
  final String _appSecret = const String.fromEnvironment('APP_SECRET');
  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("View Result: ${widget.attemptId}");
    
    // ✅ التحقق: إذا كانت النتائج ممررة مسبقاً (وضع التدريب)، نستخدمها مباشرة ولا نطلبها من السيرفر
    if (widget.practiceResults != null) {
      setState(() {
        _resultData = widget.practiceResults;
        _loading = false;
      });
    } else {
      _fetchResults();
    }
  }

  Future<void> _fetchResults() async {
    try {
      var box = await StorageService.openBox('auth_box');
      _userId = box.get('user_id');
      _deviceId = box.get('device_id');
      _token = box.get('jwt_token'); 

      // ✅ الاعتماد على ApiClient دون تمرير الـ Headers يدوياً
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/exams/get-results',
        queryParameters: {'attemptId': widget.attemptId},
      );

      if (mounted && res.statusCode == 200) {
        setState(() {
          _resultData = res.data;
          _loading = false;
        });

        // تخزين النتيجة محلياً للرجوع إليها لاحقاً
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
                  // ✅ نترك الهيدرز هنا لأن CachedNetworkImage لا يستخدم الـ ApiClient الخاص بنا
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
            child: Text("Failed to load results",
                style: TextStyle(color: AppColors.error))),
      );
    }

    // ✅ دعم هيكل الرد الموحد (وضع التدريب يرسل الحقول مباشرة أو داخل score_details)
    final scoreDetails = _resultData!['score_details'] ?? _resultData!; 
    final List questions = _resultData!['corrected_questions'] ?? [];
    final double percentage = (scoreDetails['percentage'] ?? 0) / 100.0;
    final bool isPractice = _resultData!['is_practice'] == true;

    Color statusColor = percentage >= 0.5 ? AppColors.success : AppColors.error;
    String statusMsg = percentage >= 0.5 ? "PASSED" : "FAILED";

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(isPractice ? "PRACTICE RESULT" : "EXAM RESULTS",
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
            // 💡 تنبيه في حالة التدريب
            if (isPractice)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accentYellow.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, color: AppColors.accentYellow, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "هذه نتيجة تدريبية (Practice Mode). لم يتم حفظ هذه النتيجة في سجل درجاتك الدائم.",
                        style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. ملخص النتيجة
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
                    percent: percentage,
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
                  const SizedBox(height: 8),
                  Text(
                      "Score: ${scoreDetails['score']} / ${scoreDetails['total']}",
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 32),
            
            // ✅ عرض التحليل التفصيلي (الأسئلة والإجابات)
            if (questions.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text("DETAILED ANALYSIS",
                    style: TextStyle(
                        color: AppColors.accentYellow,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(height: 16),

              ...List.generate(questions.length, (index) {
                final q = questions[index];
                final userAnsId = q['user_answer']?['selected_option_id'];
                final correctOptId = q['correct_option_id'];
                final bool isCorrect = userAnsId == correctOptId;
                final String? imageFileId = q['image_file_id'];

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
                              color:
                                  isCorrect ? AppColors.success : AppColors.error,
                              size: 20),
                          const SizedBox(width: 10),
                          Text("Question ${index + 1}",
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
                                },
                                placeholder: (context, url) => Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accentYellow)),
                                errorWidget: (context, url, error) => const Icon(
                                    Icons.error,
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

                      // عرض الخيارات وتحديد الصحيح منها وما اختاره الطالب
                      ...(q['options'] as List).map((opt) {
                        final bool isSelected = opt['id'] == userAnsId;
                        final bool isTheCorrectOne = opt['id'] == correctOptId;

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
