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
    // ✅ [FIX] `detached` used to call cancelAllDownloads(), which treats the
    // app's engine detaching the same as the user explicitly tapping Cancel
    // — including deleting the HLS resume metadata (segDir) AND the
    // pending_downloads_box record. Because this app runs a background
    // service, a force-close (swipe away from recents) can fire `detached`
    // while the isolate keeps running briefly before the OS finally kills
    // the process — long enough for the segDir delete to finish but not
    // always long enough to also reach the pendingBox delete just after it.
    // Net effect: Resume button still shows (record survived), but the
    // resume metadata is already gone, so it silently restarts from 0%.
    // `detached` is an environment signal, not the user giving up on the
    // download — it should be treated like Pause (halt network activity,
    // keep everything needed to resume), not like Cancel.
    if (state == AppLifecycleState.detached) {
      _pauseAllForLifecycle();
    }
  }

  Future<void> _pauseAllForLifecycle() async {
    final List<String> allIds = List.from(_cancelTokens.keys);
    for (var id in allIds) {
      await pauseDownload(id);
    }
    _stopBackgroundService();
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
  // ✅ [PAUSE] Set right before cancelling a token from pauseDownload(), so
  // the catch block in startDownload can tell "user tapped Pause" apart
  // from "user tapped Cancel" even though both surface as the exact same
  // DioExceptionType.cancel — the reason string passed to CancelToken.cancel()
  // doesn't survive the isolate boundary, so this side-channel set is how
  // that intent is actually communicated back.
  static final Set<String> _pausedLessonIds = {};
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
    _pausedLessonIds.remove(lessonId);
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

  /// ✅ [PAUSE] Stops an in-progress download's network activity right
  /// away, same as cancelDownload — but, unlike cancelDownload, this is
  /// NOT a "give up on this download" action: it deliberately leaves the
  /// HLS segment cache and the pending_downloads_box record untouched, so
  /// the item just moves from "Active" to "Paused" in the Downloads
  /// screen and a later tap on "Resume" (resumeDownload) picks up exactly
  /// where this left off, same as if the connection had dropped.
  Future<void> pauseDownload(String lessonId) async {
    if (_cancelTokens.containsKey(lessonId)) {
      _pausedLessonIds.add(lessonId);
      try {
        _cancelTokens[lessonId]?.cancel("User paused download");
      } catch (e) {
        debugPrint("Error pausing token: $e");
      }
      _cancelTokens.remove(lessonId);
    }

    _activeDownloads.remove(lessonId);
    activeTitles.remove(lessonId);
    _activeSavePaths.remove(lessonId);

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
    // ✅ [FIX] Tracks the furthest aggregated progress reached so far across
    // every attempt in this single startDownload() call. `attempt` used to
    // be a lifetime counter for the whole call — once 3 failures happened
    // ANYWHERE (even far apart, with real progress made in between), the
    // very next hiccup would give up for good with "failed", no matter how
    // close to 100% the download was. That's exactly what produced the
    // "resumes fine from 56% up to 98%, then suddenly fails" reports: on a
    // long/flaky download it's easy to hit 2-3 transient blips well before
    // the end, quietly using up the whole retry budget, so the blip right
    // near completion has nothing left and hard-fails instead of
    // auto-retrying like all the earlier ones did. See the reset below.
    double bestProgressSoFar = 0.0;
    double progressAtLastFailure = 0.0;

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
              if (p > bestProgressSoFar) bestProgressSoFar = p;
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
          if (total > bestProgressSoFar) bestProgressSoFar = total;

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
            // ✅ [PAUSE] Distinguish "user tapped Pause" from "user tapped
            // Cancel" — both throw the exact same DioExceptionType.cancel,
            // so pauseDownload() marks the intent in _pausedLessonIds right
            // before cancelling the token.
            final bool wasPaused = _pausedLessonIds.remove(lessonId);
            await notifService.cancelNotification(notificationId);
            if (wasPaused) {
              // Leave the pending record + segment cache exactly as-is so
              // Resume picks up from here — nothing else to do.
              break;
            }
            // User explicitly cancelled — this download isn't coming back
            // automatically, so drop the pending record and stop here.
            try {
              final pendingBox =
                  await StorageService.openBox('pending_downloads_box');
              await pendingBox.delete(lessonId);
            } catch (_) {}
            break;
          }

          // ✅ [FIX] A 401/403 partway through means the signed CDN link
          // (captured once, up front, when the user picked a quality) has
          // expired — this is exactly what happens when a download sits
          // paused for a long time (app force-closed, resumed much later)
          // rather than a short connection blip. Retrying the same url, or
          // just showing "tap Resume", would only reuse that same dead
          // link again — the saved segment cache means most of the file is
          // already there, so it can look like it's about to finish and
          // then fail right near the end. Instead, clear the stale link so
          // the top of the loop re-resolves a fresh one via get-video-id
          // and keeps going from the cached progress.
          final bool isExpiredLink = e is LinkExpiredException;
          final bool isNetworkIssue = _isLikelyConnectivityError(e);

          // ✅ [FIX] Only count this as one more strike against the shared
          // retry budget if we HAVEN'T made any real progress since the
          // last failure. If we have, this is a fresh problem on
          // previously-solid ground — give it a full new budget instead of
          // letting old, already-recovered-from failures count against it.
          if (bestProgressSoFar > progressAtLastFailure + 0.01) {
            attempt = 0;
          }
          progressAtLastFailure = bestProgressSoFar;
          attempt++;

          if (isExpiredLink &&
              attempt <= maxAutoRetries &&
              !cancelToken.isCancelled) {
            FirebaseCrashlytics.instance.log(
                "🔄 Download link expired for $videoTitle — fetching a fresh link (retry #$attempt)");
            downloadUrl = null;
            audioUrl = null;
            try {
              final pendingBox =
                  await StorageService.openBox('pending_downloads_box');
              final existing = pendingBox.get(lessonId);
              if (existing is Map) {
                final updated = Map<String, dynamic>.from(existing);
                updated['downloadUrl'] = null;
                updated['audioUrl'] = null;
                await pendingBox.put(lessonId, updated);
              }
            } catch (_) {}
            await notifService.showProgressNotification(
              id: notificationId,
              title: "Downloading: $videoTitle",
              body: "Refreshing expired link...",
              progress: 0,
              maxProgress: 100,
            );
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

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
            // ✅ [FIX] If we gave up specifically because the connection
            // kept dropping (as opposed to some other failure), tell the
            // user that explicitly and point them at the Resume button
            // instead of a generic "failed" message that gives no next
            // step.
            failureMessage: isExpiredLink
                ? "Download link expired. Tap Resume to fetch a fresh link and continue $videoTitle."
                : isNetworkIssue
                ? "No internet connection. Tap Resume to continue $videoTitle when you're back online."
                : null,
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
        case DioExceptionType.badResponse:
          // 401/403 are handled separately as an expired signed link, and
          // other 4xx (400/404/etc) are genuine, non-retryable problems —
          // but a 429 or 5xx from the CDN is a transient server hiccup
          // worth another try, same as a dropped connection.
          final status = e.response?.statusCode ?? 0;
          return status == 429 || (status >= 500 && status < 600);
        default:
          return e.error is SocketException;
      }
    }
    // ✅ [FIX] By the time an error crosses the isolate boundary (see
    // `_videoDownloadIsolateEntryPoint`'s `sendPort.send('error: $e')`), all
    // type information is gone — it arrives here as a plain Exception whose
    // message is just the original error's toString(). So this string
    // fallback is actually the ONLY check that matters for real
    // video/audio download failures, and the old narrow list of substrings
    // missed plenty of everyday transient errors — especially the kind
    // that show up right after a cold app start / network hand-off
    // (Wi-Fi <-> mobile data switching, radio waking up, DNS not ready
    // yet): "Software caused connection abort", TLS handshake resets,
    // "Connection refused", "Broken pipe", etc. Any of those used to fall
    // straight through to an immediate, un-retried hard failure instead of
    // the same auto-retry a plain dropped connection gets.
    final msg = e.toString().toLowerCase();
    const transientMarkers = [
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'connection closed',
      'connection reset',
      'connection refused',
      'connection abort',
      'broken pipe',
      'timeout',
      'timed out',
      'handshake',
      'tlsexception',
      'httpexception',
      'os error',
      'stream closed',
      'unexpected end of stream',
      'no route to host',
      'client exception',
    ];
    return transientMarkers.any(msg.contains);
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
  // ✅ [SECURITY FIX] Replaces the old download→plaintext-temp-file→encrypt
  // pipeline. That flow always materialized the *entire* PDF as plaintext
  // bytes in the OS temp directory for the full duration of the download
  // (and again while hashing it), deleted only after encryption succeeded —
  // and left behind on a crash. This now streams the download straight into
  // the same single isolate that hashes and encrypts it in 32KB blocks as
  // the bytes arrive, exactly like the direct-MP4 path below: only small
  // in-RAM buffers ever hold plaintext, and disk only ever sees ciphertext.
  Future<void> _runPdfDownloadAndEncrypt({
    required String url,
    required String savePath,
    required Map<String, dynamic> headers,
    required List<int> keyBytes,
    required Function(double) onProgress,
    required CancelToken cancelToken,
  }) async {
    final ReceivePort port = ReceivePort();

    final isolate = await Isolate.spawn(_pdfDownloadIsolateEntryPoint, {
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
        onProgress(1.0);
        if (!completer.isCompleted) completer.complete();
      } else if (message == 'link_expired') {
        port.close();
        isolate.kill();
        if (!completer.isCompleted) completer.completeError(LinkExpiredException());
      } else if (message is String && message.startsWith('error:')) {
        port.close();
        isolate.kill();
        if (!completer.isCompleted) completer.completeError(Exception(message));
      }
    });

    await completer.future;
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
      } else if (message == 'link_expired') {
        port.close();
        isolate.kill();
        if (!completer.isCompleted) {
          completer.completeError(LinkExpiredException());
        }
      } else if (message is String && message.startsWith('error:')) {
        port.close();
        isolate.kill();
        if (!completer.isCompleted) completer.completeError(Exception(message));
      }
    });

    await completer.future;
  }
}

