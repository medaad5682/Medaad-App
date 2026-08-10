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
import 'package:cryptography/cryptography.dart';
// ✅ [FIX F-13] استدعاء مكتبة التشفير لحساب بصمة الملفات المحملة
import 'package:crypto/crypto.dart' as hash_crypto;

import 'notification_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../constants/api_constants.dart';
import 'file_crypto_service.dart';

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

    try {
      // ✅ [FIX] جلب مفتاح التشفير ChaCha20 عبر FileCryptoService.init() بدل
      // قراءة/كتابة Keychain مباشرة بمثيل FlutterSecureStorage خاص وغير
      // محمي هنا. النسخة القديمة كانت تستخدم صنف الحماية الافتراضي
      // (whenUnlocked) بلا انتظار _AppReadyGate وبلا إعادة محاولة — وهي
      // بالضبط إعدادات -25308 التي أُصلحت في كل مكان آخر إلا هنا. كانت
      // مشكلة مضاعفة: (أ) قد يفشل التحميل برسالة مضللة "تحقق من الإنترنت"
      // حين تفشل قراءة Keychain فعلياً، و(ب) لو كان هذا أول مسار يلمس
      // 'docs_chacha_key' على الجهاز (تحميل مباشر قبل فتح شاشة الملفات
      // المحملة قط)، كان يُنشئ المفتاح بصنف حماية whenUnlocked بدل
      // first_unlock_this_device المستخدم في بقية التطبيق — وaccessibility
      // لا يُرحَّل تلقائياً لعنصر Keychain موجود بالفعل.
      //
      // FileCryptoService.init() يعيد استخدام المفتاح المخزَّن في الذاكرة
      // إن كان قد هُيِّئ بالفعل (مثال: عبر LocalProxyService.start())، أو
      // يقرأه/يولّده بأمان تام عبر StorageService.readSecureValueSafely /
      // writeSecureValueSafely — بنفس صنف الحماية first_unlock_this_device
      // ونفس منطق الانتظار وإعادة المحاولة المستخدم لكل مفتاح آخر في
      // التطبيق. هذا يضمن أن كل مسار يلمس 'docs_chacha_key' (شاشة التحميلات،
      // عارض PDF، بدء تحميل جديد) يمر بنفس البوابة الآمنة الوحيدة، فلا يوجد
      // بعد الآن أي احتمال لمفتاحين مختلفين بصنفي حماية مختلفين لنفس العنصر.
      await FileCryptoService.init();
      final String? storedKey = FileCryptoService.keyBase64;
      if (storedKey == null || storedKey.isEmpty) {
        throw Exception(
            "CRITICAL: docs_chacha_key unavailable — FileCryptoService.init() did not produce a key.");
      }
      final List<int> chachaKeyBytes = base64Decode(storedKey);

      var box = await StorageService.openBox('auth_box');
      final deviceId = box.get('device_id');
      final token = box.get('jwt_token');
      const String appSecret = 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only';

      // ✅ جلب توكن الـ App Check
      String? appCheckToken;
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken();
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
      onComplete();
    } catch (e, stack) {
      await notifService.cancelNotification(notificationId);
      bool isCancelled =
          (e is DioException && e.type == DioExceptionType.cancel);

      if (!isCancelled) {
        FirebaseCrashlytics.instance
            .recordError(e, stack, reason: 'Download Failed');
        await notifService.showCompletionNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
          title: videoTitle,
          isSuccess: false,
        );
        onError("Download failed. Please check internet.");
      }

      // Cleanup partial files
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final safeCourse =
            courseName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
        final safeSubject =
            subjectName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
        final safeChapter =
            chapterName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
        final dirPath =
            '${appDir.path}/offline_content/$safeCourse/$safeSubject/$safeChapter';

        final videoFileName =
            isPdf ? "$lessonId.pdf.enc" : "vid_${lessonId}_${quality}_v2.enc";
        final audioFileName = 'aud_${lessonId}_hq_v2.enc';

        final videoFile = File('$dirPath/$videoFileName');
        if (await videoFile.exists()) await videoFile.delete();

        final audioFile = File('$dirPath/$audioFileName');
        if (await audioFile.exists()) await audioFile.delete();
      } catch (_) {}
    } finally {
      _activeDownloads.remove(lessonId);
      _cancelTokens.remove(lessonId);
      activeTitles.remove(lessonId);

      var prog = Map<String, double>.from(downloadingProgress.value);
      prog.remove(lessonId);
      downloadingProgress.value = prog;

      if (_activeDownloads.isEmpty) {
        _stopBackgroundService();
      }
    }
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

      final file = File(savePath);
      final sink = await file.open(mode: FileMode.write);
      List<int> buffer = [];
      int total = tsUrls.length;
      int done = 0;
      const int batchSize = 8;

      for (int i = 0; i < total; i += batchSize) {
        int end = min(i + batchSize, total);
        List<String> batchUrls = tsUrls.sublist(i, end);
        List<Future<List<int>?>> futures = batchUrls.map((u) async {
          try {
            final rs = await dio.get<List<int>>(u,
                options: Options(
                    headers: headers,
                    responseType: ResponseType.bytes,
                    receiveTimeout: const Duration(seconds: 20)));
            return rs.data;
          } catch (e) {
            return null;
          }
        }).toList();

        List<List<int>?> results = await Future.wait(futures);
        for (var data in results) {
          if (data != null) {
            buffer.addAll(data);
            while (buffer.length >= CHUNK_SIZE) {
              final block = buffer.sublist(0, CHUNK_SIZE);
              buffer.removeRange(0, CHUNK_SIZE);
              final enc = await encryptData(block);
              await sink.writeFrom(enc);
            }
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
      sendPort.send('done');
      return;
    }

    int totalBytes = 0;
    try {
      final headRes = await dio.head(url, options: Options(headers: headers));
      totalBytes =
          int.parse(headRes.headers.value(Headers.contentLengthHeader) ?? '0');
    } catch (_) {}

    final file = File(savePath);
    final sink = await file.open(mode: FileMode.write);
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
    int downloadedBytes = 0;

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
