import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/constants/app_colors.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

class ExamStatsScreen extends StatefulWidget {
  final String examId;
  final String examTitle;

  const ExamStatsScreen({
    Key? key,
    required this.examId,
    required this.examTitle,
  }) : super(key: key);

  @override
  State<ExamStatsScreen> createState() => _ExamStatsScreenState();
}

class _ExamStatsScreenState extends State<ExamStatsScreen> {
  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
   
  // متغيرات البيانات
  double _averageScore = 0;       // متوسط الدرجات الرقمية (مثلاً 18.5)
  double _averagePercentage = 0;  // متوسط النسب المئوية (مثلاً 92.5)
  int _totalAttempts = 0;
  List<dynamic> _topStudents = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final data = await _teacherService.getExamStats(widget.examId);
      setState(() {
        // استقبال البيانات الجديدة من الـ API
        _averageScore = double.tryParse(data['averageScore']?.toString() ?? '0') ?? 0;
        _averagePercentage = double.tryParse(data['averagePercentage']?.toString() ?? '0') ?? 0;
        _totalAttempts = int.tryParse(data['totalAttempts']?.toString() ?? '0') ?? 0;
        _topStudents = data['topStudents'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(AppLocalizations.of(context)!.failedFetchStats(e.toString())), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.statisticsForTitle(widget.examTitle),
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)
        ),
        backgroundColor: AppColors.backgroundSecondary,
        iconTheme: IconThemeData(color: AppColors.accentYellow),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // --- بطاقات الملخص (Total Attempts & Average) ---
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: AppLocalizations.of(context)!.numberOfAttemptsLabel,
                          value: _totalAttempts.toString(),
                          icon: Icons.people_alt,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildStatCard(
                          title: AppLocalizations.of(context)!.averagePercentageLabel,
                          // عرض متوسط النسبة المئوية هنا لأنه الأهم للمعلم
                          value: "${_averagePercentage.toStringAsFixed(1)}%",
                          icon: Icons.analytics,
                          color: _averagePercentage >= 50 ? AppColors.success : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),

                  // --- قائمة الأوائل ---
                  Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Row(
                      children: [
                          Icon(Icons.emoji_events, color: AppColors.accentYellow),
                          const SizedBox(width: 8),
                          Text(
                           AppLocalizations.of(context)!.honorRollTitle,
                           style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                         ),
                      ],
                    ),
                  ),

                  if (_topStudents.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.hourglass_empty, size: 50, color: AppColors.textSecondary),
                          const SizedBox(height: 15),
                          Text(
                            AppLocalizations.of(context)!.noCompletedAttemptsYet,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _topStudents.length,
                      itemBuilder: (context, index) {
                        final student = _topStudents[index];
                        final isFirst = index == 0;
                        final isSecond = index == 1;
                        final isThird = index == 2;

                        // تحديد لون الكأس/الترتيب
                        Color rankColor;
                        if (isFirst) rankColor = const Color(0xFFFFD700); // ذهبي
                        else if (isSecond) rankColor = const Color(0xFFC0C0C0); // فضي
                        else if (isThird) rankColor = const Color(0xFFCD7F32); // برونزي
                        else rankColor = AppColors.backgroundPrimary;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: isFirst ? const Color(0xFFFFD700).withOpacity(0.5) : Colors.white10,
                              width: isFirst ? 1.5 : 1
                            ),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
                            ]
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: rankColor,
                              radius: 22,
                              child: Text(
                                "${index + 1}",
                                style: TextStyle(
                                  // ✅ تعديل لون النص بناءً على الخلفية لضمان القراءة
                                  color: (isFirst || isSecond || isThird) ? Colors.black87 : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16
                                ),
                              ),
                            ),
                            title: Text(
                              student['name'] ?? AppLocalizations.of(context)!.unknownStudentFallback,
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                // ✅ عرض التاريخ
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      student['date']?.toString().split('T')[0] ?? "",
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // ✅ عرض رقم الهاتف
                                Row(
                                  children: [
                                    Icon(Icons.phone_android, size: 12, color: AppColors.accentBlue),
                                    const SizedBox(width: 4),
                                    Text(
                                      student['phone'] ?? AppLocalizations.of(context)!.notAvailable,
                                      style: TextStyle(color: AppColors.accentBlue, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundPrimary,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.success.withOpacity(0.5)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min, // مهم لعدم تمدد الـ Column
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // ✅ عرض النسبة المئوية بخط عريض
                                  Text(
                                    "${student['percentage'] ?? 0}%",
                                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  // ✅ عرض الدرجة بخط أصغر
                                  Text(
                                    AppLocalizations.of(context)!.pointsSuffix((student['score'] ?? 0).toString()),
                                    style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            value, 
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)
          ),
          const SizedBox(height: 4),
          Text(
            title, 
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)
          ),
        ],
      ),
    );
  }
}
