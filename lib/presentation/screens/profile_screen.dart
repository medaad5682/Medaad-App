import 'package:Medaad/core/services/widgets/restart_widget.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';

// ✅ استيراد main.dart للوصول لخاصية إعادة التشغيل
import '../../main.dart';

// شاشات الإعدادات العامة
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'dev_info_screen.dart';
import 'login_screen.dart';

// شاشات الطالب
import 'my_requests_screen.dart';

// شاشات المعلم
import 'teacher/student_requests_screen.dart';
import 'teacher/manage_students_screen.dart';
import 'teacher/manage_team_screen.dart';
import 'teacher/financial_stats_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final String _baseUrl = ApiConstants.baseUrl;
  bool _isTeacher = false;
  String? _profileImage; // ✅ متغير لتخزين رابط الصورة

  @override
  void initState() {
    super.initState();
    _loadUserData(); // ✅ تحميل البيانات
  }

  // ✅ تحميل بيانات المستخدم والصلاحية والصورة
  Future<void> _loadUserData() async {
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    String? image = box.get('profile_image'); // ✅ جلب الصورة المخزنة

    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
        _profileImage = image; // ✅ تعيين الصورة
      });
    }
  }

  // 🔥 دالة حذف الحساب (الجديدة)
  Future<void> _deleteAccount() async {
    // 1. إظهار نافذة تحذير (تأكيد الحذف)
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(
          "Delete Account",
          style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to delete your account? This action cannot be undone and you will lose all your subscriptions.",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel",
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Delete",
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 2. بدء عملية الحذف
    try {
      // إظهار مؤشر تحميل
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      var authBox = await StorageService.openBox('auth_box');
      final token = authBox.get('jwt_token');

      if (token != null) {
        // استدعاء API الحذف بالاعتماد على ApiClient
        await ApiClient.instance.delete(
          '$_baseUrl/api/student/delete-account',
          options: Options(
            validateStatus: (status) => status! < 500,
          ),
        );
      }

      // 3. تنظيف البيانات محلياً والخروج
      await authBox.clear();
      AppState().clear();

      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل

        // التوجيه لشاشة الدخول
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Account deleted successfully."),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error deleting account: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // دالة تسجيل الخروج
  Future<void> _logout() async {
    try {
      var authBox = await StorageService.openBox('auth_box');
      final token = authBox.get('jwt_token');

      // 1. إرسال طلب للسيرفر لحذف التوكن
      if (token != null) {
        try {
          // استدعاء API تسجيل الخروج بالاعتماد على ApiClient
          await ApiClient.instance.post(
            '$_baseUrl/api/auth/logout',
            options: Options(
              validateStatus: (status) => status! < 500,
              sendTimeout: const Duration(seconds: 3),
            ),
          );
        } catch (e) {
          debugPrint("Server Logout Warning: $e");
        }
      }

      // 2. مسح البيانات محلياً
      await authBox.clear();

      // 3. مسح الذاكرة
      AppState().clear();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("Local Logout Error: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // ✅ دالة لتغيير الثيم وإعادة تشغيل التطبيق
  void _toggleThemeAndRestart() async {
    await AppState().toggleTheme();

    // تأخير بسيط لضمان حفظ الإعدادات في Hive
    await Future.delayed(const Duration(milliseconds: 150));

    if (mounted) {
      // 🔄 إعادة تشغيل التطبيق بالكامل لإصلاح الألوان
      RestartWidget.restartApp(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = AppState().isGuest;
    final user = AppState().userData;

    final String name =
        isGuest ? "GUEST USER" : (user?['first_name'] ?? "User").toUpperCase();
    final String username =
        isGuest ? "Not Logged In" : (user?['username'] ?? "@user");
    final String firstLetter =
        isGuest ? "?" : (name.isNotEmpty ? name[0] : "U");

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "MY PROFILE",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isTeacher ? "TEACHER DASHBOARD" : "MANAGE YOUR ACCOUNT",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 32),

              // --- User Info Card ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(24),
                  // ✅ استخدام لون حدود ديناميكي
                  border: Border.all(
                      color: AppColors.textSecondary.withOpacity(0.1)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8)
                  ],
                ),
                child: Row(
                  children: [
                    // ✅ Avatar
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.accentYellow.withOpacity(0.5),
                            width: 2),
                        image: (_isTeacher &&
                                _profileImage != null &&
                                _profileImage!.isNotEmpty)
                            ? DecorationImage(
                                image: NetworkImage(_profileImage!
                                        .startsWith('http')
                                    ? _profileImage!
                                    : '$_baseUrl/api/public/get-avatar?file=$_profileImage'),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (_isTeacher &&
                              _profileImage != null &&
                              _profileImage!.isNotEmpty)
                          ? null
                          : Center(
                              child: Text(
                                firstLetter,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentYellow,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundPrimary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              username,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (!isGuest)
                      GestureDetector(
                        onTap: () {
                          // ✅ تحديث البيانات عند العودة من شاشة التعديل
                          Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const EditProfileScreen()))
                              .then((_) => _loadUserData());
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color:
                                    AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: Icon(LucideIcons.edit2,
                              size: 16, color: AppColors.accentYellow),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ========================================================
              // 🟢 قسم المعلم (يظهر فقط للمعلم)
              // ========================================================
              if (_isTeacher && !isGuest) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    "TEACHER CONTROLS",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                        letterSpacing: 2.0),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.accentYellow.withOpacity(0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // 1. طلبات الاشتراك
                      _buildMenuItem(context,
                          icon: LucideIcons.bellRing,
                          title: "Incoming Requests",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const StudentRequestsScreen()))),
                      Divider(
                          height: 1,
                          color: AppColors.textSecondary.withOpacity(0.1)),

                      // 2. إدارة الطلاب
                      _buildMenuItem(context,
                          icon: LucideIcons.users,
                          title: "My Students",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const ManageStudentsScreen()))),
                      Divider(
                          height: 1,
                          color: AppColors.textSecondary.withOpacity(0.1)),

                      // 3. فريق العمل
                      _buildMenuItem(context,
                          icon: LucideIcons.shieldCheck,
                          title: "Manage Team",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ManageTeamScreen()))),
                      Divider(
                          height: 1,
                          color: AppColors.textSecondary.withOpacity(0.1)),

                      // 4. الإحصائيات المالية
                      _buildMenuItem(context,
                          icon: LucideIcons.barChart2,
                          title: "Financial Stats",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const FinancialStatsScreen()))),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // --- Account Settings (للجميع ما عدا الضيف) ---
              if (!isGuest) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    "ACCOUNT SETTINGS",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                        letterSpacing: 2.0),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.textSecondary.withOpacity(0.1)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildMenuItem(context,
                          icon: LucideIcons.user,
                          title: "Edit Profile",
                          onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const EditProfileScreen()))
                              .then((_) => _loadUserData())),
                      Divider(
                          height: 1,
                          color: AppColors.textSecondary.withOpacity(0.1)),
                      _buildMenuItem(context,
                          icon: LucideIcons.lock,
                          title: "Change Password",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const ChangePasswordScreen()))),

                      // ⚠️ إظهار "طلباتي" فقط للطالب
                      if (!_isTeacher) ...[
                        Divider(
                            height: 1,
                            color: AppColors.textSecondary.withOpacity(0.1)),
                        _buildMenuItem(context,
                            icon: LucideIcons.clipboardList,
                            title: "My Requests",
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const MyRequestsScreen()))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // --- General Settings ---
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  "GENERAL",
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 2.0),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.textSecondary.withOpacity(0.1)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildMenuItem(context,
                        icon: LucideIcons.info,
                        title: "App Information",
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DevInfoScreen()))),
                    Divider(
                        height: 1,
                        color: AppColors.textSecondary.withOpacity(0.1)),

                    // ✅ زر التبديل بين الوضعين النهاري والليلي
                    _buildMenuItem(
                      context,
                      icon:
                          AppState.isDark ? LucideIcons.moon : LucideIcons.sun,
                      title: AppState.isDark
                          ? "Dark Mode / الوضع الليلي"
                          : "Light Mode / الوضع النهاري",
                      onTap: _toggleThemeAndRestart,
                      trailing: Switch(
                        value: AppState.isDark,
                        // ✅ ألوان الوضع النشط (Dark Mode)
                        activeColor: AppColors.accentYellow,
                        activeTrackColor:
                            AppColors.accentYellow.withOpacity(0.4),

                        // ✅ ألوان الوضع غير النشط (Light Mode)
                        inactiveThumbColor: Colors.grey.shade600,
                        inactiveTrackColor: Colors.grey.shade300,

                        onChanged: (val) {
                          _toggleThemeAndRestart();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ========================================================
              // 🔴 Danger Zone (حذف الحساب) - تمت الإضافة هنا
              // ========================================================
              if (!isGuest) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    "DANGER ZONE",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                        letterSpacing: 2.0),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.error
                        .withOpacity(0.05), // لون خلفية خفيف للأحمر
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildMenuItem(
                        context,
                        icon: LucideIcons.trash2,
                        title: "Delete My Account",
                        // أيقونة حمراء لتمييز الخطر
                        trailing: Icon(LucideIcons.chevronRight,
                            size: 18, color: AppColors.error),
                        onTap: _deleteAccount, // استدعاء دالة الحذف
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // --- Logout Button ---
              GestureDetector(
                onTap: _logout,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isGuest
                        ? AppColors.accentYellow
                        : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isGuest
                            ? AppColors.accentYellow
                            : AppColors.error.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isGuest ? LucideIcons.logIn : LucideIcons.logOut,
                          color: isGuest
                              ? AppColors.backgroundPrimary
                              : AppColors.error,
                          size: 18),
                      const SizedBox(width: 12),
                      Text(isGuest ? "LOGIN / REGISTER" : "LOGOUT",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isGuest
                                  ? AppColors.backgroundPrimary
                                  : AppColors.error,
                              letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ دالة بناء العناصر
  Widget _buildMenuItem(BuildContext context,
      {required IconData icon,
      required String title,
      required VoidCallback onTap,
      String? badge,
      Widget? trailing}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 2)
                  ],
                ),
                child: Icon(icon, size: 18, color: AppColors.accentYellow),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
              if (trailing != null)
                trailing
              else ...[
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.accentOrange,
                        borderRadius: BorderRadius.circular(50)),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                Icon(LucideIcons.chevronRight,
                    size: 18, color: AppColors.textSecondary),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
