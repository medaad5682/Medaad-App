import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// ✅ نتيجة عملية الدمج: تحمل سبب الفشل الحقيقي (كود الإرجاع + سجلات FFmpeg)
/// بدل إخفائه خلف قيمة true/false بسيطة - هذا ما يصل لاحقاً داخل رسالة
/// الاستثناء التي تظهر في Crashlytics لتشخيص أي فشل فعلي بسهولة.
class MuxResult {
  final bool success;
  final String? failureReason;

  const MuxResult.ok() : success = true, failureReason = null;
  const MuxResult.fail(this.failureReason) : success = false;
}

/// ✅ خدمة دمج مسارات الفيديو والصوت المنفصلة (Adaptive Streams) في ملف واحد
///
/// تستخدم "Stream Copy" (نسخ المسارات كما هي بدون إعادة ترميز):
/// `-c:v copy -c:a copy`
/// وهذا يعني: لا فك تشفير ولا إعادة ترميز فعلي للفيديو/الصوت - فقط إعادة
/// تغليف (repackaging) البيانات المرمّزة فعلاً داخل حاوية MP4 جديدة. هذا
/// يجعل العملية سريعة جداً (ثوانٍ) وخفيفة على المعالج والذاكرة، وهو الخيار
/// المناسب للأجهزة الضعيفة (2GB RAM, Android 8) حيث إعادة الترميز الكامل
/// قد تستغرق دقائق وتستهلك بطارية ومعالج بشكل كبير.
class VideoMuxService {
  /// دمج فيديو (بدون صوت) + صوت (منفصل) في ملف MP4 واحد قابل للتشغيل
  ///
  /// [videoPath]: مسار ملف الفيديو الخام (غير مشفر، مؤقت)
  /// [audioPath]: مسار ملف الصوت الخام (غير مشفر، مؤقت)
  /// [outputPath]: مسار ملف الإخراج المدموج (غير مشفر، مؤقت - سيُشفّر فوراً
  ///   بعد هذه الدالة ثم يُحذف بأمان)
  ///
  /// ترجع MuxResult.ok() عند النجاح، أو MuxResult.fail(reason) مع سبب الفشل
  /// الحقيقي (مأخوذ من FFmpeg نفسه) عند الفشل
  static Future<MuxResult> muxVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    final videoFile = File(videoPath);
    final audioFile = File(audioPath);

    if (!await videoFile.exists() || await videoFile.length() == 0) {
      const reason = 'Video input missing or empty';
      FirebaseCrashlytics.instance.log('❌ [MUX] $reason: $videoPath');
      return const MuxResult.fail(reason);
    }
    if (!await audioFile.exists() || await audioFile.length() == 0) {
      const reason = 'Audio input missing or empty';
      FirebaseCrashlytics.instance.log('❌ [MUX] $reason: $audioPath');
      return const MuxResult.fail(reason);
    }

    // حذف أي ملف إخراج قديم بنفس الاسم لتفادي تعارض FFmpeg مع ملف موجود
    final outFile = File(outputPath);
    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }

    // ✅ -f mp4: تحديد صريح لصيغة الحاوية (MP4) كطبقة دفاع ثانية، بحيث
    // لا يعتمد FFmpeg على امتداد الملف فقط لمعرفة صيغة الإخراج. هذا مهم
    // على الأجهزة الضعيفة حيث قد تكون المسارات المؤقتة بامتداد مختلف.
    // الطبقة الأولى: SecureTempService.newTempPath يُنشئ المسار بامتداد .mp4
    // الطبقة الثانية: -f mp4 هنا يضمن الصيغة بغض النظر عن الامتداد
    final command = '-y '
        '-i "$videoPath" '
        '-i "$audioPath" '
        '-map 0:v:0 -map 1:a:0 '
        '-c:v copy -c:a copy '
        '-f mp4 '
        '-movflags +faststart '
        '"$outputPath"';

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outExists = await outFile.exists();
        final outSize = outExists ? await outFile.length() : 0;
        if (!outExists || outSize == 0) {
          const reason = 'FFmpeg reported success but output is missing/empty';
          FirebaseCrashlytics.instance.log('❌ [MUX] $reason');
          return const MuxResult.fail(reason);
        }
        return const MuxResult.ok();
      }

      // ⚠️ فشل الدمج بـ stream-copy: غالباً بسبب عدم توافق بين الفيديو
      // والصوت (مثل اختلاف نوع الحاوية بشكل لا يدعم النسخ المباشر).
      // نحاول مرة واحدة بإعادة ترميز الصوت فقط (الأخف من إعادة ترميز الفيديو)
      // كخطة بديلة، لأن إعادة ترميز الفيديو على جهاز ضعيف قد تستغرق وقتاً طويلاً.
      final logs = await session.getOutput();
      final allLogs = await session.getAllLogs();
      final logMessages = allLogs.map((l) => l.getMessage()).join(' | ');
      FirebaseCrashlytics.instance.log(
          '⚠️ [MUX] Stream-copy failed (code: $returnCode). Output: ${logs ?? ""}. Logs: $logMessages');

      final fallback = await _muxWithAudioReencodeFallback(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
      );

      if (fallback.success) return fallback;

      // كلا المحاولتين فشلتا - نرجع سبب فشل المحاولة الأولى (stream-copy)
      // مع إشارة لفشل البديل أيضاً، حتى تظهر السجلات الفعلية في الاستثناء
      final truncatedLog = logMessages.length > 300
          ? '${logMessages.substring(0, 300)}...'
          : logMessages;
      return MuxResult.fail(
          'Stream-copy failed (code: $returnCode): $truncatedLog. Fallback also failed: ${fallback.failureReason}');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'VideoMuxService.muxVideoAudio failed');
      return MuxResult.fail('Exception: $e');
    }
  }

  /// خطة بديلة: إعادة ترميز الصوت فقط إلى AAC (خفيف جداً، ثوانٍ معدودة حتى
  /// على جهاز ضعيف) مع الإبقاء على الفيديو كنسخ مباشر بدون أي إعادة ترميز.
  /// هذا يغطي حالات كانت فيها حاوية/ترميز الصوت الأصلي غير متوافق مباشرة مع MP4.
  static Future<MuxResult> _muxWithAudioReencodeFallback({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    final outFile = File(outputPath);
    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }

    final command = '-y '
        '-i "$videoPath" '
        '-i "$audioPath" '
        '-map 0:v:0 -map 1:a:0 '
        '-c:v copy -c:a aac -b:a 160k '
        '-f mp4 '
        '-movflags +faststart '
        '"$outputPath"';

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outExists = await outFile.exists();
        final outSize = outExists ? await outFile.length() : 0;
        if (outExists && outSize > 0) return const MuxResult.ok();
        const reason = 'Fallback reported success but output is missing/empty';
        FirebaseCrashlytics.instance.log('❌ [MUX] $reason');
        return const MuxResult.fail(reason);
      }

      final logs = await session.getOutput();
      final allLogs = await session.getAllLogs();
      final logMessages = allLogs.map((l) => l.getMessage()).join(' | ');
      FirebaseCrashlytics.instance.log(
          '❌ [MUX] Audio re-encode fallback also failed (code: $returnCode). Output: ${logs ?? ""}. Logs: $logMessages');

      final truncatedLog = logMessages.length > 300
          ? '${logMessages.substring(0, 300)}...'
          : logMessages;
      return MuxResult.fail('Audio re-encode failed (code: $returnCode): $truncatedLog');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'VideoMuxService._muxWithAudioReencodeFallback failed');
      return MuxResult.fail('Exception: $e');
    }
  }
}
