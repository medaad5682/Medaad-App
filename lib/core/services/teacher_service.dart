import 'dart:io';
import 'package:dio/dio.dart'; // لا يزال مطلوباً من أجل DioException و FormData و MultipartFile
import '../services/api_client.dart';
import '../constants/api_constants.dart';

class TeacherService {
  // ⚠️ تأكد من أن هذا الرابط صحيح ويعمل
  final String baseUrl = ApiConstants.apiUrl;

  // ==========================================================
  // 🆕 إدارة البروفايل (جلب البيانات + رفع الصورة + التحديث)
  // ==========================================================

  // ✅ دالة جلب البروفايل الكامل للمدرس (البيانات الحالية + تفاصيل الدفع)
  Future<Map<String, dynamic>> getTeacherProfile() async {
    try {
      // إرسال طلب GET لجلب البيانات بالاعتماد على ApiClient
      final response = await ApiClient.instance.get(
        '$baseUrl/teacher/update-profile',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'];
      } else {
        throw Exception("فشل تحميل البيانات");
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['error'] ?? "فشل الاتصال بالسيرفر");
      }
      throw Exception("خطأ غير متوقع: $e");
    }
  }

  // ✅ دالة رفع صورة البروفايل
  Future<String> uploadProfileImage(File file) async {
    try {
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      // استخدام الـ API الجديد المخصص للصور الشخصية
      final response = await ApiClient.instance.post(
        '$baseUrl/user/upload-avatar',
        data: formData,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['url'];
      } else {
        throw Exception("فشل رفع الصورة");
      }
    } catch (e) {
      throw Exception("خطأ أثناء الرفع: $e");
    }
  }

  // ✅ دالة تحديث بيانات المدرس (تحديث البيانات الشخصية + الصورة)
  Future<void> updateProfile({
    String? firstName,
    String? phone,
    String? password,
    String? profileImage,
  }) async {
    try {
      await ApiClient.instance.post(
        '$baseUrl/teacher/update-profile',
        data: {
          if (firstName != null) 'firstName': firstName,
          if (phone != null) 'phone': phone,
          if (password != null) 'password': password,
          if (profileImage != null) 'profileImage': profileImage,
        },
      );
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['error'] ?? "فشل تحديث البيانات");
      }
      throw Exception("خطأ غير متوقع: $e");
    }
  }

  // ==========================================================
  // 1️⃣ إدارة المحتوى (إضافة - تعديل - حذف)
  // ==========================================================
  Future<dynamic> manageContent({
    required String action, // 'create', 'update', 'delete'
    required String type, // 'courses', 'subjects', 'chapters', 'videos', 'pdfs'
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await ApiClient.instance.post(
        '$baseUrl/teacher/content',
        data: {'action': action, 'type': type, 'data': data},
      );
      return response.data;
    } catch (e) {
      if (e is DioException) {
        throw Exception(
            e.response?.data['error'] ?? "حدث خطأ في الاتصال بالسيرفر");
      }
      throw Exception("فشل تنفيذ العملية: $e");
    }
  }

  // ==========================================================
  // 2️⃣ رفع الملفات العامة (للمحتوى)
  // ==========================================================
  // ✅ [تم التعديل لإرجاع Map بدلاً من String للحصول على الرابط والهاش معاً]
  Future<Map<String, dynamic>> uploadFile(File file,
      {Function(int sent, int total)? onProgress}) async {
    try {
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await ApiClient.instance.post(
        '$baseUrl/teacher/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (onProgress != null && total != -1) {
            onProgress(sent, total);
          }
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data; // إرجاع البيانات كاملة
      } else {
        throw Exception("فشل رفع الملف");
      }
    } catch (e) {
      throw Exception("خطأ أثناء الرفع: $e");
    }
  }

  // ==========================================================
  // 2.b️⃣ رفع الفيديوهات مباشرة إلى Bunny Stream (TUS قابل للاستئناف)
  // ==========================================================
  // ✅ بدء/طلب جلسة رفع جديدة: ينشئ كائن فيديو فارغ على Bunny ويرجع توقيعاً
  // موقّعاً يستخدمه التطبيق للرفع المباشر (بدون مرور الفيديو بسيرفرنا).
  Future<Map<String, dynamic>> createVideoUploadSession({
    required String chapterId,
    required String title,
    required int fileSize,
    int expirationHours = 6,
  }) async {
    try {
      final response = await ApiClient.instance.post(
        '$baseUrl/teacher/create-upload-session',
        data: {
          'chapterId': chapterId,
          'title': title,
          'fileSize': fileSize,
          'expirationHours': expirationHours,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return Map<String, dynamic>.from(response.data);
      }
      throw Exception(response.data['error'] ?? 'فشل إنشاء جلسة الرفع');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['error'] ?? 'فشل الاتصال بالسيرفر');
      }
      throw Exception('فشل إنشاء جلسة الرفع: $e');
    }
  }

  // ✅ تأكيد اكتمال الرفع المباشر على Bunny وحفظ سجل الفيديو في قاعدة البيانات
  Future<Map<String, dynamic>> confirmVideoUpload({
    required String bunnyVideoId,
    required String chapterId,
    required String title,
    bool notifyStudents = false,
    int sortOrder = 999,
    int durationSeconds = 0,
  }) async {
    try {
      final response = await ApiClient.instance.post(
        '$baseUrl/teacher/confirm-upload',
        data: {
          'bunnyVideoId': bunnyVideoId,
          'chapterId': chapterId,
          'title': title,
          'notifyStudents': notifyStudents,
          'sortOrder': sortOrder,
          'durationSeconds': durationSeconds,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return Map<String, dynamic>.from(response.data);
      }
      throw Exception(response.data['error'] ?? 'فشل حفظ بيانات الفيديو');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['error'] ?? 'فشل الاتصال بالسيرفر');
      }
      throw Exception('فشل تأكيد الرفع: $e');
    }
  }

  // ✅ إلغاء/تنظيف جلسة رفع لم تكتمل (يحذف الفيديو الفارغ من Bunny)
  Future<void> cancelVideoUpload({required String bunnyVideoId}) async {
    try {
      await ApiClient.instance.post(
        '$baseUrl/teacher/cancel-upload',
        data: {'bunnyVideoId': bunnyVideoId},
      );
    } catch (_) {
      // غير حرج — لا داعي لإفشال تجربة المستخدم بسبب فشل التنظيف
    }
  }

  // ✅ الاستعلام عن حالة معالجة فيديو تم رفعه (waiting/encoding/ready/failed)
  Future<Map<String, dynamic>> getVideoStatus(String videoId) async {
    try {
      final response = await ApiClient.instance.get(
        '$baseUrl/teacher/video-status',
        queryParameters: {'videoId': videoId},
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['error'] ?? 'فشل جلب حالة الفيديو');
      }
      throw Exception('فشل جلب حالة الفيديو: $e');
    }
  }

  // ==========================================================
  // 3️⃣ إدارة الطلبات والطلاب
  // ==========================================================

  // جلب الطلبات المعلقة
  // ✅ دالة جلب الطلبات (تم التعديل لدعم الحالات والصفحات)
  Future<List<dynamic>> getRequests(
      {String status = 'pending', int page = 1}) async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/students',
      queryParameters: {
        'mode': 'requests',
        'status': status,
        'page': page,
        'limit': 10 // تحديد إرجاع 10 فقط في كل مرة
      },
    );

    // التوافق مع تعديل الباك إند (إرجاع {data, count})
    if (response.data is Map<String, dynamic> &&
        response.data.containsKey('data')) {
      return response.data['data'] as List<dynamic>;
    } else if (response.data is List) {
      return response.data;
    }
    return [];
  }

  // قبول أو رفض طلب اشتراك
  Future<void> handleRequest(String requestId, bool approve,
      {String? reason}) async {
    await ApiClient.instance.post(
      '$baseUrl/teacher/students',
      data: {
        'action': 'handle_request',
        'payload': {
          'requestId': requestId,
          'decision': approve ? 'approve' : 'reject',
          'rejectionReason': reason
        }
      },
    );
  }

  // البحث عن طالب
  Future<Map<String, dynamic>> searchStudent(String query) async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/students',
      queryParameters: {'mode': 'search', 'query': query},
    );
    return response.data;
  }

  // منح أو سحب صلاحية
  Future<void> toggleAccess(
      String studentId, String type, String itemId, bool allow) async {
    await ApiClient.instance.post(
      '$baseUrl/teacher/students',
      data: {
        'action': 'manage_access',
        'payload': {
          'studentId': studentId,
          'type': type,
          'itemId': itemId,
          'allow': allow
        }
      },
    );
  }

  // جلب محتوى المعلم
  Future<List<dynamic>> getMyContent() async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/students',
      queryParameters: {'mode': 'my_content'},
    );
    return response.data;
  }

  // ==========================================================
  // 4️⃣ إدارة فريق العمل
  // ==========================================================

  // جلب أعضاء الفريق
  Future<List<dynamic>> getTeamMembers() async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/team',
      queryParameters: {'mode': 'list'},
    );
    return response.data;
  }

  // البحث عن طلاب لترقيتهم
  Future<List<dynamic>> searchStudentsForTeam(String query) async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/team',
      queryParameters: {'mode': 'search', 'query': query},
    );
    return response.data;
  }

  // إدارة العضو
  Future<void> manageTeamMember(
      {required String action, required String userId}) async {
    await ApiClient.instance.post(
      '$baseUrl/teacher/team',
      data: {
        'action': action, // 'promote' or 'demote'
        'userId': userId,
      },
    );
  }

  // ==========================================================
  // 5️⃣ الامتحانات (إنشاء - تعديل - حذف - إحصائيات)
  // ==========================================================

  // إنشاء أو تحديث امتحان
  Future<void> createExam(Map<String, dynamic> examData) async {
    // تحديد نوع العملية بناءً على وجود المعرف
    String action = examData.containsKey('examId') ? 'update' : 'create';

    await ApiClient.instance.post(
      '$baseUrl/teacher/exams',
      data: {'action': action, 'payload': examData},
    );
  }

  // ✅ حذف امتحان
  Future<void> deleteExam(String examId) async {
    await ApiClient.instance.post(
      '$baseUrl/teacher/exams',
      data: {
        'action': 'delete',
        'payload': {'examId': examId}
      },
    );
  }

  // جلب تفاصيل الامتحان للمعلم (لغرض التعديل)
  Future<Map<String, dynamic>> getExamDetails(String examId) async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/get-exam-details',
      queryParameters: {'examId': examId},
    );
    return response.data;
  }

  // جلب إحصائيات امتحان معين
  Future<Map<String, dynamic>> getExamStats(String examId) async {
    final response = await ApiClient.instance.get(
      '$baseUrl/teacher/exams',
      queryParameters: {'examId': examId},
    );
    return response.data;
  }

  // ==========================================================
  // 6️⃣ الإحصائيات المالية (NEW)
  // ==========================================================

  // جلب الإحصائيات المالية والطلاب
  Future<Map<String, dynamic>> getFinancialStats() async {
    try {
      final response = await ApiClient.instance.get(
        '$baseUrl/teacher/financial-stats',
      );
      return response.data;
    } catch (e) {
      if (e is DioException) {
        throw Exception(
            e.response?.data['error'] ?? "فشل جلب الإحصائيات المالية");
      }
      throw Exception('فشل جلب الإحصائيات المالية: $e');
    }
  }
}
