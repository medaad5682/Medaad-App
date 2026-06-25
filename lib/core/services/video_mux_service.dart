import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
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
  // ✅ [PIPE-MUX] ثوابت التشفير - يجب أن تطابق تماماً ما في FileCryptoService
  // وما في LocalProxyService حتى تعمل قراءة الملف بشكل صحيح
  static const int _CHUNK_SIZE = 32 * 1024;       // 32KB - لا تغيّر هذا
  static const int _NONCE_LENGTH = 12;
  static const int _MAC_LENGTH = 16;

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ [PIPE-MUX] الطريقة الجديدة: دمج وتشفير في نفس الوقت بدون ملف وسيط
  //
  // بدلاً من:
  //   1) FFmpeg يكتب ملف .mp4 مؤقت كامل على الديسك  (انتظار)
  //   2) ثم نشفّر الملف كله من الديسك                (انتظار آخر طويل)
  //
  // نفعل:
  //   FFmpeg يكتب على stdout → نقرأ منه مباشرة → نشفّر → نكتب .enc مباشرة
  //   الدمج والتشفير يحدثان معاً في نفس الوقت (pipeline parallel)
  //
  // المتطلبات:
  //   - FFmpeg يدعم الكتابة على pipe (stdout) مع -f mp4 -movflags frag_keyframe+...
  //   - الملف الناتج هو fragmented MP4 بدلاً من regular MP4
  //   - LocalProxyService يقرأ بـ chunk-index math فيعمل بكلا الصيغتين ✅
  //   - media_kit (libmpv) يدعم fragmented MP4 بشكل كامل ✅
  // ─────────────────────────────────────────────────────────────────────────
  static Future<MuxResult> muxAndEncryptPiped({
    required String videoPath,
    required String audioPath,
    required String encryptedOutputPath,
    required List<int> keyBytes,
    required Function(double) onProgress,
  }) async {
    final videoFile = File(videoPath);
    final audioFile = File(audioPath);

    if (!await videoFile.exists() || await videoFile.length() == 0) {
      const reason = 'Video input missing or empty';
      FirebaseCrashlytics.instance.log('❌ [PIPE-MUX] $reason: $videoPath');
      return const MuxResult.fail(reason);
    }
    if (!await audioFile.exists() || await audioFile.length() == 0) {
      const reason = 'Audio input missing or empty';
      FirebaseCrashlytics.instance.log('❌ [PIPE-MUX] $reason: $audioPath');
      return const MuxResult.fail(reason);
    }

    // حذف أي ملف إخراج قديم بنفس الاسم
    final outFile = File(encryptedOutputPath);
    if (await outFile.exists()) {
      try { await outFile.delete(); } catch (_) {}
    }

    final algorithm = Chacha20.poly1305Aead();
    final secretKey = SecretKey(keyBytes);

    final sink = outFile.openWrite();
    List<int> buffer = [];
    int totalBytesFromFFmpeg = 0;

    // ✅ [PIPE-MUX] أوامر FFmpeg للكتابة على stdout:
    // -movflags frag_keyframe+empty_moov+default_base_moof: تجعل الملف
    //   fragmented MP4 قابلاً للكتابة على pipe (بدونها تفشل الكتابة على stdout)
    // pipe:1: يكتب على stdout بدلاً من ملف
    // نستخدم Process.start وليس FFmpegKit لأننا نحتاج قراءة stdout مباشرة
    final process = await Process.start('ffmpeg', [
      '-y',
      '-i', videoPath,
      '-i', audioPath,
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-c:v', 'copy',
      '-c:a', 'copy',
      '-f', 'mp4',
      '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
      'pipe:1',
    ]);

    // ✅ استهلاك stderr حتى لا تتوقف عملية FFmpeg بسبب امتلاء buffer الـ pipe
    final stderrBuffer = StringBuffer();
    process.stderr.listen(
      (data) => stderrBuffer.write(String.fromCharCodes(data)),
      onError: (_) {},
    );

    try {
      // ✅ [PIPE-MUX] قراءة من stdout FFmpeg وتشفير فوري chunk بـ chunk
      await for (final chunk in process.stdout) {
        buffer.addAll(chunk);
        totalBytesFromFFmpeg += chunk.length;

        // كلما اكتمل chunk بحجم 32KB نشفّره فوراً ونكتبه
        while (buffer.length >= _CHUNK_SIZE) {
          final block = buffer.sublist(0, _CHUNK_SIZE);
          buffer.removeRange(0, _CHUNK_SIZE);

          final nonce = List<int>.generate(
              _NONCE_LENGTH, (_) => Random.secure().nextInt(256));
          final secretBox = await algorithm.encrypt(
              block, secretKey: secretKey, nonce: nonce);

          sink.add(nonce);
          sink.add(secretBox.cipherText);
          sink.add(secretBox.mac.bytes);
        }

        // تحديث التقدم (تقريبي - نعرف حجم الملف المتوقع من حجمَي المدخلَين)
        try {
          onProgress((totalBytesFromFFmpeg /
                  (await videoFile.length() + await audioFile.length()))
              .clamp(0.0, 0.95));
        } catch (_) {}
      }

      // ✅ تشفير ما تبقّى في الـ buffer (الـ chunk الأخير الذي أقل من 32KB)
      if (buffer.isNotEmpty) {
        final nonce = List<int>.generate(
            _NONCE_LENGTH, (_) => Random.secure().nextInt(256));
        final secretBox = await algorithm.encrypt(
            buffer, secretKey: secretKey, nonce: nonce);
        sink.add(nonce);
        sink.add(secretBox.cipherText);
        sink.add(secretBox.mac.bytes);
      }

      await sink.close();

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        final logs = stderrBuffer.toString();
        final truncated = logs.length > 400 ? '${logs.substring(0, 400)}...' : logs;
        FirebaseCrashlytics.instance
            .log('❌ [PIPE-MUX] FFmpeg exit $exitCode. Stderr: $truncated');

        // ✅ [FALLBACK] إذا فشل pipe، نرجع للطريقة القديمة (ملف وسيط)
        FirebaseCrashlytics.instance
            .log('⚠️ [PIPE-MUX] Falling back to classic mux+encrypt');
        if (await outFile.exists()) await outFile.delete();
        return const MuxResult.fail('pipe_failed'); // إشارة خاصة للـ fallback
      }

      final outSize = await outFile.length();
      if (outSize == 0) {
        FirebaseCrashlytics.instance.log('❌ [PIPE-MUX] Output file is empty');
        return const MuxResult.fail('pipe_output_empty');
      }

      onProgress(1.0);
      FirebaseCrashlytics.instance
          .log('✅ [PIPE-MUX] Success. Encrypted size: $outSize bytes');
      return const MuxResult.ok();
    } catch (e, stack) {
      await sink.close();
      if (await outFile.exists()) {
        try { await outFile.delete(); } catch (_) {}
      }
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'VideoMuxService.muxAndEncryptPiped failed');
      return MuxResult.fail('Exception in pipe: $e');
    } finally {
      process.kill();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // الطريقة القديمة: تبقى كـ fallback عند فشل pipe
  // تُستخدم من download_manager عند إرجاع 'pipe_failed'
  // ─────────────────────────────────────────────────────────────────────────

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
