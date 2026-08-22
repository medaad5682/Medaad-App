import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// ✅ إضافة استيراد Firebase App Check
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
// ✅ [FIX F-13] استدعاء مكتبة التشفير لحساب بصمة الملفات المحملة
import 'package:crypto/crypto.dart' as hash_crypto;

import 'notification_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../constants/api_constants.dart';

class DownloadManager with WidgetsBindingObserver {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  DownloadManager._internal() {
    WidgetsBinding.instance.addObserver(this);
    NotificationService().cancelAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      cancelAllDownloads();
    }
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  static final Set<String> _activeDownloads = {};
  final Map<String, String> activeTitles = {};
  static final Map<String, CancelToken> _cancelTokens = {};
  // ✅ [FIX] Tracks the output file path(s) for the currently active download
  // of each lesson, so an explicit user cancel can also clean up that
  // download's HLS segment cache (see _videoDownloadIsolateEntryPoint). A
  // plain failure (e.g. connection drop) does NOT go through here, so the
  // segment cache is preserved and the next attempt can resume from it.
  static final Map<String, List<String>> _activeSavePaths = {};
  static final ValueNotifier<Map<String, double>> downloadingProgress =
      ValueNotifier({});
  final String _baseUrl = ApiConstants.baseUrl;
  Timer? _keepAliveTimer;

  bool isFileDownloading(String id) => _activeDownloads.contains(id);

  bool isFileDownloaded(String id) {
    if (!Hive.isBoxOpen('downloads_box')) return false;
    return Hive.box('downloads_box').containsKey(id);
  }

  String _extractDurationFromUrl(String url) {
    try {
      final regex = RegExp(r'(?:dur%3D|dur=)(\d+(\.\d+)?)');
      final match = regex.firstMatch(url);
      if (match != null) {
        final secondsString = match.group(1);
        if (secondsString != null) {
          return _formatDuration(double.parse(secondsString).toInt());
        }
      }
    } catch (e) {}
    return "";
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = totalSeconds % 60;
    return hours > 0
        ? "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}"
        : "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  Future<void> cancelAllDownloads() async {
    final List<String> allIds = List.from(_cancelTokens.keys);
    for (var id in allIds) {
      await cancelDownload(id);
    }
    await NotificationService().cancelAll();
    _stopBackgroundService();
  }

  Future<void> cancelDownload(String lessonId) async {
    if (_cancelTokens.containsKey(lessonId)) {
      try {
        _cancelTokens[lessonId]?.cancel("User cancelled download");
      } catch (e) {
        debugPrint("Error canceling token: $e");
      }
      _cancelTokens.remove(lessonId);
    }

    // ✅ [FIX] User explicitly cancelled — this download isn't coming back
    // automatically, so clean up any cached HLS segments now instead of
    // leaving them around forever.
    final pathsToClean = _activeSavePaths.remove(lessonId);
    if (pathsToClean != null) {
      for (final path in pathsToClean) {
        try {
          final segDir = Directory('$path.segments');
          if (await segDir.exists()) await segDir.delete(recursive: true);
        } catch (e) {
          debugPrint("Error cleaning segment cache: $e");
        }
      }
    }

    // ✅ [FIX] Also drop the resumable/pending record so a cancelled
    // download doesn't show a stray "Resume" button afterwards.
    try {
      final pendingBox = await StorageService.openBox('pending_downloads_box');
      await pendingBox.delete(lessonId);
    } catch (e) {
      debugPrint("Error clearing pending download record: $e");
    }

    _activeDownloads.remove(lessonId);
    activeTitles.remove(lessonId);

    var prog = Map<String, double>.from(downloadingProgress.value);
    prog.remove(lessonId);
    downloadingProgress.value = prog;

    await NotificationService().cancelNotification(lessonId.hashCode);

    if (_activeDownloads.isEmpty) {
      _stopBackgroundService();
    }
  }

