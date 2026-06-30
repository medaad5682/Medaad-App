import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'storage_service.dart';
import 'teacher_service.dart';

// ===================================================================
// 🐰 خدمة الرفع المباشر والقابل للاستئناف للفيديوهات من التطبيق إلى
// Bunny Stream عبر بروتوكول TUS — نفس الآلية المستخدمة في لوحة تحكم الويب
// (hooks/useBunnyDirectUpload.js) لكن بتطبيق Dart خام بدون مكتبات خارجية.
// ===================================================================
//
// ✅ قابلية الاستئناف بعد انقطاع الاتصال أو إغلاق التطبيق:
//   - عند بدء الرفع، تُحفظ كل بيانات الجلسة (TUS upload URL + بيانات Bunny
//     + معرف الفصل + العنوان...) في Hive (صندوق مشفّر `upload_sessions`).
//   - إذا انقطع الاتصال أو أُغلق التطبيق أثناء الرفع، تبقى البيانات محفوظة.
//   - عند إعادة فتح شاشة الرفع لاحقاً لنفس الملف (نفس المسار + الحجم +
//     تاريخ التعديل)، تكتشف الخدمة الجلسة المحفوظة، وتسأل سيرفر Bunny
//     (عبر HEAD request وفق بروتوكول TUS) عن آخر offset تم استلامه فعلياً،
//     ثم تكمل الرفع من تلك النقطة بالضبط — لا إعادة رفع من الصفر.
//   - تُحذف الجلسة المحفوظة فقط عند: نجاح الرفع، أو إلغاء صريح من المعلم،
//     أو انتهاء صلاحية التوقيع (Bunny AuthorizationExpire) فينشئ التطبيق
//     جلسة جديدة تلقائياً.
// ===================================================================

enum BunnyUploadStatus {
  idle,
  requesting, // طلب جلسة من السيرفر
  uploading,
  paused, // توقف بسبب فقد الاتصال (وليس خطأ نهائي) — يمكن استئنافه تلقائياً
  confirming, // اكتمل الرفع على Bunny وجاري حفظ السجل في قاعدة البيانات
  done,
  error,
  cancelled,
}

class BunnyUploadException implements Exception {
  final String message;
  BunnyUploadException(this.message);
  @override
  String toString() => message;
}

