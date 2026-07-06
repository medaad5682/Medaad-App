import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../data/models/course_model.dart'; // تأكد من استيراد الموديل الخاص بالكورس
import 'course_details_screen.dart';
import 'my_requests_screen.dart';
import 'teacher_profile_screen.dart';
import 'teacher/student_requests_screen.dart';
// ✅ 1. استيراد شاشة الإشعارات
import 'notifications_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchTerm = "";
  int _currentSlide = 0;
  late Timer _timer;
  final PageController _pageController = PageController();

  // جلب البيانات من مدير الحالة المركزي
  final _allCourses = AppState().allCourses;
  final _user = AppState().userData;
    
  // قائمة لتخزين الكورسات العشوائية
  List<dynamic> _randomCourses = []; 

  bool _isTeacher = false;

  // ✅ عدد الجمل التشجيعية ثابت (النصوص الفعلية تُبنى داخل build() لأنها تحتاج context للترجمة)
  static const int _encouragementsCount = 5;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _generateRandomCourses(); // توليد القائمة العشوائية عند بدء الشاشة

    // إعداد مؤقت السلايدر للنص التشجيعي
    _timer = Timer.periodic(const Duration(seconds: 8), (Timer timer) {
      if (_currentSlide < _encouragementsCount - 1) {
        _currentSlide++;
      } else {
        _currentSlide = 0;
      }
        
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentSlide,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // دالة لاختيار 5 كورسات عشوائية
  void _generateRandomCourses() {
    if (_allCourses.isNotEmpty) {
      // نأخذ نسخة من القائمة الأصلية حتى لا نعدل ترتيب البيانات الرئيسية
      var tempList = List.of(_allCourses);
      tempList.shuffle(); // خلط القائمة عشوائياً
      setState(() {
        _randomCourses = tempList.take(5).toList(); // أخذ أول 5 عناصر بعد الخلط
      });
    }
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

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // ✅ الجمل التشجيعية مبنية هنا لأنها تحتاج context للترجمة (راجع _encouragementsCount أعلاه)
    final List<String> encouragements = [
      l10n.encouragement1,
      l10n.encouragement2,
      l10n.encouragement3,
      l10n.encouragement4,
      l10n.encouragement5,
    ];

    // منطق العرض: إذا كان هناك بحث نستخدم _allCourses، وإلا نستخدم _randomCourses
    List<dynamic> coursesToDisplay;
      
    if (_searchTerm.isEmpty) {
      // إذا لم يكن هناك بحث، اعرض القائمة العشوائية التي جهزناها
      coursesToDisplay = _randomCourses;
      // حماية إضافية: إذا كانت القائمة العشوائية فارغة لسبب ما (مثل تحميل البيانات متأخراً)، أعد توليدها
      if (coursesToDisplay.isEmpty && _allCourses.isNotEmpty) {
         _generateRandomCourses();
         coursesToDisplay = _randomCourses;
      }
    } else {
      // إذا كان المستخدم يبحث، قم بالفلترة من القائمة الكاملة
      coursesToDisplay = _allCourses.where((course) => 
        course.title.toLowerCase().contains(_searchTerm.toLowerCase()) ||
        course.code.toLowerCase().contains(_searchTerm.toLowerCase())
      ).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header & Search Section ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary.withOpacity(0.8),
                border: const Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.homeWelcomeGreeting,
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (_user?['first_name'] ?? l10n.guestFallbackName)
                                .toString()
                                .toUpperCase(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                        
                      // ✅ 2. صف يحتوي على زر الإشعارات وزر الطلبات
                      Row(
                        children: [
                          // زر الإشعارات 🔔
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context, 
                                MaterialPageRoute(builder: (_) => const NotificationsScreen())
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Icon(
                                LucideIcons.bell,
                                color: AppColors.accentYellow, 
                                size: 22
                              ),
                            ),
                          ),
                          const SizedBox(width: 12), // المسافة بين الأزرار
                          
                          // زر الطلبات 📋
                          GestureDetector(
                            onTap: () {
                               if (_isTeacher) {
                                 Navigator.push(
                                   context, 
                                   MaterialPageRoute(builder: (_) => const StudentRequestsScreen())
                                 );
                               } else {
                                 Navigator.push(
                                   context, 
                                   MaterialPageRoute(builder: (_) => const MyRequestsScreen())
                                 );
                               }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Icon(
                                _isTeacher ? LucideIcons.inbox : LucideIcons.clipboardList,
                                color: AppColors.accentYellow, 
                                size: 22
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: TextField(
                      onChanged: (val) => setState(() => _searchTerm = val),
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          LucideIcons.search, 
                          color: _searchTerm.isNotEmpty ? AppColors.accentYellow : AppColors.textSecondary,
                          size: 18,
                        ),
                        hintText: l10n.searchCourseHint,
                        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- Scrollable Content ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Slider - تم تعديل الألوان هنا لتكون سوداء فوق الخلفية الرمادية
                    SizedBox(
                      height: 96,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300], // الإبقاء على لون الخلفية الرمادي
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 12, left: 16,
                              child: Icon(
                                LucideIcons.quote, 
                                color: Colors.black.withOpacity(0.2), // أيقونة الاقتباس بالأسود الشفاف
                                size: 32
                              ),
                            ),
                            PageView.builder(
                              controller: _pageController,
                              itemCount: encouragements.length,
                              onPageChanged: (idx) => setState(() => _currentSlide = idx),
                              itemBuilder: (context, index) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 32),
                                    child: Text(
                                      encouragements[index].toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.black, // النص باللون الأسود
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              bottom: 12,
                              left: 0, right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(encouragements.length, (index) {
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    width: _currentSlide == index ? 20 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _currentSlide == index 
                                          ? AppColors.accentYellow 
                                          : Colors.black.withOpacity(0.2), // نقاط التمرير بالأسود
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Section Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _searchTerm.isEmpty ? l10n.suggestedForYou : l10n.searchResults, 
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          l10n.activeLabel,
                          style: TextStyle(
                            color: AppColors.accentOrange,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Course List
                    coursesToDisplay.isEmpty 
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(l10n.noCoursesFound, style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5))),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: coursesToDisplay.length,
                        itemBuilder: (context, index) {
                          final course = coursesToDisplay[index];
                            
                          return GestureDetector(
                            onTap: () {
                               Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CourseDetailsScreen(courseCode: course.code),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: ID and Chevron
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentOrange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          "#${course.code}",
                                          style: TextStyle(
                                            color: AppColors.accentOrange,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                      DirectionalFlip(child: Icon(LucideIcons.chevronRight, color: AppColors.accentYellow, size: 20)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                    
                                  // Title
                                  Text(
                                    course.title.toUpperCase(),
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Teacher info (CLICKABLE)
                                  GestureDetector(
                                    onTap: () {
                                      if (course.teacherId.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TeacherProfileScreen(teacherId: course.teacherId)
                                          ),
                                        );
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        Icon(LucideIcons.userCircle, size: 14, color: AppColors.accentOrange),
                                        const SizedBox(width: 8),
                                        Text(
                                          course.instructorName.toUpperCase(),
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
