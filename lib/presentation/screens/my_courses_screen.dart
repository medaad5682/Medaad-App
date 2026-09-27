import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
// ✅ إضافة استيراد خدمة المدرس
import '../../core/services/teacher_service.dart';
import 'course_materials_screen.dart';
import 'login_screen.dart';
import 'teacher/manage_content_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

// 📦 صف واحد في قائمة المكتبة المسطّحة: إما مجلد باقة، كورس/مجموعة مواد
// منفردة، أو صف "مجموعة كورسات باقة مفتوحة" (يُرسم بخط شجرة متصل واحد).
class _LibraryRow {
  final Map<String, dynamic>? packageItem;
  final Map<String, dynamic>? courseItem;
  final List<Map<String, dynamic>>? nestedCourses;

  _LibraryRow.package(Map<String, dynamic> item)
      : packageItem = item,
        courseItem = null,
        nestedCourses = null;

  _LibraryRow.course(Map<String, dynamic> item)
      : packageItem = null,
        courseItem = item,
        nestedCourses = null;

  _LibraryRow.nestedGroup(List<Map<String, dynamic>> courses)
      : packageItem = null,
        courseItem = null,
        nestedCourses = courses;
}

class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  bool _isTeacher = false;
  bool _isUpdating = false;
  bool _isFreeMode = false; // ✅ متغير لحفظ حالة الوضع المجاني

  // 📦 معرّفات مجلدات الباقات المفتوحة حالياً (أكورديون) — بدون شاشة
  // منفصلة، بمجرد الضغط على مجلد باقة تُضاف/تُحذف هنا وتظهر/تختفي
  // كورساتها كصفوف فرعية أسفل المجلد مباشرة في نفس القائمة.
  final Set<String> _expandedPackageIds = {};

  // ✅ تعريف خدمة المدرس
  final TeacherService _teacherService = TeacherService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    bool freeMode =
        box.get('free_mode', defaultValue: false); // ✅ قراءة الوضع من التخزين

    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
        _isFreeMode = freeMode; // ✅ تحديث الحالة
      });
    }
  }

  // ✅ منطق التحديث المعدل (الحل الجذري للمشكلة)
  Future<void> _refreshData() async {
    if (mounted) setState(() => _isUpdating = true); // إظهار التحميل فوراً

    try {
      // 1. إذا كان المستخدم مدرساً، نجبر التطبيق على جلب أحدث محتوى له من السيرفر وتحديث الكاش
      if (_isTeacher) {
        try {
          final updatedContent = await _teacherService.getMyContent();
          var box = await StorageService.openBox('teacher_data');
          await box.put('my_content', updatedContent);
        } catch (e) {
          debugPrint("Failed to refresh teacher content: $e");
        }
      }

      // 2. إعادة تحميل حالة التطبيق العامة (والتي ستقرأ الآن الكاش المحدث)
      await AppState().reloadAppInit();
    } catch (e) {
      debugPrint("Error refreshing data: $e");
    } finally {
      // 3. إخفاء التحميل وإعادة بناء الواجهة
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppState().isGuest) {
      return _buildGuestView();
    }
    return _buildLibraryView();
  }

  // --- 2. واجهة خاصة بالضيف ---
  Widget _buildGuestView() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Icon(LucideIcons.lock,
                            color: AppColors.textSecondary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.libraryTitle,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!.guestModeLabel,
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Login Required Message
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.shieldAlert,
                        size: 64,
                        color: AppColors.textSecondary.withOpacity(0.2)),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.loginRequiredTitle,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.loginRequiredMessage,
                      style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.7),
                          fontSize: 12),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true)
                            .pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.loginNowButton,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
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

  // --- 3. واجهة المكتبة ---
  Widget _buildLibraryView() {
    // استخدام البيانات من الحالة العامة
    final libraryItems = AppState().myLibrary;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Icon(LucideIcons.bookOpen,
                            color: AppColors.accentYellow, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.libraryTitle,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!.myLessonsSubtitle,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Buttons
                  Row(
                    children: [
                      // 🟢 زر إضافة كورس (للمدرس)
                      if (_isTeacher) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageContentScreen(
                                    contentType: ContentType.course),
                              ),
                            ).then((value) {
                              // ✅ عند العودة بنجاح (value == true)، نقوم بالتحديث
                              if (value == true) {
                                _refreshData();
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.accentYellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color:
                                      AppColors.accentYellow.withOpacity(0.5)),
                            ),
                            child: Icon(LucideIcons.plusSquare,
                                color: AppColors.accentYellow, size: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (_isUpdating)
              Expanded(
                child: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.accentYellow),
                ),
              )
            else
              Expanded(
                child: libraryItems.isEmpty
                    ? Center(
                        child: Text(
                          AppLocalizations.of(context)!.noActiveCourses,
                          style: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      )
                    : Builder(builder: (context) {
                        // 📦 نبني قائمة "مسطّحة": كل عنصر مجلد باقة يتبعه
                        // مباشرة صف واحد يحتوي كل كورساتها معاً (بخط شجرة
                        // متصل واحد) إن كان مفتوحاً (أكورديون) — بدون أي
                        // تنقّل لشاشة جديدة، فقط توسيع/طي داخل نفس القائمة.
                        final rows = _flattenLibraryRows(libraryItems);

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];

                            if (row.packageItem != null) {
                              // 📦 مجلد باقة: يضم عدة كورسات/مواد مملوكة
                              // تابعة لنفس الباقة (تفعيل كامل أو جزئي) —
                              // تصميم مختلف عن بطاقة الكورس العادية، والضغط
                              // عليه يفتح/يطوي قائمة كورساتها في نفس المكان.
                              return _buildPackageFolderCard(row.packageItem!);
                            }

                            if (row.nestedCourses != null) {
                              return _buildNestedCoursesGroup(row.nestedCourses!);
                            }

                            return _buildCourseCard(row.courseItem!);
                          },
                        );
                      }),
              ),
          ],
        ),
      ),
    );
  }

  // 📦 يحوّل عناصر المكتبة إلى قائمة "مسطّحة" من الصفوف: كل عنصر مجلد باقة
  // يتبعه مباشرة صف واحد يضم كل كورساتها معاً (إن كان مفتوحاً حالياً) —
  // هذا ما يصنع شكل الأكورديون (الطي/الفتح) بخط شجرة متصل واحد، بدلاً من
  // خط منفصل لكل بطاقة.
  List<_LibraryRow> _flattenLibraryRows(List<Map<String, dynamic>> items) {
    final List<_LibraryRow> rows = [];
    for (final item in items) {
      if (item['type'] == 'package') {
        rows.add(_LibraryRow.package(item));
        if (_expandedPackageIds.contains(item['id'].toString()) &&
            item['courses'] is List) {
          final nestedCourses = (item['courses'] as List)
              .whereType<Map>()
              .map((c) => Map<String, dynamic>.from(c))
              .toList();
          if (nestedCourses.isNotEmpty) {
            rows.add(_LibraryRow.nestedGroup(nestedCourses));
          }
        }
      } else {
        rows.add(_LibraryRow.course(item));
      }
    }
    return rows;
  }

  // 🌳 صف كورسات باقة مفتوحة: خط شجرة رأسي واحد متصل يمتد على طول كل
  // الكورسات المتفرّعة منه معاً (بدل خط منفصل لكل بطاقة)، تماماً كأسلوب
  // الفصول المتفرعة من مادة.
  Widget _buildNestedCoursesGroup(List<Map<String, dynamic>> courses) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14),
              child: Container(
                width: 2,
                color: AppColors.accentYellow.withOpacity(0.25),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: courses
                    .map((c) => _buildCourseCard(c, nested: true))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بطاقة كورس عادية — تُستخدم لكورس منفرد في المكتبة، أو لكورس ظاهر تحت
  // مجلد باقة مفتوح عند nested=true — بنفس المنطق ونفس الفتح لـ
  // CourseMaterialsScreen، فقط بحجم أصغر (ارتفاع أقل) ليظهر بصرياً كـ"عنصر
  // داخل مجلد" أشبه بشكل الفصول. خط الشجرة الذي يصلها بالمجلد يُرسم مرة
  // واحدة لكل الكورسات معاً من _buildNestedCoursesGroup، وليس هنا.
  Widget _buildCourseCard(Map<String, dynamic> item, {bool nested = false}) {
    final String title = item['title'] ?? 'Unknown';
    final String instructor = item['instructor'] ?? 'Instructor';
    final String code = item['code']?.toString() ?? '';
    final String id = item['id'].toString();

    final String description = item['description'] ?? '';
    final double localPrice =
        double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;

    List<dynamic>? subjectsToPass;
    if (item['owned_subjects'] is List) {
      subjectsToPass = item['owned_subjects'];
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CourseMaterialsScreen(
              courseId: id,
              courseTitle: title,
              courseCode: code,
              instructorName: instructor,
              preLoadedSubjects: subjectsToPass,
            ),
          ),
        ).then((updatedSubjects) {
          if (updatedSubjects != null && updatedSubjects is List) {
            _updateOwnedSubjects(id, updatedSubjects);
          }
        });
      },
      child: Container(
        margin: EdgeInsets.only(bottom: nested ? 10 : 16),
        padding: EdgeInsets.all(nested ? 12 : 20),
        decoration: BoxDecoration(
          color: nested
              ? AppColors.backgroundPrimary
              : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(nested ? 14 : 24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: nested
              ? null
              : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              width: nested ? 34 : 48,
              height: nested ? 34 : 48,
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(nested ? 10 : 12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4)
                ],
              ),
              child: Icon(LucideIcons.playCircle,
                  color: AppColors.accentOrange, size: nested ? 16 : 24),
            ),
            SizedBox(width: nested ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (code.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppColors.accentOrange.withOpacity(0.2),
                            width: 0.5),
                      ),
                      child: Text(
                        "#$code",
                        style: TextStyle(
                          color: AppColors.accentOrange,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: nested ? 12 : 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!nested) ...[
                    const SizedBox(height: 4),
                    Text(
                      instructor.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 🟢 زر التعديل (داخل البطاقة)
            if (_isTeacher)
              GestureDetector(
                onTap: () {
                  double realPrice = localPrice;
                  try {
                    final freshCourse = AppState()
                        .allCourses
                        .firstWhere((c) => c.id == id);
                    realPrice = freshCourse.fullPrice;
                  } catch (_) {}

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageContentScreen(
                        contentType: ContentType.course,
                        initialData: {
                          'id': id,
                          'title': title,
                          'code': code,
                          'price': realPrice,
                          'fullPrice': realPrice,
                          'description': description,
                        },
                      ),
                    ),
                  ).then((value) {
                    if (value == true) {
                      _refreshData();
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.accentYellow.withOpacity(0.3)),
                  ),
                  child: Icon(LucideIcons.edit3,
                      color: AppColors.accentYellow, size: 18),
                ),
              )
            else
              DirectionalFlip(
                child: Icon(LucideIcons.chevronRight,
                    color: AppColors.textSecondary.withOpacity(0.6),
                    size: nested ? 16 : 20),
              ),
          ],
        ),
      ),
    );
  }

  // --- 5. بطاقة مجلد الباقة ---
  // تصميم مختلف عن بطاقة الكورس العادية: تدرج لوني + أيقونة صندوق مكدّسة +
  // شارة بعدد الكورسات، لتمييزها بصرياً كـ"مجلد" يضم عدة كورسات وليس كورساً
  // واحداً. تظهر لكل باقة يملك الطالب كورساً واحداً على الأقل منها (سواء
  // كانت الباقة مُفعّلة بالكامل أو جزئياً).
  Widget _buildPackageFolderCard(Map<String, dynamic> item) {
    final String title = item['title']?.toString() ?? 'Unknown';
    final String packageId = item['id'].toString();
    final List<dynamic> coursesInPackage =
        item['courses'] is List ? item['courses'] as List<dynamic> : [];
    final int courseCount = coursesInPackage.length;
    final bool isArabic = AppState.isArabic;
    final bool isExpanded = _expandedPackageIds.contains(packageId);
    final String subtitle = isArabic
        ? '$courseCount كورس داخل الباقة'
        : '$courseCount COURSES IN THIS PACKAGE';

    return GestureDetector(
      // 📦 فتح/طي أكورديون: مجرد إضافة/حذف من مجموعة المعرّفات المفتوحة،
      // فتظهر كورسات الباقة كصفوف مباشرة أسفل هذا المجلد في نفس القائمة —
      // بدون أي تنقّل لشاشة جديدة.
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedPackageIds.remove(packageId);
          } else {
            _expandedPackageIds.add(packageId);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accentYellow.withOpacity(0.9),
              AppColors.accentOrange.withOpacity(0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentOrange.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              // أيقونة "مجلد مكدّس" لإيحاء أن هذا يضم عدة عناصر
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    Positioned(
                      left: 4,
                      top: 6,
                      child: Icon(LucideIcons.layers,
                          size: 22,
                          color: AppColors.accentYellow.withOpacity(0.35)),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.accentYellow.withOpacity(0.4)),
                        ),
                        child: Icon(LucideIcons.package,
                            color: AppColors.accentYellow, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isArabic ? 'باقة' : 'PACKAGE',
                        style: TextStyle(
                          color: AppColors.accentYellow,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              // ⬇️ السهم يتقلّب لأسفل عند الفتح، ويعود لليمين/اليسار (حسب
              // الاتجاه) عند الطي — نفس فكرة سهم مجلد الفصول.
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: DirectionalFlip(
                  child: Icon(LucideIcons.chevronRight,
                      color: AppColors.textSecondary.withOpacity(0.6),
                      size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // بعد فتح كورس تابع لباقة قد تتغير owned_subjects الخاصة به (مثلاً بعد
  // شراء مادة إضافية). نحدّثها هنا داخل نسخة الكورس المُخزّنة تحت مجلد
  // الباقة في AppState().myLibrary مباشرة، حتى تبقى متزامنة عند طي/فتح
  // المجلد دون الحاجة لإعادة تحميل init كامل.
  void _updateOwnedSubjects(String id, List<dynamic> updatedSubjects) {
    bool changed = false;
    for (var libItem in AppState().myLibrary) {
      if (libItem['type'] == 'package' && libItem['courses'] is List) {
        for (var course in libItem['courses']) {
          if (course is Map && course['id'].toString() == id) {
            course['owned_subjects'] = updatedSubjects;
            changed = true;
          }
        }
      } else if (libItem['id'].toString() == id) {
        libItem['owned_subjects'] = updatedSubjects;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }
}
