import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

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
  /// ترجع true عند النجاح، false عند الفشل (مع تسجيل السبب في Crashlytics)
  static Future<bool> muxVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    final videoFile = File(videoPath);
    final audioFile = File(audioPath);

    if (!await videoFile.exists() || await videoFile.length() == 0) {
      FirebaseCrashlytics.instance
          .log('❌ [MUX] Video input missing or empty: $videoPath');
      return false;
    }
    if (!await audioFile.exists() || await audioFile.length() == 0) {
      FirebaseCrashlytics.instance
          .log('❌ [MUX] Audio input missing or empty: $audioPath');
      return false;
    }

    // حذف أي ملف إخراج قديم بنفس الاسم لتفادي تعارض FFmpeg مع ملف موجود
    final outFile = File(outputPath);
    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }

    // ✅ -map 0:v:0 و -map 1:a:0: نأخذ مسار الفيديو من الملف الأول والصوت من
    // الثاني بشكل صريح، لتجنب أي التباس إذا كان أحد الملفين يحتوي مسارات متعددة.
    // ✅ -c:v copy -c:a copy: نسخ مباشر بدون إعادة ترميز (الأهم لأجهزة ضعيفة).
    // ✅ -movflags +faststart: نقل جدول الفهرسة (moov atom) لبداية الملف بدلاً
    // من نهايته، لضمان إمكانية بدء التشغيل/البحث (seek) فوراً دون الحاجة لقراءة
    // الملف كاملاً أولاً - مهم جداً لأن ملف الإخراج سيُقرأ لاحقاً عبر بروكسي
    // محلي يدعم Range requests.
    // ✅ -y: استبدال ملف الإخراج تلقائياً دون سؤال تفاعلي (لا يوجد تفاعل في FFmpegKit أصلاً).
    final command = '-y '
        '-i "$videoPath" '
        '-i "$audioPath" '
        '-map 0:v:0 -map 1:a:0 '
        '-c:v copy -c:a copy '
        '-movflags +faststart '
        '"$outputPath"';

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outExists = await outFile.exists();
        final outSize = outExists ? await outFile.length() : 0;
        if (!outExists || outSize == 0) {
          FirebaseCrashlytics.instance.log(
              '❌ [MUX] FFmpeg reported success but output is missing/empty');
          return false;
        }
        return true;
      }

      // ⚠️ فشل الدمج بـ stream-copy: غالباً بسبب عدم توافق بين الفيديو
      // والصوت (مثل اختلاف نوع الحاوية بشكل لا يدعم النسخ المباشر).
      // نحاول مرة واحدة بإعادة ترميز الصوت فقط (الأخف من إعادة ترميز الفيديو)
      // كخطة بديلة، لأن إعادة ترميز الفيديو على جهاز ضعيف قد تستغرق وقتاً طويلاً.
      final logs = await session.getOutput();
      FirebaseCrashlytics.instance.log(
          '⚠️ [MUX] Stream-copy failed, retrying with audio re-encode. Logs: ${logs ?? ""}');

      return await _muxWithAudioReencodeFallback(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'VideoMuxService.muxVideoAudio failed');
      return false;
    }
  }

  /// خطة بديلة: إعادة ترميز الصوت فقط إلى AAC (خفيف جداً، ثوانٍ معدودة حتى
  /// على جهاز ضعيف) مع الإبقاء على الفيديو كنسخ مباشر بدون أي إعادة ترميز.
  /// هذا يغطي حالات كانت فيها حاوية/ترميز الصوت الأصلي غير متوافق مباشرة مع MP4.
  static Future<bool> _muxWithAudioReencodeFallback({
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
        '-movflags +faststart '
        '"$outputPath"';

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outExists = await outFile.exists();
        final outSize = outExists ? await outFile.length() : 0;
        return outExists && outSize > 0;
      }

      final logs = await session.getOutput();
      FirebaseCrashlytics.instance.log(
          '❌ [MUX] Audio re-encode fallback also failed. Logs: ${logs ?? ""}');
      return false;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'VideoMuxService._muxWithAudioReencodeFallback failed');
      return false;
    }
  }
}
