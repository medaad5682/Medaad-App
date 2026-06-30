import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'checkout_screen.dart';
import 'teacher_profile_screen.dart';
import 'login_screen.dart'; // ✅ استيراد صفحة الدخول
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';

class CourseDetailsScreen extends StatefulWidget {
  final String courseCode;
  const CourseDetailsScreen({super.key, required this.courseCode});

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _courseData;
  List<String> _selectedSubjectIds = [];
  bool _isFullCourse = false;
  final String _baseUrl = ApiConstants.baseUrl;

  bool _isTeacher = false;
  bool _isFreeMode = false; // ✅ متغير الوضع المجاني
  bool _enrolling = false; // ✅ حالة التحميل عند التفعيل

  // 🔒 كلمة السر المتطابقة مع الباك اند
  static const String _activationSecret = "Medaad_Free_Activation_2026_Secure";

  @override
  void initState() {
    super.initState();
    _checkAccess(); // ✅ التحقق من الصلاحيات والوضع
  }

  Future<void> _checkAccess() async {
    var box = await StorageService.openBox('auth_box');

    // 1. التحقق من الزائر (Guest Check)
    bool isGuest = box.get('is_guest', defaultValue: false);
    if (isGuest) {
      if (mounted) {
        // توجيه الزائر لصفحة الدخول فوراً
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
      return;
    }

    // 2. التحقق من الدور والوضع المجاني
    String? role = box.get('role');
    bool freeMode = box.get('free_mode', defaultValue: false);

    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
        _isFreeMode = freeMode;
      });
      _fetchDetails();
    }
  }

  Future<void> _fetchDetails() async {
    try {
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/public/get-course-sales-details',
        queryParameters: {'courseCode': widget.courseCode},
      );

      if (mounted) {
        setState(() {
          _courseData = res.data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ✅ دالة التفعيل المجاني المباشر (تم تأمينها هنا)
  Future<void> _enrollFree() async {
    setState(() => _enrolling = true);
    try {
      var box = await StorageService.openBox('auth_box');
      String? userId = box.get('user_id');

      // تجهيز البيانات المختارة
      List<Map<String, dynamic>> selectedItems = [];
      if (_isFullCourse) {
        selectedItems.add({'id': _courseData!['id'], 'type': 'course'});
      } else {
        for (var sub in _courseData!['subjects']) {
          if (_selectedSubjectIds.contains(sub['id'].toString())) {
            selectedItems.add({'id': sub['id'], 'type': 'subject'});
          }
        }
      }

      if (selectedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context)!.selectItemsFirstError)));
        setState(() => _enrolling = false);
        return;
      }

      final res = await ApiClient.instance.post(
        '$_baseUrl/api/student/enroll-free', // تأكد أن هذا المسار موجود في الباك اند
        data: {'items': selectedItems},
        options: Options(headers: {
          'x-user-id': userId, // ✅ الاحتفاظ بهيدر المعرف
          'x-free-secret': _activationSecret, // ✅ الاحتفاظ بهيدر التفعيل المجاني
        }),
      );

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.activationSuccessMessage),
            backgroundColor: AppColors.success));
        // إعادة تحميل الصفحة لتحديث الحالة إلى المملوكة
        _fetchDetails();
        setState(() {
          _selectedSubjectIds.clear();
          _isFullCourse = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.activationFailedMessage),
          backgroundColor: AppColors.error));
    } finally {
      setState(() => _enrolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_courseData == null)
      return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: Text(AppLocalizations.of(context)!.courseNotFound,
                  style: TextStyle(color: AppColors.textPrimary))));

    final course = _courseData!;
    final teacher = course['teacher'] ?? {};
    final String teacherName =
        teacher['name'] ?? AppLocalizations.of(context)!.unknownInstructor;
    final String? teacherIdString = teacher['id']?.toString();

    final subjects = List<Map<String, dynamic>>.from(course['subjects'] ?? []);
    final double fullPrice = (course['price'] ?? 0).toDouble();

    bool allSubjectsOwned = false;
    if (subjects.isNotEmpty) {
      allSubjectsOwned = subjects.every((s) => s['isOwned'] == true);
    }

    bool isCourseOwned = (course['isOwned'] ?? false) || allSubjectsOwned;

    double currentPrice = _isFullCourse
        ? fullPrice
        : subjects
            .where((s) => _selectedSubjectIds.contains(s['id'].toString()))
            .fold(0, (sum, s) => sum + (s['price'] ?? 0));

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header & Back
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(LucideIcons.arrowLeft,
                                  color: AppColors.accentYellow, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Title & Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "#${course['code']}",
                          style: const TextStyle(
                              color: AppColors.accentOrange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        course['title'].toString().toUpperCase(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Instructor Card
                      GestureDetector(
                        onTap: () {
                          if (teacherIdString != null &&
                              teacherIdString.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TeacherProfileScreen(
                                    teacherId: teacherIdString),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(AppLocalizations.of(context)!
                                      .instructorProfileUnavailable)),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundPrimary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.accentOrange
                                          .withOpacity(0.5)),
                                ),
                                child: const Icon(LucideIcons.user,
                                    color: AppColors.accentOrange, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!
                                        .instructorLabel,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    teacherName,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Icon(LucideIcons.chevronRight,
                                  size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                      Text(
                        course['description'] ??
                            AppLocalizations.of(context)!
                                .noDescriptionAvailable,
                        style: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.8),
                            height: 1.6,
                            fontSize: 14),
                      ),

                      const SizedBox(height: 40),

                      // ✅ للمعلمين: إخفاء كل شيء
                      if (_isTeacher)
                        Container(
                          padding: const EdgeInsets.all(24),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              Icon(LucideIcons.lock,
                                  color: AppColors.textSecondary, size: 32),
                              const SizedBox(height: 12),
                              Text(
                                AppLocalizations.of(context)!
                                    .teacherAccountLabel,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.of(context)!
                                    .teachersCannotPurchaseMessage,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // ✅ تغيير النص ليكون عاماً
                        Text(
                            _isFreeMode
                                ? AppLocalizations.of(context)!
                                    .courseContentLabel
                                : AppLocalizations.of(context)!
                                    .purchaseOptionsLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentYellow,
                                letterSpacing: 2.0)),
                        const SizedBox(height: 20),

                        // 1. Full Course Option
                        if (!isCourseOwned)
                          GestureDetector(
                            onTap: () => setState(() {
                              _isFullCourse = !_isFullCourse;
                              _selectedSubjectIds.clear();
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isFullCourse
                                      ? AppColors.accentYellow
                                      : Colors.transparent,
                                  width: _isFullCourse ? 2 : 1,
                                ),
                                boxShadow: _isFullCourse
                                    ? [
                                        BoxShadow(
                                            color: AppColors.accentYellow
                                                .withOpacity(0.2),
                                            blurRadius: 15)
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // ✅ نصوص عامة
                                      Text(
                                          _isFreeMode
                                              ? AppLocalizations.of(context)!
                                                  .fullCourseLabel
                                              : AppLocalizations.of(context)!
                                                  .fullCourseAccessLabel,
                                          style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(
                                          AppLocalizations.of(context)!
                                              .accessAllSubjectsExams,
                                          style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11)),
                                    ],
                                  ),
                                  // ✅ إخفاء السعر
                                  if (!_isFreeMode)
                                    Text(
                                        AppLocalizations.of(context)!
                                            .priceEgp(fullPrice.toString()),
                                        style: TextStyle(
                                            color: AppColors.accentYellow,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18)),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(24),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.success.withOpacity(0.5)),
                            ),
                            child: Column(
                              children: [
                                Icon(LucideIcons.checkCircle,
                                    color: AppColors.success, size: 32),
                                const SizedBox(height: 8),
                                Text(
                                    AppLocalizations.of(context)!
                                        .courseOwnedLabel,
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5)),
                              ],
                            ),
                          ),

                        if (subjects.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Text(
                              AppLocalizations.of(context)!
                                  .individualSubjectsLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 2.0)),
                          const SizedBox(height: 16),

                          // 2. Individual Subjects List
                          ...subjects.map((sub) {
                            bool isOwned = sub['isOwned'] ?? false;
                            bool isSelected = _selectedSubjectIds
                                .contains(sub['id'].toString());

                            return GestureDetector(
                              onTap: (isOwned || isCourseOwned)
                                  ? null
                                  : () {
                                      setState(() {
                                        _isFullCourse = false;
                                        if (isSelected) {
                                          _selectedSubjectIds
                                              .remove(sub['id'].toString());
                                        } else {
                                          _selectedSubjectIds
                                              .add(sub['id'].toString());
                                        }
                                      });
                                    },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 18),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary
                                      .withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.accentOrange
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (!isOwned && !isCourseOwned)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 16),
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: isSelected
                                                  ? AppColors.accentOrange
                                                  : AppColors.textSecondary
                                                      .withOpacity(0.5),
                                              width: 2),
                                          color: isSelected
                                              ? AppColors.accentOrange
                                              : Colors.transparent,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        sub['title'],
                                        style: TextStyle(
                                          color: (isOwned || isCourseOwned)
                                              ? AppColors.textSecondary
                                              : AppColors.textPrimary,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          decoration: (isOwned || isCourseOwned)
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (isOwned || isCourseOwned)
                                      Text(
                                          AppLocalizations.of(context)!
                                              .ownedLabel,
                                          style: TextStyle(
                                              color: AppColors.success,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold))
                                    else if (!_isFreeMode) // ✅ إخفاء السعر هنا
                                      Text(
                                          AppLocalizations.of(context)!
                                              .priceEgp(
                                                  sub['price'].toString()),
                                          style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ], // نهاية else (not teacher)
                    ],
                  ),
                ),
              ),
            ],
          ),

          // --- Bottom Action Bar ---
          // يظهر الشريط إذا تم اختيار عناصر (أو الوضع الطبيعي) وليس معلماً
          if (((_isFullCourse || _selectedSubjectIds.isNotEmpty) ||
                  !_isFreeMode) &&
              !_isTeacher)
            if (currentPrice > 0 ||
                _isFreeMode) // شرط إضافي: إما هناك سعر (عادي) أو وضع مجاني
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(
                        top: BorderSide(
                            color: AppColors.textSecondary.withOpacity(0.1))),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, -5))
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // القسم الأيسر: السعر أو رسالة التفعيل
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_isFreeMode) ...[
                            Text(
                                AppLocalizations.of(context)!
                                    .totalPayableLabel,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5)),
                            const SizedBox(height: 4),
                            Text(
                                AppLocalizations.of(context)!
                                    .priceEgp(currentPrice.toString()),
                                style: TextStyle(
                                    color: AppColors.accentYellow,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900)),
                          ] else
                            Text(
                                AppLocalizations.of(context)!
                                    .freeActivationLabel,
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                        ],
                      ),

                      // الزر: إما Checkout أو Activate
                      ElevatedButton(
                        onPressed: _enrolling
                            ? null
                            : () {
                                // ✅ 1. الوضع المجاني: تفعيل مباشر
                                if (_isFreeMode) {
                                  _enrollFree();
                                }
                                // ✅ 2. الوضع العادي: الذهاب للدفع
                                else {
                                  List<Map<String, dynamic>> selectedItems = [];
                                  if (_isFullCourse) {
                                    selectedItems.add({
                                      'id': course['id'],
                                      'type': 'course',
                                      'title': course['title'],
                                      'price': fullPrice
                                    });
                                  } else {
                                    for (var sub in subjects) {
                                      if (_selectedSubjectIds
                                          .contains(sub['id'].toString())) {
                                        selectedItems.add({
                                          'id': sub['id'],
                                          'type': 'subject',
                                          'title': sub['title'],
                                          'price': sub['price']
                                        });
                                      }
                                    }
                                  }

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CheckoutScreen(
                                        amount: currentPrice,
                                        paymentInfo: Map<String, dynamic>.from(
                                            course['paymentInfo'] ?? {}),
                                        selectedItems: selectedItems,
                                        teacherId: teacher['id'],
                                      ),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFreeMode
                              ? AppColors.success
                              : AppColors.accentYellow, // لون مختلف
                          foregroundColor: AppColors.backgroundPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _enrolling
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Row(
                                children: [
                                  Text(
                                      _isFreeMode
                                          ? AppLocalizations.of(context)!
                                              .activateButton
                                          : AppLocalizations.of(context)!
                                              .checkoutButton,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          letterSpacing: 1.0)),
                                  const SizedBox(width: 8),
                                  Icon(
                                      _isFreeMode
                                          ? LucideIcons.unlock
                                          : LucideIcons.arrowRight,
                                      size: 18),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
