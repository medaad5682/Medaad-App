import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// ✅ نتيجة عملية الدمج: تحمل سبب الفشل الحقيقي
class MuxResult {
  final bool success;
  final String? failureReason;

  const MuxResult.ok()
      : success = true,
        failureReason = null;

  const MuxResult.fail(this.failureReason)
      : success = false;
}

/// خدمة دمج الفيديو والصوت وتشفير الملف النهائي
class VideoMuxService {
  // يجب أن تتطابق مع FileCryptoService
  static const int _CHUNK_SIZE = 32 * 1024;
  static const int _NONCE_LENGTH = 12;
  static const int _MAC_LENGTH = 16;

  static Future<MuxResult> muxAndEncryptWithIsolate({
    required String videoPath,
    required String audioPath,
    required String tempMuxedPath,
    required String encryptedOutputPath,
    required List<int> keyBytes,
    required Function(double) onProgress,
  }) async {
    final videoFile = File(videoPath);
    final audioFile = File(audioPath);

    if (!await videoFile.exists() ||
        await videoFile.length() == 0) {
      const reason = 'Video input missing or empty';

      FirebaseCrashlytics.instance.log(
        '❌ [MUX+ENC] $reason: $videoPath',
      );

      return const MuxResult.fail(reason);
    }

    if (!await audioFile.exists() ||
        await audioFile.length() == 0) {
      const reason = 'Audio input missing or empty';

      FirebaseCrashlytics.instance.log(
        '❌ [MUX+ENC] $reason: $audioPath',
      );

      return const MuxResult.fail(reason);
    }

    // المرحلة 1: دمج الفيديو والصوت
    final muxResult = await muxVideoAudio(
      videoPath: videoPath,
      audioPath: audioPath,
      outputPath: tempMuxedPath,
    );

    if (!muxResult.success) {
      FirebaseCrashlytics.instance.log(
        '❌ [MUX+ENC] Mux stage failed: '
        '${muxResult.failureReason}',
      );

      return muxResult;
    }

    onProgress(0.85);

    // المرحلة 2: التشفير داخل Isolate
    try {
      await _runEncryptIsolate(
        inputPath: tempMuxedPath,
        outputPath: encryptedOutputPath,
        keyBytes: keyBytes,
        onProgress: (p) =>
            onProgress(0.85 + p * 0.15),
      );
    } finally {
      // حذف الملف المؤقت
      final tmpFile = File(tempMuxedPath);

      if (await tmpFile.exists()) {
        try {
          final len = await tmpFile.length();

          if (len > 0 &&
              len < 512 * 1024 * 1024) {
            final raf =
                await tmpFile.open(mode: FileMode.write);

            const wipeChunk = 64 * 1024;
            final zeros = Uint8List(wipeChunk);

            int written = 0;

            while (written < len) {
              final toWrite =
                  (len - written)
                      .clamp(0, wipeChunk)
                      .toInt();

              await raf.writeFrom(
                zeros,
                0,
                toWrite,
              );

              written += toWrite;
            }

            await raf.close();
          }

          await tmpFile.delete();
        } catch (_) {
          try {
            await tmpFile.delete();
          } catch (_) {}
        }
      }
    }

    final outFile = File(encryptedOutputPath);

    if (!await outFile.exists() ||
        await outFile.length() == 0) {
      const reason =
          'Encrypted output missing or empty after isolate encrypt';

      FirebaseCrashlytics.instance.log(
        '❌ [MUX+ENC] $reason',
      );

      return const MuxResult.fail(reason);
    }

    onProgress(1.0);

    FirebaseCrashlytics.instance.log(
      '✅ [MUX+ENC] Done. '
      'Encrypted size: ${await outFile.length()} bytes',
    );

    return const MuxResult.ok();
  }

  // تشغيل التشفير داخل Isolate
  static Future<void> _runEncryptIsolate({
    required String inputPath,
    required String outputPath,
    required List<int> keyBytes,
    required Function(double) onProgress,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    final isolate = await Isolate.spawn(
      _encryptFileIsolateEntry,
      {
        'sendPort': receivePort.sendPort,
        'inputPath': inputPath,
        'outputPath': outputPath,
        'keyBytes': keyBytes,
      },
    );

    receivePort.listen((message) {
      if (message is double) {
        onProgress(
          message.clamp(0.0, 1.0),
        );
      } else if (message == 'done') {
        receivePort.close();
        isolate.kill();

        if (!completer.isCompleted) {
          completer.complete();
        }
      } else if (message is String &&
          message.startsWith('error:')) {
        receivePort.close();
        isolate.kill();

        if (!completer.isCompleted) {
          completer.completeError(
            Exception(
              message.substring(6),
            ),
          );
        }
      }
    });

    await completer.future;
  }

  // دالة التشفير داخل الـ Isolate
  static void _encryptFileIsolateEntry(
    Map<String, dynamic> args,
  ) async {
    final SendPort sendPort = args['sendPort'];
    final String inputPath = args['inputPath'];
    final String outputPath = args['outputPath'];
    final List<int> keyBytes = args['keyBytes'];

    try {
      final inFile = File(inputPath);
      final outFile = File(outputPath);

      if (!inFile.existsSync()) {
        sendPort.send(
          'error:Input file not found: $inputPath',
        );
        return;
      }

      final algorithm =
          Chacha20.poly1305Aead();

      final secretKey =
          SecretKey(keyBytes);

      final fileLength =
          await inFile.length();

      if (fileLength == 0) {
        sendPort.send(
          'error:Input file is empty: $inputPath',
        );
        return;
      }

      final rafRead = await inFile.open(
        mode: FileMode.read,
      );

      final iosSink =
          outFile.openWrite();

      try {
        int currentPos = 0;

        while (currentPos < fileLength) {
          final chunk =
              await rafRead.read(
            _CHUNK_SIZE,
          );

          if (chunk.isEmpty) {
            break;
          }

          final nonce =
              List<int>.generate(
            _NONCE_LENGTH,
            (_) =>
                Random.secure()
                    .nextInt(256),
          );

          final secretBox =
              await algorithm.encrypt(
            chunk,
            secretKey: secretKey,
            nonce: nonce,
          );

          iosSink.add(nonce);
          iosSink.add(
            secretBox.cipherText,
          );
          iosSink.add(
            secretBox.mac.bytes,
          );

          currentPos += chunk.length;

          sendPort.send(
            currentPos / fileLength,
          );
        }
      } finally {
        await rafRead.close();
        await iosSink.close();
      }

      sendPort.send('done');
    } catch (e) {
      sendPort.send('error:$e');
    }
  }

  // دمج الفيديو والصوت
  static Future<MuxResult> muxVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    final videoFile = File(videoPath);
    final audioFile = File(audioPath);

    if (!await videoFile.exists() ||
        await videoFile.length() == 0) {
      const reason =
          'Video input missing or empty';

      FirebaseCrashlytics.instance.log(
        '❌ [MUX] $reason: $videoPath',
      );

      return const MuxResult.fail(
        reason,
      );
    }

    if (!await audioFile.exists() ||
        await audioFile.length() == 0) {
      const reason =
          'Audio input missing or empty';

      FirebaseCrashlytics.instance.log(
        '❌ [MUX] $reason: $audioPath',
      );

      return const MuxResult.fail(
        reason,
      );
    }

    final outFile =
        File(outputPath);

    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }

