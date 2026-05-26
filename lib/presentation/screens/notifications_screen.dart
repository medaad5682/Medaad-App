import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Dio _dio = Dio();
  bool _isLoading = true;
  List<dynamic> _notifications = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    try {
      var box = await Hive.openBox('auth_box');
      String? token = box.get('jwt_token');
      String? userId = box.get('user_id');
      String? deviceId = box.get('device_id'); // ✅ استخراج معرف الجهاز

      // ✅ التحقق من وجود جميع بيانات المصادقة بما فيها معرف الجهاز
      if (token == null || userId == null || deviceId == null) {
        if (mounted) {
          setState(() {
            _errorMessage = "الرجاء تسجيل الدخول لعرض الإشعارات.";
            _isLoading = false;
          });
        }
        return;
      }

      final response = await ApiClient.instance.get(
        '${ApiConstants.baseUrl}/api/student/get-notifications',
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-user-id': userId,
          'x-device-id': deviceId, // ✅ إرسال معرف الجهاز في الهيدر
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (mounted) {
          setState(() {
            _notifications = response.data['notifications'] ?? [];
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = "فشل في تحميل الإشعارات.";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "خطأ في الاتصال. يرجى المحاولة لاحقاً.";
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0 && now.day == date.day) {
        return "اليوم، ${DateFormat.jm().format(date)}";
      } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != date.day)) {
        return "أمس، ${DateFormat.jm().format(date)}";
      } else {
        return DateFormat('yyyy/MM/dd - h:mm a').format(date);
      }
    } catch (e) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    // استكشاف وضع الثيم الحالي (مظلم أم مضيء) لضبط الألوان تلقائياً
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // الألوان المتكيفة
    final Color bgColor = isDark ? AppColors.backgroundPrimary : const Color(0xFFF8F9FA);
    final Color appBarColor = isDark ? AppColors.backgroundSecondary : Colors.white;
    final Color cardColor = isDark ? AppColors.backgroundSecondary : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF212529);
    final Color subTextColor = isDark ? Colors.white70 : const Color(0xFF6C757D);
    final Color borderColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withOpacity(0.1),
        centerTitle: true,
        title: Text(
          "الإشعارات",
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.wifiOff, size: 64, color: AppColors.error.withOpacity(0.7)),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: TextStyle(color: AppColors.error, fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _isLoading = true);
                          _fetchNotifications();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentYellow,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text("إعادة المحاولة", style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.bellOff, size: 80, color: subTextColor.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          Text("لا توجد إشعارات حتى الآن", 
                            style: TextStyle(color: subTextColor, fontSize: 16, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.accentYellow,
                      backgroundColor: cardColor,
                      onRefresh: _fetchNotifications, // تحديث القائمة عند السحب للأسفل
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: _notifications.length,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          final notif = _notifications[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                              boxShadow: isDark ? [] : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentYellow.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(LucideIcons.bellRing, color: AppColors.accentYellow, size: 22),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notif['title'] ?? 'إشعار جديد',
                                        style: TextStyle(
                                          color: textColor, 
                                          fontWeight: FontWeight.bold, 
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        notif['body'] ?? '',
                                        style: TextStyle(
                                          color: subTextColor, 
                                          fontSize: 13, 
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(LucideIcons.clock, size: 12, color: subTextColor.withOpacity(0.7)),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(notif['created_at']),
                                            style: TextStyle(
                                              color: subTextColor.withOpacity(0.8), 
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