/// ✅ [FIX] Thrown (in the MAIN isolate) when a download isolate reports
/// that the signed CDN link it was using has expired (401/403 from the
/// server). Distinguished from a generic failure so `startDownload` can
/// automatically fetch a fresh link and keep going, instead of treating it
/// as a dead end that only a manual "Resume" tap can fix — and instead of
/// pointlessly burning connectivity-retry attempts on a link that will
/// never start working again no matter how many times it's retried as-is.
class LinkExpiredException implements Exception {
  @override
  String toString() => 'Download link expired';
}

// ===========================================================================
// 🛡️ Isolates Entry Points
// ===========================================================================

// ✅ [SECURITY FIX] Streams the PDF download, rolling SHA-256 hash, and
// ChaCha20-Poly1305 encryption together in one pass, inside one isolate.
// No plaintext PDF byte ever touches disk: each network chunk is hashed and
// buffered in memory only, and once the buffer holds a full 32KB block it is
// immediately encrypted and written to `savePath`. Only ciphertext exists on
// disk at any point.
void _pdfDownloadIsolateEntryPoint(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'];
  final String savePath = args['savePath'];
  try {
    final String url = args['url'];
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

    Response res;
    try {
      res = await dio.get(url,
          options:
              Options(responseType: ResponseType.stream, headers: headers));
    } catch (e) {
      if (_isExpiredLinkError(e)) throw _ExpiredLinkSignal();
      rethrow;
    }

    // ✅ [FIX F-13] Header is available as soon as the response comes back,
    // before the body stream is drained, so the integrity check can still
    // run against every byte — just via a rolling hash instead of a second
    // read pass over a fully-materialized plaintext file.
    final expectedHash =
        res.headers.value('x-file-hash') ?? res.headers.value('X-File-Hash');
    final int total =
        int.parse(res.headers.value(Headers.contentLengthHeader) ?? '-1');

    final digestSink = _DigestCollectorSink();
    final hashSink = hash_crypto.sha256.startChunkedConversion(digestSink);

    final file = File(savePath);
    final sink = await file.open(mode: FileMode.write);
    List<int> buffer = [];
    int received = 0;

    final Stream<Uint8List> stream = res.data.stream;
    await for (final chunk in stream) {
      hashSink.add(chunk);
      buffer.addAll(chunk);
      while (buffer.length >= CHUNK_SIZE) {
        final block = buffer.sublist(0, CHUNK_SIZE);
        buffer.removeRange(0, CHUNK_SIZE);
        final enc = await encryptData(block);
        await sink.writeFrom(enc);
      }
      received += chunk.length;
      // Reserve the last 2% for the tail-buffer flush + hash verification
      // below, same budget the old flow gave to its separate encrypt pass.
      if (total != -1) sendPort.send((received / total) * 0.98);
    }
    if (buffer.isNotEmpty) {
      final enc = await encryptData(buffer);
      await sink.writeFrom(enc);
    }
    await sink.close();

    hashSink.close();
    final actualHash = digestSink.digest.toString();

    if (expectedHash != null && expectedHash.isNotEmpty) {
      if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
        try {
          await file.delete();
        } catch (_) {}
        throw Exception(
            "Integrity Check Failed: SHA-256 hash mismatch! File might be tampered with.");
      }
    }

    sendPort.send(1.0);
    sendPort.send('done');
  } catch (e) {
    try {
      final f = File(savePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (e is _ExpiredLinkSignal) {
      sendPort.send('link_expired');
    } else {
      sendPort.send('error: $e');
    }
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
      Response response;
      try {
        response = await dio.get(url, options: Options(headers: headers));
      } catch (e) {
        if (_isExpiredLinkError(e)) throw _ExpiredLinkSignal();
        rethrow;
      }
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

      // ✅ [SECURITY FIX] Resume support no longer caches raw segment bytes
      // to disk (that used to leave the entire video's plaintext sitting in
      // `<savePath>.segments/seg_N.ts` files until the whole download
      // finished, and left behind on a crash). Instead we persist only the
      // BYTE LENGTH of each segment once it's been downloaded — a few
      // bytes of metadata, never content — alongside the same
      // whole-encrypted-block accounting the direct-MP4 path already uses
      // below (`existingLen ~/ ENCRYPTED_CHUNK_SIZE`) to work out exactly
      // how many raw input bytes are already safely encrypted on disk. From
      // that we can tell which segments are already fully consumed (skip
      // them — no need to ever see their bytes again) and, at most, which
      // ONE segment straddles the resume point (re-fetch just that one to
      // refill the in-memory buffer). Every segment's plaintext exists only
      // transiently in RAM, exactly like the direct-MP4 path.
      final segDir = Directory('$savePath.segments');
      if (!await segDir.exists()) await segDir.create(recursive: true);
      final metaFile = File('${segDir.path}/meta.json');

      final int total = tsUrls.length;
      List<int?> segLengths = List<int?>.filled(total, null);

      // ✅ [FIX] Segments download in concurrent batches of 8, so
      // persistMeta() can be called by several segments' fetches at once.
      // An unguarded writeAsString() to the same file lets these races out
      // of order: if a slightly-behind write happens to land on disk AFTER
      // a more-complete one, the file silently REGRESSES to a less-complete
      // snapshot — permanently losing a segment's recorded length, which
      // then breaks the resume walk below and forces a full restart. This
      // chain guarantees writes commit strictly in enqueue order, so a
      // later (more complete) snapshot can never be clobbered by an earlier
      // one finishing its disk I/O late.
      Future<void> metaWriteChain = Future.value();
      Future<void> persistMeta() {
        metaWriteChain = metaWriteChain.then((_) async {
          try {
            await metaFile.writeAsString(
                jsonEncode(segLengths.map((l) => l ?? 0).toList()),
                flush: true);
          } catch (_) {
            // Best-effort — worst case a future resume falls back to a
            // clean restart, which is safe, just not optimally fast.
          }
        });
        return metaWriteChain;
      }

      if (await metaFile.exists()) {
        try {
          final decoded = jsonDecode(await metaFile.readAsString());
          if (decoded is List) {
            for (int i = 0; i < decoded.length && i < total; i++) {
              final v = decoded[i];
              if (v is int && v > 0) segLengths[i] = v;
            }
          }
        } catch (_) {
          // Corrupt/unreadable metadata — treated as "no metadata" below.
        }
      }

      final file = File(savePath);
      int existingLen = 0;
      if (await file.exists()) existingLen = await file.length();
      int completeChunks = existingLen ~/ ENCRYPTED_CHUNK_SIZE;
      int resumableRawBytes = completeChunks * CHUNK_SIZE;

      // Walk the known segment lengths to find exactly which segment index
      // the resume point falls in, and how far into that segment it falls.
      int resumeSegIndex = 0;
      int localOffsetInSeg = 0;
      if (resumableRawBytes > 0) {
        int cum = 0;
        bool located = false;
        for (int i = 0; i < total; i++) {
          final len = segLengths[i];
          if (len == null) break; // metadata doesn't reach this far
          if (cum + len > resumableRawBytes) {
            resumeSegIndex = i;
            localOffsetInSeg = resumableRawBytes - cum;
            located = true;
            break;
          }
          cum += len;
        }
        if (!located && cum == resumableRawBytes) {
          resumeSegIndex = 0;
          for (int i = 0; i < total; i++) {
            if (segLengths[i] == null) {
              resumeSegIndex = i;
              break;
            }
          }
          localOffsetInSeg = 0;
          located = true;
        }
        if (!located) {
          // Metadata doesn't account for the bytes the encrypted output
          // claims to have — can't safely map a resume point. Fall back to
          // a clean restart rather than risk skipping unverified data.
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          existingLen = 0;
          completeChunks = 0;
          resumableRawBytes = 0;
          resumeSegIndex = 0;
          localOffsetInSeg = 0;
          segLengths = List<int?>.filled(total, null);
        }
      }

      if (resumeSegIndex > 0) {
        sendPort.send(resumeSegIndex / total);
      }

      Future<List<int>> fetchSegment(String segUrl, int index) async {
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
            segLengths[index] = data.length;
            await persistMeta();
            return data;
          } catch (e) {
            // ✅ A 401/403 means the signed CDN link itself has expired —
            // retrying the SAME url will just fail again 4 times in a row
            // (wasting time right as the download is almost done). Bail
            // out immediately so the caller can fetch a fresh link instead
            // of grinding through pointless retries.
            if (_isExpiredLinkError(e)) throw _ExpiredLinkSignal();
            lastError = e;
            if (attempt < 3) {
              await Future.delayed(Duration(seconds: 1 + attempt));
            }
          }
        }
        // Segment genuinely failed after retries. Throw (instead of
        // returning null and silently moving on) so the download is marked
        // as failed rather than falsely "complete" — the segment-length
        // metadata already persisted is left in place so the next attempt
        // can resume from here instead of starting over.
        throw Exception("Segment $index failed after retries: $lastError");
      }

      if (resumeSegIndex > 0) {
        // Drop any trailing partial/unconfirmed encrypted block from a
        // previous crash before appending fresh data after it — same
        // truncate-then-append idiom the direct-MP4 resume path below uses.
        final raf = await file.open(mode: FileMode.append);
        await raf.truncate(completeChunks * ENCRYPTED_CHUNK_SIZE);
        await raf.close();
      }
      final sink = await file.open(
          mode: resumeSegIndex > 0 ? FileMode.append : FileMode.write);
      List<int> buffer = [];
      int done = resumeSegIndex;
      const int batchSize = 8;

      try {
        // The segment straddling the resume point (if any) has no
        // persisted content — re-fetch it and discard only the prefix
        // bytes that were already encrypted+flushed in a previous attempt.
        if (localOffsetInSeg > 0) {
          final data = await fetchSegment(tsUrls[resumeSegIndex], resumeSegIndex);
          buffer.addAll(data.sublist(localOffsetInSeg));
          done++;
          sendPort.send(done / total);
        }
        final int startIndex = resumeSegIndex + (localOffsetInSeg > 0 ? 1 : 0);

        for (int i = startIndex; i < total; i += batchSize) {
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

        // ✅ Success — the segment-length metadata is no longer needed.
        try {
          if (await segDir.exists()) await segDir.delete(recursive: true);
        } catch (_) {}

        sendPort.send('done');
        return;
      } catch (e) {
        await sink.close();
        // NOTE: we intentionally do NOT delete segDir here — the persisted
        // segment-length metadata (never content) is exactly what lets a
        // retry/resume skip already-consumed segments instead of
        // re-downloading the whole video from scratch.
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
    // ✅ [FIX] Unlike the HLS branch above (which already closes its sink
    // before rethrowing on failure), this progressive/MP4 branch used to
    // leave `sink` open whenever it threw — the outer catch at the very
    // bottom of this function only sends an 'error'/'link_expired' message,
    // it never closes this sink. `isolate.kill()` is then called back on
    // the main isolate the moment that message arrives, which can happen
    // before any buffered-but-unflushed bytes from the last successful
    // write are guaranteed to have hit disk. On a normal in-app retry this
    // was rarely noticed (the isolate died anyway, and the next attempt
    // just re-scans the file), but it meant the file's last few KB right
    // before a failure weren't reliably durable — worth closing cleanly
    // every time so a resume always starts from a fully-flushed byte
    // count.
    bool sinkClosed = false;
    Future<void> closeSinkOnce() async {
      if (sinkClosed) return;
      sinkClosed = true;
      try {
        await sink.close();
      } catch (_) {}
    }

    List<int> buffer = [];

    try {
      // ✅ [FIX] Same as the HLS path above: report the resume point right
      // away instead of letting the UI sit at 0% until the first network
      // chunk lands. This is what actually stops the progress bar from
      // visibly starting at 0% on resume.
      if (downloadedBytes > 0 && totalBytes > 0) {
        sendPort.send(downloadedBytes / totalBytes);
      }

      if (totalBytes <= 0) {
        Response res;
        try {
          res = await dio.get(url,
              options: Options(
                  responseType: ResponseType.stream, headers: headers));
        } catch (e) {
          if (_isExpiredLinkError(e)) throw _ExpiredLinkSignal();
          rethrow;
        }
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
        await closeSinkOnce();
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
            // ✅ [FIX] Same reasoning as the HLS segment loop above: a
            // 401/403 means the signed link expired mid-download (most
            // common when a paused download is resumed a long time after it
            // was started) — retrying the same url won't help, so surface it
            // distinctly instead of burning all 5 retries first.
            if (_isExpiredLinkError(e)) throw _ExpiredLinkSignal();
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
      await closeSinkOnce();
      sendPort.send('done');
    } catch (e) {
      await closeSinkOnce();
      rethrow;
    }
  } catch (e) {
    if (e is _ExpiredLinkSignal) {
      sendPort.send('link_expired');
    } else {
      sendPort.send('error: $e');
    }
  }
}

/// ✅ [FIX] Marker thrown internally (inside the download isolate) when a
/// segment/chunk/manifest request comes back 401/403 — i.e. the signed CDN
/// link has expired — so it can be reported back to the main isolate as a
/// distinct 'link_expired' message instead of a generic failure. This is
/// what lets `startDownload` tell the difference between "genuinely dead,
/// tap Resume" and "just needs a fresh link, retry automatically".
class _ExpiredLinkSignal implements Exception {}

bool _isExpiredLinkError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) return true;
  }
  return false;
}

// ✅ [FIX] `package:crypto` does not publicly export an `AccumulatorSink`
// (that was my mistake in the prior version of this fix — it caused a
// `Method not found: 'AccumulatorSink'` compile error). `Hash.
// startChunkedConversion()` just needs any `Sink<Digest>` to forward the
// final digest to once `close()` is called, so this tiny local class is
// all that's actually required — no extra dependency.
class _DigestCollectorSink implements Sink<hash_crypto.Digest> {
  hash_crypto.Digest? digest;

  @override
  void add(hash_crypto.Digest data) => digest = data;

  @override
  void close() {}
}