    final command =
        '-y '
        '-i "$videoPath" '
        '-i "$audioPath" '
        '-map 0:v:0 -map 1:a:0 '
        '-c:v copy -c:a copy '
        '-f mp4 '
        '-movflags +faststart '
        '"$outputPath"';

    try {
      final session =
          await FFmpegKit.execute(
        command,
      );

      final returnCode =
          await session.getReturnCode();

      if (ReturnCode.isSuccess(
        returnCode,
      )) {
        final outExists =
            await outFile.exists();

        final outSize =
            outExists
                ? await outFile.length()
                : 0;

        if (!outExists ||
            outSize == 0) {
          const reason =
              'FFmpeg reported success but output is missing/empty';

          FirebaseCrashlytics.instance.log(
            '❌ [MUX] $reason',
          );

          return const MuxResult.fail(
            reason,
          );
        }

        return const MuxResult.ok();
      }

      final logs =
          await session.getOutput();

      final allLogs =
          await session.getAllLogs();

      final logMessages =
          allLogs
              .map(
                (l) =>
                    l.getMessage(),
              )
              .join(' | ');

      FirebaseCrashlytics.instance.log(
        '⚠️ [MUX] Stream-copy failed '
        '(code: $returnCode). '
        'Output: ${logs ?? ""}. '
        'Logs: $logMessages',
      );

      final fallback =
          await _muxWithAudioReencodeFallback(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
      );

      if (fallback.success) {
        return fallback;
      }

      final truncatedLog =
          logMessages.length > 300
              ? '${logMessages.substring(0, 300)}...'
              : logMessages;

      return MuxResult.fail(
        'Stream-copy failed '
        '(code: $returnCode): '
        '$truncatedLog. '
        'Fallback also failed: '
        '${fallback.failureReason}',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(
        e,
        stack,
        reason:
            'VideoMuxService.muxVideoAudio failed',
      );

      return MuxResult.fail(
        'Exception: $e',
      );
    }
  }

  // إعادة ترميز الصوت فقط
  static Future<MuxResult>
      _muxWithAudioReencodeFallback({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    final outFile =
        File(outputPath);

    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }

    final command =
        '-y '
        '-i "$videoPath" '
        '-i "$audioPath" '
        '-map 0:v:0 -map 1:a:0 '
        '-c:v copy '
        '-c:a aac '
        '-b:a 160k '
        '-f mp4 '
        '-movflags +faststart '
        '"$outputPath"';

    try {
      final session =
          await FFmpegKit.execute(
        command,
      );

      final returnCode =
          await session.getReturnCode();

      if (ReturnCode.isSuccess(
        returnCode,
      )) {
        final outExists =
            await outFile.exists();

        final outSize =
            outExists
                ? await outFile.length()
                : 0;

        if (outExists &&
            outSize > 0) {
          return const MuxResult.ok();
        }

        const reason =
            'Fallback reported success but output is missing/empty';

        FirebaseCrashlytics.instance.log(
          '❌ [MUX] $reason',
        );

        return const MuxResult.fail(
          reason,
        );
      }

      final logs =
          await session.getOutput();

      final allLogs =
          await session.getAllLogs();

      final logMessages =
          allLogs
              .map(
                (l) =>
                    l.getMessage(),
              )
              .join(' | ');

      FirebaseCrashlytics.instance.log(
        '❌ [MUX] Audio re-encode '
        'fallback also failed '
        '(code: $returnCode). '
        'Output: ${logs ?? ""}. '
        'Logs: $logMessages',
      );

      final truncatedLog =
          logMessages.length > 300
              ? '${logMessages.substring(0, 300)}...'
              : logMessages;

      return MuxResult.fail(
        'Audio re-encode failed '
        '(code: $returnCode): '
        '$truncatedLog',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(
        e,
        stack,
        reason:
            'VideoMuxService._muxWithAudioReencodeFallback failed',
      );

      return MuxResult.fail(
        'Exception: $e',
      );
    }
  }
}