class BunnyTusUploadService {
  // Singleton: حتى يستمر الرفع في الخلفية حتى لو غادر المستخدم الشاشة
  static final BunnyTusUploadService _instance =
      BunnyTusUploadService._internal();
  factory BunnyTusUploadService() => _instance;
  BunnyTusUploadService._internal() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    // فحص أولي للحالة الحالية عند إنشاء الخدمة (الـ Stream لا يصدر قيمة فورية دائماً)
    Connectivity().checkConnectivity().then((results) {
      _isNetworkAvailable =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
    });
  }

  static const String _sessionsBoxName = 'upload_sessions';
  static const int _chunkSize = 8 * 1024 * 1024; // 8MB لكل قطعة

  final TeacherService _teacherService = TeacherService();
  final Dio _tusDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(minutes: 10),
    receiveTimeout: const Duration(seconds: 30),
    // Bunny TUS endpoint مستقل عن باك إند التطبيق، لذا لا نستخدم ApiClient هنا
    validateStatus: (_) => true,
  ));

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // الحالة الحالية المتاحة للواجهة عبر ValueNotifier-style callbacks
  BunnyUploadStatus status = BunnyUploadStatus.idle;
  double progress = 0.0; // 0..1
  String? errorMessage;
  String? currentFileKey;

  void Function(BunnyUploadStatus status, double progress, String? error)?
      onUpdate;

  bool _cancelRequested = false;
  bool _isNetworkAvailable = true;
  Completer<void>? _pauseWaiter;

  void _emit() => onUpdate?.call(status, progress, errorMessage);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);
    _isNetworkAvailable = hasConnection;
    if (hasConnection && _pauseWaiter != null && !_pauseWaiter!.isCompleted) {
      _pauseWaiter!.complete();
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  // ------------------------------------------------------------
  // مفتاح فريد للملف (يُستخدم لتخزين/استرجاع جلسة الرفع المحفوظة)
  // ------------------------------------------------------------
  String _fingerprint(File file, int fileSize) {
    final modified = file.lastModifiedSync().millisecondsSinceEpoch;
    return 'bunny_upload:${file.path}:$fileSize:$modified';
  }

  Future<Map<dynamic, dynamic>?> _loadSession(String key) async {
    try {
      final box = await StorageService.openBox(_sessionsBoxName);
      final raw = box.get(key);
      if (raw == null) return null;
      final session = Map<String, dynamic>.from(jsonDecode(raw));
      final expiresAt = session['expiresAt'] as int?;
      if (expiresAt != null &&
          DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiresAt) {
        await box.delete(key);
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(String key, Map<String, dynamic> data) async {
    try {
      final box = await StorageService.openBox(_sessionsBoxName);
      await box.put(key, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _clearSession(String key) async {
    try {
      final box = await StorageService.openBox(_sessionsBoxName);
      await box.delete(key);
    } catch (_) {}
  }

  /// يتحقق هل يوجد رفع متوقف (غير مكتمل) محفوظ لهذا الملف بالتحديد.
  /// تُستخدم هذه الدالة لإظهار خيار "استئناف الرفع السابق" في الواجهة.
  Future<bool> hasResumableSession(File file) async {
    final fileSize = await file.length();
    final key = _fingerprint(file, fileSize);
    final session = await _loadSession(key);
    return session != null;
  }

  // ------------------------------------------------------------
  // بدء أو استئناف رفع فيديو
  // ------------------------------------------------------------
  Future<void> startUpload({
    required File file,
    required String chapterId,
    required String title,
    bool notifyStudents = false,
    int sortOrder = 999,
    int durationSeconds = 0,
    required void Function(Map<String, dynamic> result) onComplete,
    required void Function(String error) onError,
  }) async {
    _cancelRequested = false;
    errorMessage = null;
    progress = 0.0;
    status = BunnyUploadStatus.requesting;
    _emit();

    final fileSize = await file.length();
    final fileKey = _fingerprint(file, fileSize);
    currentFileKey = fileKey;

    try {
      Map<dynamic, dynamic>? session = await _loadSession(fileKey);

      if (session == null) {
        session = await _createFreshSession(
          file: file,
          fileSize: fileSize,
          chapterId: chapterId,
          title: title,
          notifyStudents: notifyStudents,
          sortOrder: sortOrder,
          durationSeconds: durationSeconds,
        );
        await _saveSession(fileKey, Map<String, dynamic>.from(session));
      }

      status = BunnyUploadStatus.uploading;
      _emit();

      await _runTusUpload(
        file: file,
        fileSize: fileSize,
        fileKey: fileKey,
        session: Map<String, dynamic>.from(session),
        onComplete: onComplete,
        onError: onError,
      );
    } catch (e) {
      status = BunnyUploadStatus.error;
      errorMessage = e.toString().replaceAll('Exception:', '').trim();
      _emit();
      onError(errorMessage ?? 'فشل رفع الفيديو');
    }
  }

  Future<Map<String, dynamic>> _createFreshSession({
    required File file,
    required int fileSize,
    required String chapterId,
    required String title,
    required bool notifyStudents,
    required int sortOrder,
    required int durationSeconds,
  }) async {
    final result = await _teacherService.createVideoUploadSession(
      chapterId: chapterId,
      title: title,
      fileSize: fileSize,
    );

    return {
      ...result,
      'chapterId': chapterId,
      'title': title,
      'notifyStudents': notifyStudents,
      'sortOrder': sortOrder,
      'durationSeconds': durationSeconds,
      'fileSize': fileSize,
      'tusUploadUrl': null, // يُملأ بعد POST الأول إلى Bunny
    };
  }

  // ------------------------------------------------------------
  // تنفيذ بروتوكول TUS يدوياً: إنشاء المورد (إن لم يكن موجوداً) ثم
  // رفع البيانات على دفعات (PATCH) قابلة للاستئناف باستخدام Upload-Offset
  // ------------------------------------------------------------
  Future<void> _runTusUpload({
    required File file,
    required int fileSize,
    required String fileKey,
    required Map<String, dynamic> session,
    required void Function(Map<String, dynamic> result) onComplete,
    required void Function(String error) onError,
  }) async {
    final bunnyVideoId = session['bunnyVideoId'] as String;
    final libraryId = session['libraryId'].toString();
    final signature = session['signature'] as String;
    final expiresAt = session['expiresAt'];
    final tusEndpoint =
        (session['tusEndpoint'] as String?) ?? 'https://video.bunnycdn.com/tusupload';

    // إذا انتهت صلاحية التوقيع، أنشئ جلسة جديدة بالكامل (Bunny video جديد)
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt is int && nowSec > expiresAt - 30) {
      await _clearSession(fileKey);
      final fresh = await _createFreshSession(
        file: file,
        fileSize: fileSize,
        chapterId: session['chapterId'],
        title: session['title'],
        notifyStudents: session['notifyStudents'] ?? false,
        sortOrder: session['sortOrder'] ?? 999,
        durationSeconds: session['durationSeconds'] ?? 0,
      );
      await _saveSession(fileKey, fresh);
      return _runTusUpload(
        file: file,
        fileSize: fileSize,
        fileKey: fileKey,
        session: fresh,
        onComplete: onComplete,
        onError: onError,
      );
    }

    final authHeaders = {
      'AuthorizationSignature': signature,
      'AuthorizationExpire': expiresAt.toString(),
      'VideoId': bunnyVideoId,
      'LibraryId': libraryId,
      'Tus-Resumable': '1.0.0',
    };

    String? tusUploadUrl = session['tusUploadUrl'] as String?;

    // دالة مساعدة محلية: عند انتهاء صلاحية الجلسة في أي لحظة أثناء الرفع
    // (HEAD أو PATCH رجعا 401/403/404/410)، ننشئ جلسة Bunny جديدة بالكامل
    // ونستأنف الرفع تلقائياً بدلاً من إفشال العملية على المعلم.
    Future<void> regenerateAndResume() async {
      await _clearSession(fileKey);
      final fresh = await _createFreshSession(
        file: file,
        fileSize: fileSize,
        chapterId: session['chapterId'],
        title: session['title'],
        notifyStudents: session['notifyStudents'] ?? false,
        sortOrder: session['sortOrder'] ?? 999,
        durationSeconds: session['durationSeconds'] ?? 0,
      );
      await _saveSession(fileKey, fresh);
      await _runTusUpload(
        file: file,
        fileSize: fileSize,
        fileKey: fileKey,
        session: fresh,
        onComplete: onComplete,
        onError: onError,
      );
    }

    // 1) إنشاء مورد TUS إن لم يكن منشأً بعد (أول مرة لهذه الجلسة)
    if (tusUploadUrl == null) {
      try {
        tusUploadUrl = await _createTusResource(
          tusEndpoint: tusEndpoint,
          fileSize: fileSize,
          fileName: file.uri.pathSegments.last,
          title: session['title'] ?? file.uri.pathSegments.last,
          authHeaders: authHeaders,
        );
      } on _SessionExpiredError {
        return regenerateAndResume();
      }
      session['tusUploadUrl'] = tusUploadUrl;
      await _saveSession(fileKey, session);
    }

    // 2) معرفة آخر offset مستلم فعلياً على سيرفر Bunny (يدعم الاستئناف
    //    حتى لو تغيّر اتصال الشبكة أو أُعيد فتح التطبيق بالكامل)
    int offset;
    try {
      offset = await _fetchCurrentOffset(tusUploadUrl, authHeaders);
    } on _SessionExpiredError {
      return regenerateAndResume();
    }

    final raf = await file.open();
    try {
      while (offset < fileSize) {
        if (_cancelRequested) {
          status = BunnyUploadStatus.cancelled;
          _emit();
          return;
        }

        // ⏸️ إذا لا يوجد اتصال إنترنت، ننتظر بهدوء حتى يعود بدل الفشل الفوري
        if (!_isNetworkAvailable) {
          status = BunnyUploadStatus.paused;
          _emit();
          _pauseWaiter = Completer<void>();
          await _pauseWaiter!.future.timeout(
            const Duration(days: 1),
            onTimeout: () {},
          );
          if (_cancelRequested) {
            status = BunnyUploadStatus.cancelled;
            _emit();
            return;
          }
          status = BunnyUploadStatus.uploading;
          _emit();
          // نعيد التحقق من الأوفست الحقيقي بعد عودة الاتصال (احتياطاً)
          try {
            offset = await _fetchCurrentOffset(tusUploadUrl, authHeaders);
          } on _SessionExpiredError {
            await raf.close();
            return regenerateAndResume();
          }
          continue;
        }

        final remaining = fileSize - offset;
        final thisChunk = min(_chunkSize, remaining);
        await raf.setPosition(offset);
        final bytes = await raf.read(thisChunk);

        try {
          final newOffset = await _patchChunk(
            tusUploadUrl: tusUploadUrl,
            offset: offset,
            bytes: bytes,
            authHeaders: authHeaders,
          );
          offset = newOffset;
          progress = (offset / fileSize).clamp(0.0, 0.99);
          _emit();
        } on _SessionExpiredError {
          await raf.close();
          return regenerateAndResume();
        } on _RetryableUploadError {
          // خطأ شبكة عابر — أعد محاولة نفس القطعة بعد تأخير بسيط بدل
          // إفشال الرفع بالكامل (مقاومة لاهتزاز الشبكة كما في نسخة الويب)
          await Future.delayed(const Duration(seconds: 3));
          try {
            offset = await _fetchCurrentOffset(tusUploadUrl, authHeaders);
          } on _SessionExpiredError {
            await raf.close();
            return regenerateAndResume();
          }
        }
      }
    } finally {
      await raf.close();
    }

    // ── اكتمل الرفع على Bunny — الآن نؤكد الحفظ في قاعدة البيانات ──
    status = BunnyUploadStatus.confirming;
    progress = 1.0;
    _emit();

    try {
      final confirmResult = await _teacherService.confirmVideoUpload(
        bunnyVideoId: bunnyVideoId,
        chapterId: session['chapterId'],
        title: session['title'],
        notifyStudents: session['notifyStudents'] ?? false,
        sortOrder: session['sortOrder'] ?? 999,
        durationSeconds: session['durationSeconds'] ?? 0,
      );
      await _clearSession(fileKey);
      status = BunnyUploadStatus.done;
      _emit();
      onComplete(confirmResult);
    } catch (e) {
      // الرفع نفسه نجح فعلياً على Bunny، فقط فشل تسجيله في قاعدة البيانات.
      // نُبقي الجلسة المحفوظة بحالة "اكتمل الرفع" حتى تتم المحاولة لاحقاً
      // بدون إعادة رفع الفيديو من جديد.
      status = BunnyUploadStatus.error;
      errorMessage =
          'اكتمل رفع الفيديو لكن فشل حفظ البيانات: ${e.toString().replaceAll('Exception:', '').trim()}';
      _emit();
      onError(errorMessage!);
    }
  }

  Future<String> _createTusResource({
    required String tusEndpoint,
    required int fileSize,
    required String fileName,
    required String title,
    required Map<String, String> authHeaders,
  }) async {
    final metadata = {
      'filetype': 'video/mp4',
      'title': title,
    };
    final encodedMetadata = metadata.entries
        .map((e) => '${e.key} ${base64Encode(utf8.encode(e.value))}')
        .join(',');

    try {
      final res = await _tusDio.post(
        tusEndpoint,
        options: Options(headers: {
          ...authHeaders,
          'Upload-Length': fileSize.toString(),
          'Upload-Metadata': encodedMetadata,
          'Content-Length': '0',
        }),
      );

      if (res.statusCode == 201) {
        final location = res.headers.value('location');
        if (location == null) {
          throw BunnyUploadException('لم يستلم التطبيق رابط الرفع من السيرفر');
        }
        // قد يأتي الرابط نسبياً أو كاملاً
        if (location.startsWith('http')) return location;
        final uri = Uri.parse(tusEndpoint);
        return '${uri.scheme}://${uri.host}$location';
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw _SessionExpiredError('انتهت صلاحية جلسة الرفع');
      }

      throw BunnyUploadException('فشل إنشاء جلسة الرفع على السيرفر (${res.statusCode})');
    } on DioException catch (e) {
      throw _RetryableUploadError(e.message ?? 'خطأ في الاتصال');
    }
  }

  Future<int> _fetchCurrentOffset(
      String tusUploadUrl, Map<String, String> authHeaders) async {
    try {
      final res = await _tusDio.head(
        tusUploadUrl,
        options: Options(headers: authHeaders),
      );
      if (res.statusCode == 200 || res.statusCode == 204) {
        final offsetHeader = res.headers.value('upload-offset');
        return int.tryParse(offsetHeader ?? '0') ?? 0;
      }
      if (res.statusCode == 404 || res.statusCode == 410) {
        throw _SessionExpiredError('انتهت صلاحية الرفع المؤقت على السيرفر');
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw _SessionExpiredError('انتهت صلاحية جلسة الرفع');
      }
      throw _RetryableUploadError('تعذر التحقق من حالة الرفع (${res.statusCode})');
    } on DioException {
      // لا يوجد اتصال الآن — اعتبرها حالة قابلة لإعادة المحاولة لاحقاً
      throw _RetryableUploadError('تعذر التحقق من حالة الرفع');
    }
  }

  Future<int> _patchChunk({
    required String tusUploadUrl,
    required int offset,
    required List<int> bytes,
    required Map<String, String> authHeaders,
  }) async {
    try {
      final res = await _tusDio.patch(
        tusUploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            ...authHeaders,
            'Content-Type': 'application/offset+octet-stream',
            'Upload-Offset': offset.toString(),
            'Content-Length': bytes.length.toString(),
          },
        ),
      );

      if (res.statusCode == 204 || res.statusCode == 200) {
        final newOffsetHeader = res.headers.value('upload-offset');
        final newOffset = int.tryParse(newOffsetHeader ?? '');
        return newOffset ?? (offset + bytes.length);
      }

      if (res.statusCode == 409) {
        // تعارض في الأوفست (ربما رفعت قطعة سابقاً بالفعل) — أعد القراءة من السيرفر
        throw _RetryableUploadError('تعارض في نقطة الاستئناف');
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw _SessionExpiredError('انتهت صلاحية جلسة الرفع');
      }

      throw _RetryableUploadError('خطأ مؤقت أثناء رفع جزء من الملف (${res.statusCode})');
    } on DioException {
      throw _RetryableUploadError('انقطع الاتصال أثناء رفع جزء من الملف');
    }
  }

  // ------------------------------------------------------------
  // إلغاء صريح من المستخدم
  // ------------------------------------------------------------
  Future<void> cancel({File? file}) async {
    _cancelRequested = true;
    if (_pauseWaiter != null && !_pauseWaiter!.isCompleted) {
      _pauseWaiter!.complete();
    }

    if (file != null) {
      final fileSize = await file.length();
      final key = _fingerprint(file, fileSize);
      final session = await _loadSession(key);
      if (session != null && session['bunnyVideoId'] != null) {
        // تنظيف الفيديو الفارغ من Bunny (غير حرج لو فشل)
        try {
          await _teacherService.cancelVideoUpload(
            bunnyVideoId: session['bunnyVideoId'],
          );
        } catch (_) {}
      }
      await _clearSession(key);
    }

    status = BunnyUploadStatus.cancelled;
    progress = 0.0;
    _emit();
  }

  void reset() {
    status = BunnyUploadStatus.idle;
    progress = 0.0;
    errorMessage = null;
    currentFileKey = null;
  }
}

class _RetryableUploadError implements Exception {
  final String message;
  _RetryableUploadError(this.message);
  @override
  String toString() => message;
}

class _SessionExpiredError implements Exception {
  final String message;
  _SessionExpiredError(this.message);
  @override
  String toString() => message;
}