  void _startBackgroundService() async {
    // ✅ [CRASH-FIX] Guard against ForegroundServiceStartNotAllowedException /
    // MissingForegroundServiceTypeException. If the plugin ever surfaces
    // these as a catchable PlatformException (rather than a raw native
    // crash), we don't want it hitting the top-level runZonedGuarded
    // handler in main.dart, which records everything as fatal:true.
    // Downloads simply won't show a progress notification in that rare
    // case — non-fatal, and still logged for visibility.
    final service = FlutterBackgroundService();
    try {
      if (!await service.isRunning()) await service.startService();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason:
            'BackgroundService failed to start (non-fatal, download continues)',
        fatal: false,
      );
      // Don't return early — downloads still work without the FGS
      // notification, they just won't show background progress.
    }

    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeDownloads.isEmpty) {
        _stopBackgroundService();
        return;
      }
      try {
        service.invoke('keepAlive');
      } catch (_) {
        // Service may not be running if startService() failed above —
        // don't let a missing service kill the download loop.
      }

      try {
        NotificationService().showProgressNotification(
          id: 888,
          title: "مــــداد Service",
          body: "Downloading ${_activeDownloads.length} file(s)...",
          progress: 0,
          maxProgress: 0,
        );
      } catch (e) {}
    });
  }

  void _stopBackgroundService() async {
    _keepAliveTimer?.cancel();
    try {
      await NotificationService().cancelNotification(888);
    } catch (e) {}

    final service = FlutterBackgroundService();
    try {
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
    } catch (e) {
      // Non-fatal: service may already be gone (e.g. killed by the OS
      // due to the same FGS restrictions) — nothing to clean up then.
      debugPrint("⚠️ stopService guard: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // 🚀 Start Download Logic
  // ---------------------------------------------------------------------------

  Future<void> startDownload({
    required String lessonId,
    required String videoTitle,
    required String courseName,
    required String subjectName,
    required String chapterName,
    String? folderName,
    required String subjectId,
    String? downloadUrl,
    String? audioUrl,
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
    bool isPdf = false,
    String quality = "SD",
    String duration = "",
  }) async {
    final CancelToken cancelToken = CancelToken();
    _cancelTokens[lessonId] = cancelToken;
    activeTitles[lessonId] = videoTitle;

    FirebaseCrashlytics.instance
        .log("⬇️ Download Started: $videoTitle (PDF: $isPdf)");
    _activeDownloads.add(lessonId);
    _startBackgroundService();

    // ✅ [FIX] Persist enough info to resume this exact download later —
    // automatically after a transient network retry, or manually via a
    // "Resume" button in the chapter screen — without ever re-showing the
    // quality-selection dialog. The already-resolved link is kept so a
    // resume can reuse it directly; if it turns out to be stale/expired,
    // the normal fallback below (get-video-id) still runs and simply
    // re-fetches a fresh link for the same lessonId, and this same
    // `quality` label is kept throughout so the resumed file is saved/
    // labeled consistently with the original choice.
    try {
      final pendingBox = await StorageService.openBox('pending_downloads_box');
      await pendingBox.put(lessonId, {
        'lessonId': lessonId,
        'videoTitle': videoTitle,
        'courseName': courseName,
        'subjectName': subjectName,
        'chapterName': chapterName,
        'folderName': folderName,
        'subjectId': subjectId,
        'downloadUrl': downloadUrl,
        'audioUrl': audioUrl,
        'isPdf': isPdf,
        'quality': quality,
        'duration': duration,
      });
    } catch (e) {
      debugPrint("⚠️ Could not persist pending download record: $e");
    }

    var currentProgress = Map<String, double>.from(downloadingProgress.value);
    currentProgress[lessonId] = 0.0;
    downloadingProgress.value = currentProgress;

    final notifService = NotificationService();
    final int notificationId = lessonId.hashCode;

    await notifService.showProgressNotification(
      id: notificationId,
      title: "Downloading: $videoTitle",
      body: "Starting...",
      progress: 0,
      maxProgress: 100,
    );

    // ✅ [FIX] Bounded automatic retry on connectivity-type failures. Each
    // retry re-runs the whole attempt below, which — thanks to the HLS
    // segment cache and the MP4 byte-range resume added earlier — picks up
    // from where the previous attempt stopped instead of starting over.
    // Once these auto-retries are exhausted (or the failure isn't
    // network-related), we stop looping and leave the pending-download
    // record in place so the UI can offer a manual "Resume" button instead
    // of endlessly retrying in the background.
    const int maxAutoRetries = 3;
    const List<Duration> retryDelays = [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ];
    int attempt = 0;

    try {
      while (true) {
        try {
      // ✅ [REVERTED to 2.0.2 pattern] رجوع لنفس الطريقة المباشرة التي كانت
      // تعمل 100%: قراءة/كتابة docs_chacha_key بمثيل FlutterSecureStorage
      // افتراضي (بدون iOptions/first_unlock_this_device)، بلا انتظار
      // AppReadyGate وبلا إعادة محاولة — تماماً كما في download_manager.dart
      // وfile_crypto_service.dart وlocal_proxy.dart في نسخة 2.0.2. الإصلاح
      // اللاحق الذي مرّر هذا المفتاح عبر مثيلات first_unlock_this_device في
      // بعض المسارات وترك بعضها الآخر بلا تغيير كسر الاتساق بين وقت
      // التنزيل/التشفير ووقت التشغيل/فك التشفير — فيديوهات جديدة تُشفَّر
      // بمفتاح قد لا يُقرأ بنفس القيمة لاحقاً عبر مثيل مختلف الإعدادات،
      // فيفشل التحقق من AEAD/MAC عند التشغيل ("Failed to recognize file
      // format" في MediaKit). الرجوع لمثيل واحد متسق بلا استثناءات يضمن أن
      // كل نقطة لمس لهذا المفتاح تتعامل معه بنفس الطريقة تماماً.
      final storage = const FlutterSecureStorage();
      String? storedKey = await storage.read(key: 'docs_chacha_key');
      if (storedKey == null) {
        final rand = Random.secure();
        final kb = List<int>.generate(32, (_) => rand.nextInt(256));
        storedKey = base64Encode(kb);
        await storage.write(key: 'docs_chacha_key', value: storedKey);
      }
      final List<int> chachaKeyBytes = base64Decode(storedKey);

      var box = await StorageService.openBox('auth_box');
      final deviceId = box.get('device_id');
      final token = box.get('jwt_token');
      const String appSecret = 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only';

      // ✅ جلب توكن الـ App Check
      String? appCheckToken;
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint("App Check Error: $e");
      }

      final Map<String, dynamic> requestHeaders = {
        'Authorization': 'Bearer $token',
        'x-device-id': deviceId,
        'x-app-secret': appSecret,
        if (appCheckToken != null)
          'X-Firebase-AppCheck':
              appCheckToken, // ✅ التوكن هنا سيتم استخدامه في جميع الـ Requests القادمة (get-video-id والتحميل داخل Isolates)
      };

      if (token == null) throw Exception("User auth missing");

      String? finalVideoUrl = downloadUrl;
      String? finalAudioUrl = audioUrl;

      if (finalVideoUrl == null) {
        if (isPdf) {
          finalVideoUrl = '$_baseUrl/api/secure/get-pdf?pdfId=$lessonId';
        } else {
          final res = await ApiClient.instance.get(
            '$_baseUrl/api/secure/get-video-id',
            queryParameters: {'lessonId': lessonId},
            options: Options(headers: requestHeaders),
            cancelToken: cancelToken,
          );
          if (res.statusCode == 200 && res.data['url'] != null) {
            finalVideoUrl = res.data['url'];
          }
        }
      }

      if (cancelToken.isCancelled)
        throw DioException(
            requestOptions: RequestOptions(path: finalVideoUrl!),
            type: DioExceptionType.cancel);
      if (finalVideoUrl == null) throw Exception("Link not found");

      if (!isPdf && (duration.isEmpty || duration == "--:--")) {
        String ext = _extractDurationFromUrl(finalVideoUrl);
        if (ext.isNotEmpty) duration = ext;
      }

      final appDir = await getApplicationDocumentsDirectory();
      final safeCourse =
          courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeSubject =
          subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      final safeChapter =
          chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');

      final dir = Directory(
          '${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter');
      if (!await dir.exists()) await dir.create(recursive: true);

      // ✅ التشفير الجديد ChaCha20 V2 لجميع الملفات
      final String videoFileName =
          isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_${quality}_v2.enc";
      final String videoSavePath = '${dir.path}/$videoFileName';

      String? audioSavePath;
      if (finalAudioUrl != null) {
        audioSavePath = '${dir.path}/aud_${lessonId}_hq_v2.enc';
      }

      // ✅ [FIX] Remember these paths so an explicit cancelDownload() can
      // find and clean up this download's HLS segment cache.
      _activeSavePaths[lessonId] = [
        videoSavePath,
        if (audioSavePath != null) audioSavePath,
      ];

      if (isPdf) {
        // 📄 تحميل وتشفير الـ PDF عبر Isolate للحفاظ على استجابة الواجهة
        await _runPdfDownloadAndEncrypt(
            url: finalVideoUrl,
            savePath: videoSavePath,
            headers: requestHeaders, // التوكن مدمج هنا
            keyBytes: chachaKeyBytes,
            cancelToken: cancelToken,
            onProgress: (p) {
              if (cancelToken.isCancelled) return;
              var prog = Map<String, double>.from(downloadingProgress.value);
              prog[lessonId] = p;
              downloadingProgress.value = prog;
              onProgress(p);
              int percent = (p * 100).toInt();
              if (percent % 5 == 0) {
                notifService.showProgressNotification(
                    id: notificationId,
                    title: "Downloading PDF...",
                    body: "$percent%",
                    progress: percent,
                    maxProgress: 100);
              }
            });
      } else {
        // 🎥 تحميل وتشفير الفيديو
        double vidProg = 0.0;
        double audProg = 0.0;

        void updateAggregatedProgress() {
          if (cancelToken.isCancelled) return;
          double total = (finalAudioUrl != null)
              ? (vidProg * 0.80) + (audProg * 0.20)
              : vidProg;
          var prog = Map<String, double>.from(downloadingProgress.value);
          prog[lessonId] = total;
          downloadingProgress.value = prog;
          onProgress(total);

          int percent = (total * 100).toInt();
          if (percent % 2 == 0) {
            notifService.showProgressNotification(
              id: notificationId,
              title: "Downloading: $videoTitle",
              body: "$percent%",
              progress: percent,
              maxProgress: 100,
            );
          }
        }

        final List<Future> tasks = [];

        tasks.add(_runVideoDownloadIsolate(
            url: finalVideoUrl,
            savePath: videoSavePath,
            headers: requestHeaders, // التوكن مدمج هنا
            keyBytes: chachaKeyBytes,
            cancelToken: cancelToken,
            onProgress: (p) {
              vidProg = p;
              updateAggregatedProgress();
            }));

        if (finalAudioUrl != null && audioSavePath != null) {
          tasks.add(_runVideoDownloadIsolate(
              url: finalAudioUrl,
              savePath: audioSavePath,
              headers: requestHeaders, // التوكن مدمج هنا
              keyBytes: chachaKeyBytes,
              cancelToken: cancelToken,
              onProgress: (p) {
                audProg = p;
                updateAggregatedProgress();
              }));
        }

        await Future.wait(tasks);
      }

      if (cancelToken.isCancelled)
        throw DioException(
            requestOptions: RequestOptions(path: finalVideoUrl),
            type: DioExceptionType.cancel);

      int totalSizeBytes = await File(videoSavePath).length();
      if (audioSavePath != null && await File(audioSavePath).exists()) {
        totalSizeBytes += await File(audioSavePath).length();
      }

      var downloadsBox = await StorageService.openBox('downloads_box');
      String uniqueStorageKey = isPdf ? 'pdf_$lessonId' : 'vid_$lessonId';

      await downloadsBox.put(uniqueStorageKey, {
        'id': lessonId,
        'title': videoTitle,
        'path': videoSavePath,
        'audioPath': audioSavePath,
        'subjectId': subjectId,
        'course': courseName,
        'subject': subjectName,
        'chapter': chapterName,
        'folder': (folderName ?? '').trim(),
        'type': isPdf ? 'pdf' : 'video',
        'quality': quality,
        'duration': duration,
        'date': DateTime.now().toIso8601String(),
        'size': totalSizeBytes,
      });

      await notifService.cancelNotification(notificationId);
      await notifService.showCompletionNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: videoTitle,
        isSuccess: true,
      );

      FirebaseCrashlytics.instance.log("✅ Download Success: $videoTitle");

      // ✅ Done — this lesson is no longer a "pending/resumable" download.
      try {
        final pendingBox =
            await StorageService.openBox('pending_downloads_box');
        await pendingBox.delete(lessonId);
      } catch (_) {}

      onComplete();
      return;
        } catch (e, stack) {
          bool isCancelled =
              (e is DioException && e.type == DioExceptionType.cancel);

          if (isCancelled) {
            // User explicitly cancelled — nothing to auto-retry or resume
            // later, so drop the pending record and stop here.
            await notifService.cancelNotification(notificationId);
            try {
              final pendingBox =
                  await StorageService.openBox('pending_downloads_box');
              await pendingBox.delete(lessonId);
            } catch (_) {}
            break;
          }

          final bool isNetworkIssue = _isLikelyConnectivityError(e);
          attempt++;

          if (isNetworkIssue &&
              attempt <= maxAutoRetries &&
              !cancelToken.isCancelled) {
            FirebaseCrashlytics.instance.log(
                "🔁 Download connectivity retry #$attempt for $videoTitle: $e");
            await notifService.showProgressNotification(
              id: notificationId,
              title: "Downloading: $videoTitle",
              body: "Connection lost — retrying automatically...",
              progress: 0,
              maxProgress: 100,
            );
            await Future.delayed(retryDelays[attempt - 1]);
            continue;
          }

          // Out of auto-retries (or a non-network failure): stop looping.
          // The pending-download record stays as-is so the chapter screen
          // can show a manual "Resume" button — we deliberately do NOT
          // delete the partial output file/segment cache here, since that
          // is exactly what lets Resume pick up quickly instead of
          // re-downloading everything.
          FirebaseCrashlytics.instance
              .recordError(e, stack, reason: 'Download Failed');
          await notifService.cancelNotification(notificationId);
          await notifService.showCompletionNotification(
            id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
            title: videoTitle,
            isSuccess: false,
          );
          onError("Download paused. Tap Resume to continue.");
          break;
        }
      }
    } finally {
      _activeDownloads.remove(lessonId);
      _cancelTokens.remove(lessonId);
      activeTitles.remove(lessonId);
      _activeSavePaths.remove(lessonId);

      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;

      if (_activeDownloads.isEmpty) {
        _stopBackgroundService();
      }
    }
  }

  /// ✅ [FIX] Heuristic used to decide whether a failure is the kind that's
  /// worth auto-retrying (connection dropped/timed out) versus a failure
  /// that will just happen again immediately (bad auth, missing link, user
  /// cancellation, etc.) and shouldn't burn retry attempts.
  bool _isLikelyConnectivityError(Object e) {
    if (e is SocketException) return true;
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          return e.error is SocketException;
      }
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('timeout');
  }

  /// ✅ [FIX] Resumes a previously started (but not completed) download
  /// using the metadata saved when it first started — same lesson, same
  /// quality, same course/subject/chapter placement — without needing to
  /// re-open the quality-selection dialog. If the originally resolved link
  /// is missing or has expired, `startDownload` already falls back to
  /// re-resolving a fresh one for the same lesson automatically.
  Future<bool> resumeDownload(
    String lessonId, {
    required Function(double) onProgress,
    required Function() onComplete,
    required Function(String) onError,
  }) async {
    final pendingBox = await StorageService.openBox('pending_downloads_box');
    final Map? data = pendingBox.get(lessonId) is Map
        ? Map.from(pendingBox.get(lessonId) as Map)
        : null;
    if (data == null) return false;

    await startDownload(
      lessonId: lessonId,
      videoTitle: data['videoTitle'] ?? '',
      courseName: data['courseName'] ?? '',
      subjectName: data['subjectName'] ?? '',
      chapterName: data['chapterName'] ?? '',
      folderName: data['folderName'],
      subjectId: data['subjectId'] ?? '',
      downloadUrl: data['downloadUrl'],
      audioUrl: data['audioUrl'],
      isPdf: data['isPdf'] ?? false,
      quality: data['quality'] ?? 'SD',
      duration: data['duration'] ?? '',
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
    return true;
  }

  /// ✅ [FIX] Lets the UI know — synchronously, from whatever's already in
  /// memory/Hive — whether a lesson has an unfinished download it can
  /// offer to resume (as opposed to a fresh "Download" button).
  bool hasResumableDownload(String lessonId) {
    if (!Hive.isBoxOpen('pending_downloads_box')) return false;
    return Hive.box('pending_downloads_box').containsKey(lessonId);
  }


  Future<void> validateAndCleanRevokedDownloads(
      List<String> authorizedSubjects) async {
    try {
      if (!Hive.isBoxOpen('downloads_box')) return;
      var box = Hive.box('downloads_box');
      List<dynamic> keysToDelete = [];

      for (var key in box.keys) {
        var data = box.get(key);
        if (data == null) continue;

        String? sId = data['subjectId'];

        if (sId == null) continue;

        if (!authorizedSubjects.contains(sId)) {
          keysToDelete.add(key);
        }
      }

      for (var key in keysToDelete) {
        var data = box.get(key);
        try {
          if (data['path'] != null) {
            final file = File(data['path']);
            if (await file.exists()) await file.delete();
          }
          if (data['audioPath'] != null) {
            final file = File(data['audioPath']);
            if (await file.exists()) await file.delete();
          }
        } catch (e) {
          debugPrint("Error deleting physical file: $e");
        }
        await box.delete(key);
        debugPrint("🗑️ Deleted revoked file: ${data['title']}");
      }
    } catch (e) {
      debugPrint("Error cleaning downloads: $e");
    }
  }

  // ===========================================================================
  // ⚡ إدارة الـ Isolates والتحميل والتشفير في الخلفية (Zero UI Blocking)
  // ===========================================================================

  /// تحميل ملف PDF الخام على الـ Main Thread ثم نقل التشفير الثقيل لـ Isolate
  Future<void> _runPdfDownloadAndEncrypt({
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required List<int> keyBytes,
    required Function(double) onProgress,
    required CancelToken cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/downloading_${DateTime.now().millisecondsSinceEpoch}.tmp';

    try {
      // 1. تحميل الملف الخام واستقبال الاستجابة
      final response = await _dio.download(
        url,
        tempPath,
        options: Options(headers: headers),
        cancelToken: cancelToken,
        onReceiveProgress: (rec, total) {
          if (total != -1)
            onProgress((rec / total) * 0.90); // نعطي 90% للتحميل و 10% للتشفير
        },
      );
      if (cancelToken.isCancelled)
        throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.cancel);

      // ✅ [FIX F-13] قراءة الهاش القادم من السيرفر والتحقق من سلامة الملف قبل تشفيره
      final expectedHash = response.headers.value('x-file-hash') ??
          response.headers.value('X-File-Hash');
      if (expectedHash != null && expectedHash.isNotEmpty) {
        // حساب الهاش بنظام Stream لتجنب امتلاء الذاكرة
        final fileStream = File(tempPath).openRead();
        final hash = await hash_crypto.sha256.bind(fileStream).first;
        final actualHash = hash.toString();

        // مطابقة البصمة
        if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
          throw Exception(
              "Integrity Check Failed: SHA-256 hash mismatch! File might be tampered with.");
        }
        debugPrint("✅ [F-13] PDF Integrity Check Passed! Hash verified.");
      }

      // 2. تشغيل التشفير في مسار معالج منفصل Isolate (لمنع تجمد الواجهة)
      final ReceivePort port = ReceivePort();
      final isolate = await Isolate.spawn(_pdfEncryptIsolateEntryPoint, {
        'inputPath': tempPath,
        'outputPath': savePath,
        'keyBytes': keyBytes,
        'sendPort': port.sendPort,
      });

      final completer = Completer<void>();

      final cancelSub = cancelToken.whenCancel.then((_) {
        isolate.kill(priority: Isolate.immediate);
        if (!completer.isCompleted)
          completer.completeError(DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.cancel));
      });

      port.listen((message) {
        if (message == 'done') {
          port.close();
          isolate.kill();
          onProgress(1.0);
          if (!completer.isCompleted) completer.complete();
        } else if (message is String && message.startsWith('error:')) {
          port.close();
          isolate.kill();
          if (!completer.isCompleted)
            completer.completeError(Exception(message));
        }
      });

      await completer.future;

      // 3. مسح الملف الخام بعد نجاح التشفير
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();
    } catch (e) {
      try {
        final f = File(tempPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// تحميل وتشفير الفيديوهات (HLS أو MP4) بالكامل داخل Isolate مستقل
  Future<void> _runVideoDownloadIsolate({
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required List<int> keyBytes,
    required CancelToken cancelToken,
    required Function(double) onProgress,
  }) async {
    final ReceivePort port = ReceivePort();

    final isolate = await Isolate.spawn(_videoDownloadIsolateEntryPoint, {
      'sendPort': port.sendPort,
      'url': url,
      'savePath': savePath,
      'headers': headers,
      'keyBytes': keyBytes,
    });

    final completer = Completer<void>();

    final cancelSub = cancelToken.whenCancel.then((_) {
      isolate.kill(priority: Isolate.immediate);
      if (!completer.isCompleted) {
        completer.completeError(DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.cancel));
      }
    });

    port.listen((message) {
      if (message is double) {
        onProgress(message);
      } else if (message == 'done') {
        port.close();
        isolate.kill();
        if (!completer.isCompleted) completer.complete();
      } else if (message is String && message.startsWith('error:')) {
        port.close();
        isolate.kill();
        if (!completer.isCompleted) completer.completeError(Exception(message));
      }
    });

    await completer.future;
  }
}

// ===========================================================================
// 🛡️ Isolates Entry Points
// ===========================================================================

void _pdfEncryptIsolateEntryPoint(Map<String, dynamic> args) async {
  final String inputPath = args['inputPath'];
  final String outputPath = args['outputPath'];
  final List<int> keyBytes = args['keyBytes'];
  final SendPort sendPort = args['sendPort'];

  try {
    final inFile = File(inputPath);
    final outFile = File(outputPath);
    final rafRead = await inFile.open(mode: FileMode.read);
    final iosWrite = outFile.openWrite();

    final algorithm = Chacha20.poly1305Aead();
    final secretKey = SecretKey(keyBytes);
    const CHUNK_SIZE = 32 * 1024;
    const NONCE_LENGTH = 12;

    final int fileLength = await inFile.length();
    int currentPos = 0;

    while (currentPos < fileLength) {
      final chunk = await rafRead.read(CHUNK_SIZE);
      final nonce =
          List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
      final secretBox =
          await algorithm.encrypt(chunk, secretKey: secretKey, nonce: nonce);

      iosWrite.add(nonce);
      iosWrite.add(secretBox.cipherText);
      iosWrite.add(secretBox.mac.bytes);
      currentPos += chunk.length;
    }
    await rafRead.close();
    await iosWrite.close();
    sendPort.send('done');
  } catch (e) {
    sendPort.send('error: $e');
  }
}

void _videoDownloadIsolateEntryPoint(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'];
  try {
    final String url = args['url'];
    final String savePath = args['savePath'];
    final Map<String, dynamic> rawHeaders = args['headers'];
    final List<int> keyBytes = args['keyBytes'];

    final Map<String, String> headers =
        rawHeaders.map((key, value) => MapEntry(key, value.toString()));

    final algorithm = Chacha20.poly1305Aead();
    final secretKey = SecretKey(keyBytes);
    const int CHUNK_SIZE = 32 * 1024;
    const int NONCE_LENGTH = 12;
    // ✅ [FIX] needed to work out how many whole encrypted blocks already sit
    // on disk from a previous, interrupted attempt (see resume logic below).
    const int MAC_LENGTH = 16;
    const int ENCRYPTED_CHUNK_SIZE = NONCE_LENGTH + CHUNK_SIZE + MAC_LENGTH;

    Future<Uint8List> encryptData(List<int> data) async {
      final nonce =
          List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
      final box =
          await algorithm.encrypt(data, secretKey: secretKey, nonce: nonce);
      final builder = BytesBuilder(copy: false);
      builder.add(nonce);
      builder.add(box.cipherText);
      builder.add(box.mac.bytes);
      return builder.toBytes();
    }

    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60)));

    if (url.contains('.m3u8') || url.contains('.m3u')) {
      final response = await dio.get(url, options: Options(headers: headers));
      final content = response.data.toString();
      final baseUrl = url.substring(0, url.lastIndexOf('/') + 1);
      List<String> tsUrls = [];

      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('#')) {
          tsUrls.add(line.startsWith('http') ? line : baseUrl + line);
        }
      }

      if (tsUrls.isEmpty) throw Exception("No TS segments found");

      // ✅ [FIX] Per-segment disk cache so an interrupted HLS download can
      // resume — automatically (simply calling startDownload again for the
      // same lesson) or manually (a "Resume" button that does the same) —
      // without re-downloading segments that already finished. This also
      // means a segment that fails is retried and, if it still fails, the
      // whole isolate throws instead of silently being skipped. Previously
      // a failed segment was swallowed and counted as "done" anyway, which
      // is why a video with a mid-download connection drop would report
      // "download complete" while actually missing a chunk of the middle
      // or end of the file (e.g. only the first 5 minutes of a 1 hour
      // video would ever get written).
      final segDir = Directory('$savePath.segments');
      if (!await segDir.exists()) await segDir.create(recursive: true);

      Future<List<int>> fetchSegment(String segUrl, int index) async {
        final cacheFile = File('${segDir.path}/seg_$index.ts');
        if (await cacheFile.exists()) {
          final len = await cacheFile.length();
          if (len > 0) {
            try {
              return await cacheFile.readAsBytes();
            } catch (_) {
              // Cached copy unreadable/corrupt — fall through and re-fetch.
            }
          }
        }

        Object? lastError;
        for (int attempt = 0; attempt < 4; attempt++) {
          try {
            final rs = await dio.get<List<int>>(segUrl,
                options: Options(
                    headers: headers,
                    responseType: ResponseType.bytes,
                    receiveTimeout: const Duration(seconds: 20)));
            final data = rs.data;
            if (data == null || data.isEmpty) {
              throw Exception("Empty segment response");
            }
            await cacheFile.writeAsBytes(data, flush: true);
            return data;
          } catch (e) {
            lastError = e;
            if (attempt < 3) {
              await Future.delayed(Duration(seconds: 1 + attempt));
            }
          }
        }
        // Segment genuinely failed after retries. Throw (instead of
        // returning null and silently moving on) so the download is marked
        // as failed rather than falsely "complete" — the segments already
        // cached on disk are left in place so the next attempt can resume
        // from here instead of starting over.
        throw Exception("Segment $index failed after retries: $lastError");
      }

      final file = File(savePath);
      final sink = await file.open(mode: FileMode.write);
      List<int> buffer = [];
      int total = tsUrls.length;
      int done = 0;
      const int batchSize = 8;

      try {
        for (int i = 0; i < total; i += batchSize) {
          int end = min(i + batchSize, total);
          List<Future<List<int>>> futures = [];
          for (int j = i; j < end; j++) {
            futures.add(fetchSegment(tsUrls[j], j));
          }

          List<List<int>> results = await Future.wait(futures);
          for (var data in results) {
            buffer.addAll(data);
            while (buffer.length >= CHUNK_SIZE) {
              final block = buffer.sublist(0, CHUNK_SIZE);
              buffer.removeRange(0, CHUNK_SIZE);
              final enc = await encryptData(block);
              await sink.writeFrom(enc);
            }
            done++;
            sendPort.send(done / total);
          }
        }
        if (buffer.isNotEmpty) {
          final enc = await encryptData(buffer);
          await sink.writeFrom(enc);
        }
        await sink.close();

        // ✅ Success — the raw segment cache is no longer needed.
        try {
          if (await segDir.exists()) await segDir.delete(recursive: true);
        } catch (_) {}

        sendPort.send('done');
        return;
      } catch (e) {
        await sink.close();
        // NOTE: we intentionally do NOT delete segDir here — those already
        // -downloaded segments are exactly what let a retry/resume finish
        // quickly instead of re-downloading the whole video from scratch.
        rethrow;
      }
    }

    int totalBytes = 0;
    try {
      final headRes = await dio.head(url, options: Options(headers: headers));
      totalBytes =
          int.parse(headRes.headers.value(Headers.contentLengthHeader) ?? '0');
    } catch (_) {}

    final file = File(savePath);

    // ✅ [FIX] Resume support for direct MP4/progressive downloads: if a
    // previous attempt was interrupted (connection dropped, app killed,
    // etc.) partway through, don't discard that progress — figure out how
    // many whole encrypted blocks are already safely on disk and continue
    // from there with an HTTP Range request instead of starting over.
    int downloadedBytes = 0;
    FileMode sinkMode = FileMode.write;
    if (totalBytes > 0 && await file.exists()) {
      final existingLen = await file.length();
      final completeChunks = existingLen ~/ ENCRYPTED_CHUNK_SIZE;
      final alignedLen = completeChunks * ENCRYPTED_CHUNK_SIZE;
      final resumableBytes = completeChunks * CHUNK_SIZE;
      if (completeChunks > 0 && resumableBytes < totalBytes) {
        try {
          final raf = await file.open(mode: FileMode.append);
          // Drop any trailing partial/unconfirmed block from a previous
          // crash before appending fresh data after it.
          await raf.truncate(alignedLen);
          await raf.close();
          downloadedBytes = resumableBytes;
          sinkMode = FileMode.append;
        } catch (_) {
          // If anything about the existing file looks off, fall back to a
          // clean re-download rather than risk a corrupt result.
          downloadedBytes = 0;
          sinkMode = FileMode.write;
        }
      }
    }

    final sink = await file.open(mode: sinkMode);
    List<int> buffer = [];

    if (totalBytes <= 0) {
      final res = await dio.get(url,
          options:
              Options(responseType: ResponseType.stream, headers: headers));
      int received = 0;
      int total =
          int.parse(res.headers.value(Headers.contentLengthHeader) ?? '-1');
      Stream<Uint8List> stream = res.data.stream;

      await for (final chunk in stream) {
        buffer.addAll(chunk);
        while (buffer.length >= CHUNK_SIZE) {
          final block = buffer.sublist(0, CHUNK_SIZE);
          buffer.removeRange(0, CHUNK_SIZE);
          final enc = await encryptData(block);
          await sink.writeFrom(enc);
        }
        received += chunk.length;
        if (total != -1) sendPort.send(received / total);
      }
      if (buffer.isNotEmpty) {
        final enc = await encryptData(buffer);
        await sink.writeFrom(enc);
      }
      await sink.close();
      sendPort.send('done');
      return;
    }

    const int reqChunkSize = 1 * 1024 * 1024;
    // downloadedBytes may already be non-zero here if we resumed above.

    while (downloadedBytes < totalBytes) {
      int start = downloadedBytes;
      int end = min(start + reqChunkSize - 1, totalBytes - 1);

      bool chunkSuccess = false;
      int retries = 5;

      while (retries > 0 && !chunkSuccess) {
        try {
          final res = await dio.get(url,
              options: Options(
                  responseType: ResponseType.stream,
                  headers: {...headers, 'Range': 'bytes=$start-$end'}));

          Stream<Uint8List> stream = res.data.stream;
          await for (final chunk in stream) {
            buffer.addAll(chunk);
            while (buffer.length >= CHUNK_SIZE) {
              final block = buffer.sublist(0, CHUNK_SIZE);
              buffer.removeRange(0, CHUNK_SIZE);
              final enc = await encryptData(block);
              await sink.writeFrom(enc);
            }
          }
          chunkSuccess = true;
          downloadedBytes += (end - start + 1);
          sendPort.send(downloadedBytes / totalBytes);
        } catch (e) {
          retries--;
          if (retries == 0)
            throw Exception("Failed to download chunk after retries");
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (buffer.isNotEmpty) {
      final enc = await encryptData(buffer);
      await sink.writeFrom(enc);
    }
    await sink.close();
    sendPort.send('done');
  } catch (e) {
    sendPort.send('error: $e');
  }
}
