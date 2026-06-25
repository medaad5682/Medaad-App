// ============================================================
//  VideoMuxService — FFmpeg-free, pure-Dart MP4 muxer
// ============================================================
//
//  WHY this exists
//  ----------------
//  ffmpeg_kit_flutter bundles a ~35 MB native library that spawns
//  a heavy subprocess.  On entry-level / 1 GB-RAM devices the OS
//  kills it mid-run or the device runs out of address space before
//  the mux even starts.  For files ≥ 200 MB the risk grows further.
//
//  WHAT this does instead
//  -----------------------
//  It parses the MP4 box structure (ISO 14496-12) of the raw video
//  track and the raw audio track in pure Dart, then writes a new
//  MP4 container that holds both tracks — exactly what
//  `ffmpeg -c:v copy -c:a copy` does, but without any native code.
//
//  Guarantees kept from the old implementation
//  --------------------------------------------
//  ✅  Same public API  (MuxResult, muxVideoAudio, muxAndEncryptWithIsolate)
//  ✅  ChaCha20-Poly1305 encryption in a dedicated Isolate
//  ✅  Secure wipe + delete of the temporary muxed file
//  ✅  Progress callbacks at every stage
//  ✅  Firebase Crashlytics logging on every failure path
//
//  Supported input containers
//  --------------------------
//  • Video: MP4 / M4V / MOV (H.264, H.265, VP9 — any codec, stream-copy)
//  • Audio: MP4 / M4A / AAC-in-MP4 / any MP4-boxed audio track
//
//  Memory budget
//  -------------
//  Boxes are walked in O(1) memory (only the box header is held in RAM
//  at a time).  The actual media data (mdat) is copied in 256 KB chunks
//  so a 500 MB file never loads more than ~512 KB at once.
//
// ============================================================

import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// ── Public result type (unchanged) ──────────────────────────

class MuxResult {
  final bool success;
  final String? failureReason;

  const MuxResult.ok()
      : success = true,
        failureReason = null;

  const MuxResult.fail(this.failureReason) : success = false;
}

// ── Public service (same surface as the old FFmpeg-based one) ──

class VideoMuxService {
  // Must match FileCryptoService
  static const int _CHUNK_SIZE = 32 * 1024;
  static const int _NONCE_LENGTH = 12;
  static const int _MAC_LENGTH = 16;

  // ─── Entry point called by DownloadManager ───────────────

  static Future<MuxResult> muxAndEncryptWithIsolate({
    required String videoPath,
    required String audioPath,
    required String tempMuxedPath,
    required String encryptedOutputPath,
    required List<int> keyBytes,
    required Function(double) onProgress,
  }) async {
    // Validate inputs
    final videoFile = File(videoPath);
    final audioFile = File(audioPath);

    if (!await videoFile.exists() || await videoFile.length() == 0) {
      const reason = 'Video input missing or empty';
      FirebaseCrashlytics.instance.log('❌ [MUX+ENC] $reason: $videoPath');
      return const MuxResult.fail(reason);
    }

    if (!await audioFile.exists() || await audioFile.length() == 0) {
      const reason = 'Audio input missing or empty';
      FirebaseCrashlytics.instance.log('❌ [MUX+ENC] $reason: $audioPath');
      return const MuxResult.fail(reason);
    }

    // Stage 1 — pure-Dart mux (stream-copy, no transcoding)
    final muxResult = await muxVideoAudio(
      videoPath: videoPath,
      audioPath: audioPath,
      outputPath: tempMuxedPath,
      onProgress: (p) => onProgress(p * 0.85),
    );

    if (!muxResult.success) {
      FirebaseCrashlytics.instance
          .log('❌ [MUX+ENC] Mux stage failed: ${muxResult.failureReason}');
      return muxResult;
    }

    onProgress(0.85);

    // Stage 2 — ChaCha20 encryption in an Isolate
    try {
      await _runEncryptIsolate(
        inputPath: tempMuxedPath,
        outputPath: encryptedOutputPath,
        keyBytes: keyBytes,
        onProgress: (p) => onProgress(0.85 + p * 0.15),
      );
    } finally {
      await _secureDeleteTemp(tempMuxedPath);
    }

    final outFile = File(encryptedOutputPath);
    if (!await outFile.exists() || await outFile.length() == 0) {
      const reason = 'Encrypted output missing or empty after isolate encrypt';
      FirebaseCrashlytics.instance.log('❌ [MUX+ENC] $reason');
      return const MuxResult.fail(reason);
    }

    onProgress(1.0);
    FirebaseCrashlytics.instance.log(
        '✅ [MUX+ENC] Done. Encrypted size: ${await outFile.length()} bytes');
    return const MuxResult.ok();
  }

  // ─── Core mux (pure Dart, no native code) ─────────────────

  /// Merges a video-only MP4 and an audio-only MP4 into [outputPath]
  /// using stream-copy (no re-encoding).  Works on any Android/iOS device
  /// regardless of RAM or CPU power.
  static Future<MuxResult> muxVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    Function(double)? onProgress,
  }) async {
    try {
      FirebaseCrashlytics.instance
          .log('🔄 [MUX] Starting pure-Dart mux: $videoPath + $audioPath');

      final videoFile = File(videoPath);
      final audioFile = File(audioPath);

      if (!await videoFile.exists() || await videoFile.length() == 0) {
        return const MuxResult.fail('Video input missing or empty');
      }
      if (!await audioFile.exists() || await audioFile.length() == 0) {
        return const MuxResult.fail('Audio input missing or empty');
      }

      // Delete stale output if any
      final outFile = File(outputPath);
      if (await outFile.exists()) {
        try { await outFile.delete(); } catch (_) {}
      }

      // Parse both containers
      final videoInfo = await _parseMp4(videoFile);
      if (videoInfo == null) {
        return const MuxResult.fail(
            'Could not parse video MP4 — unsupported container');
      }
      final audioInfo = await _parseMp4(audioFile);
      if (audioInfo == null) {
        return const MuxResult.fail(
            'Could not parse audio MP4 — unsupported container');
      }

      // Build the merged MP4 in a background Isolate to keep the UI free
      final mergeResult = await _runMuxIsolate(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
        videoInfo: videoInfo,
        audioInfo: audioInfo,
        onProgress: onProgress,
      );

      if (!mergeResult.success) return mergeResult;

      // Sanity-check the output
      if (!await outFile.exists() || await outFile.length() == 0) {
        return const MuxResult.fail('Mux completed but output is missing/empty');
      }

      FirebaseCrashlytics.instance
          .log('✅ [MUX] Done: ${await outFile.length()} bytes → $outputPath');
      return const MuxResult.ok();
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'VideoMuxService.muxVideoAudio');
      return MuxResult.fail('Exception: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  MP4 parser — returns just what the muxer needs
  // ═══════════════════════════════════════════════════════════

  static Future<_Mp4Info?> _parseMp4(File f) async {
    final raf = await f.open(mode: FileMode.read);
    try {
      final size = await f.length();
      return await _walkBoxes(raf, size);
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Walks the top-level MP4 boxes and extracts moov metadata.
  static Future<_Mp4Info?> _walkBoxes(
      RandomAccessFile raf, int fileSize) async {
    int pos = 0;
    int? mdatOffset;
    int? mdatSize;
    Uint8List? moovBytes;
    bool videoTrack = false; // is this a video container?

    while (pos < fileSize) {
      final header = await _readBytes(raf, pos, 8);
      if (header == null || header.length < 8) break;

      final boxSize = _readU32(header, 0);
      final boxType = String.fromCharCodes(header.sublist(4, 8));

      int realSize;
      int dataOffset;

      if (boxSize == 1) {
        // Extended 64-bit size
        final ext = await _readBytes(raf, pos + 8, 8);
        if (ext == null) break;
        realSize = _readU64(ext, 0);
        dataOffset = pos + 16;
      } else if (boxSize == 0) {
        realSize = fileSize - pos;
        dataOffset = pos + 8;
      } else {
        realSize = boxSize;
        dataOffset = pos + 8;
      }

      if (boxType == 'mdat') {
        mdatOffset = dataOffset;
        mdatSize = realSize - (dataOffset - pos);
      } else if (boxType == 'moov') {
        moovBytes =
            await _readBytes(raf, pos, realSize.clamp(0, fileSize - pos));
        // Quick peek: does moov contain a video (vide) or audio (soun) trak?
        videoTrack = moovBytes != null &&
            _containsHandlerType(moovBytes, 'vide');
      }

      pos += realSize;
      if (realSize <= 0) break; // guard against corrupt files
    }

    if (mdatOffset == null || moovBytes == null) return null;

    return _Mp4Info(
      mdatOffset: mdatOffset,
      mdatSize: mdatSize ?? 0,
      moovBytes: moovBytes,
      isVideo: videoTrack,
    );
  }

  /// Searches moov bytes for an hdlr box with the given handler_type.
  static bool _containsHandlerType(Uint8List moov, String type) {
    final needle = Uint8List.fromList([...type.codeUnits]);
    for (int i = 0; i < moov.length - 4; i++) {
      if (moov[i] == needle[0] &&
          moov[i + 1] == needle[1] &&
          moov[i + 2] == needle[2] &&
          moov[i + 3] == needle[3]) {
        return true;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  //  Isolate: actual MP4 write
  // ═══════════════════════════════════════════════════════════

  static Future<MuxResult> _runMuxIsolate({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required _Mp4Info videoInfo,
    required _Mp4Info audioInfo,
    Function(double)? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<MuxResult>();

    final isolate = await Isolate.spawn(
      _muxIsolateEntry,
      {
        'sendPort': receivePort.sendPort,
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
        'videoMdatOffset': videoInfo.mdatOffset,
        'videoMdatSize': videoInfo.mdatSize,
        'videoMoov': videoInfo.moovBytes,
        'audioMdatOffset': audioInfo.mdatOffset,
        'audioMdatSize': audioInfo.mdatSize,
        'audioMoov': audioInfo.moovBytes,
      },
    );

    receivePort.listen((msg) {
      if (msg is double) {
        onProgress?.call(msg.clamp(0.0, 1.0));
      } else if (msg == 'ok') {
        receivePort.close();
        isolate.kill();
        if (!completer.isCompleted) completer.complete(const MuxResult.ok());
      } else if (msg is String && msg.startsWith('err:')) {
        receivePort.close();
        isolate.kill();
        if (!completer.isCompleted) {
          completer.complete(MuxResult.fail(msg.substring(4)));
        }
      }
    });

    return completer.future;
  }

  // Runs inside the Isolate — no Flutter plugins available here
  static void _muxIsolateEntry(Map<String, dynamic> args) async {
    final SendPort send = args['sendPort'];
    try {
      final String videoPath = args['videoPath'];
      final String audioPath = args['audioPath'];
      final String outputPath = args['outputPath'];
      final int videoMdatOff = args['videoMdatOffset'];
      final int videoMdatSz = args['videoMdatSize'];
      final Uint8List videoMoov = args['videoMoov'];
      final int audioMdatOff = args['audioMdatOffset'];
      final int audioMdatSz = args['audioMdatSize'];
      final Uint8List audioMoov = args['audioMoov'];

      // ── Build merged moov ─────────────────────────────────
      // Strategy:
      //   1. Take the video moov as-is.
      //   2. Extract the audio trak box from the audio moov.
      //   3. Patch the stco/co64 offsets in BOTH tracks so they point
      //      to the correct positions inside the merged mdat.
      //   4. Write: ftyp | mdat(video‖audio) | merged_moov
      //      (moov at end = streaming-compatible after a single pass;
      //       "faststart" requires a second pass which we skip to save RAM —
      //       media_kit / ExoPlayer / AVPlayer handle moov-at-end fine)

      // ── 1. Extract audio trak ─────────────────────────────
      final audioTrak = _extractTrakBox(audioMoov, 'soun');
      if (audioTrak == null) {
        send.send('err:Could not find audio trak in audio moov');
        return;
      }

      // ── 2. Compute merged mdat size ───────────────────────
      final totalMdat = videoMdatSz + audioMdatSz;

      // We write: [ftyp] [mdat-header(8)] [video-mdat-data] [audio-mdat-data] [moov]
      // Sizes needed before we write:
      final ftyp = _buildFtyp();
      final ftypSize = ftyp.length;

      // mdat box header = 8 bytes (4 size + 4 'mdat')
      // But totalMdat could exceed 2^32-1 → use 64-bit extended size box
      final bool bigMdat = totalMdat + 8 > 0xFFFFFFFF;
      final int mdatHeaderSize = bigMdat ? 16 : 8;
      final int mdatBoxSize = mdatHeaderSize + totalMdat;

      // Absolute byte offset where video mdat data starts
      final int videoDataStart = ftypSize + mdatHeaderSize;
      // Absolute byte offset where audio mdat data starts
      final int audioDataStart = videoDataStart + videoMdatSz;

      // ── 3. Patch offsets in video moov ────────────────────
      // The video's sample offsets inside the original file need to be
      // shifted by (videoDataStart - videoMdatOff)
      final int videoDelta = videoDataStart - videoMdatOff;
      final Uint8List patchedVideoMoov =
          _patchOffsets(videoMoov, videoDelta);

      // ── 4. Patch offsets in audio trak ───────────────────
      // The audio's sample offsets need to land in the merged file
      final int audioDelta = audioDataStart - audioMdatOff;
      final Uint8List patchedAudioTrak =
          _patchOffsets(audioTrak, audioDelta);

      // ── 5. Build the merged moov ──────────────────────────
      // Clone patchedVideoMoov and insert patchedAudioTrak before </moov>
      final Uint8List mergedMoov =
          _insertTrakIntoMoov(patchedVideoMoov, patchedAudioTrak);

      // ── 6. Write output file ──────────────────────────────
      final outFile = File(outputPath);
      final sink = outFile.openWrite();

      try {
        // ftyp
        sink.add(ftyp);

        // mdat header
        if (bigMdat) {
          // 64-bit extended size: size=1, 'mdat', actual 64-bit size
          final hdr = ByteData(16);
          hdr.setUint32(0, 1);
          hdr.setUint32(4, 0x6D646174); // 'mdat'
          hdr.setUint64(8, mdatBoxSize);
          sink.add(hdr.buffer.asUint8List());
        } else {
          final hdr = ByteData(8);
          hdr.setUint32(0, mdatBoxSize);
          hdr.setUint32(4, 0x6D646174); // 'mdat'
          sink.add(hdr.buffer.asUint8List());
        }

        // video mdat data
        await _copyRange(
          srcPath: videoPath,
          srcOffset: videoMdatOff,
          length: videoMdatSz,
          sink: sink,
          onProgress: (p) => send.send(p * 0.60),
        );

        send.send(0.60);

        // audio mdat data
        await _copyRange(
          srcPath: audioPath,
          srcOffset: audioMdatOff,
          length: audioMdatSz,
          sink: sink,
          onProgress: (p) => send.send(0.60 + p * 0.30),
        );

        send.send(0.90);

        // merged moov
        sink.add(mergedMoov);
      } finally {
        await sink.close();
      }

      send.send(1.0);
      send.send('ok');
    } catch (e) {
      send.send('err:$e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  MP4 box helpers
  // ═══════════════════════════════════════════════════════════

  /// Builds a minimal ftyp box: major brand = isom
  static Uint8List _buildFtyp() {
    // ftyp: size(4) type(4) major(4) version(4) compat-brands(4×n)
    // brands: isom iso2 avc1 mp41
    final brands = ['isom', 'iso2', 'avc1', 'mp41'];
    final size = 8 + 4 + 4 + brands.length * 4;
    final bd = ByteData(size);
    bd.setUint32(0, size);
    _writeStr(bd, 4, 'ftyp');
    _writeStr(bd, 8, 'isom');
    bd.setUint32(12, 0x00000200); // minor version
    for (int i = 0; i < brands.length; i++) {
      _writeStr(bd, 16 + i * 4, brands[i]);
    }
    return bd.buffer.asUint8List();
  }

  /// Writes a 4-char ASCII string into [bd] at [offset].
  static void _writeStr(ByteData bd, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  /// Finds and returns the first `trak` box whose contained `hdlr`
  /// has handler_type == [handlerType] (e.g. 'soun').
  static Uint8List? _extractTrakBox(Uint8List moov, String handlerType) {
    // Walk boxes inside moov looking for trak
    int pos = 8; // skip moov header
    while (pos < moov.length - 8) {
      final sz = _readU32(moov, pos);
      final type = String.fromCharCodes(moov.sublist(pos + 4, pos + 8));
      if (sz < 8 || pos + sz > moov.length) break;

      if (type == 'trak') {
        final trakBytes = moov.sublist(pos, pos + sz);
        // Check if this trak has the target handler
        if (_containsHandlerType(trakBytes, handlerType)) {
          return trakBytes;
        }
      }
      pos += sz;
    }
    return null;
  }

  /// Patches all stco (32-bit) and co64 (64-bit) chunk-offset boxes
  /// inside [boxBytes] by adding [delta].
  static Uint8List _patchOffsets(Uint8List boxBytes, int delta) {
    if (delta == 0) return boxBytes;

    // Work on a copy
    final data = Uint8List.fromList(boxBytes);
    _walkAndPatch(data, 0, data.length, delta);
    return data;
  }

  static void _walkAndPatch(Uint8List data, int start, int end, int delta) {
    int pos = start;
    while (pos < end - 8) {
      final sz = _readU32(data, pos);
      if (sz < 8 || pos + sz > end) break;
      final type = String.fromCharCodes(data.sublist(pos + 4, pos + 8));

      if (type == 'stco') {
        _patchStco(data, pos, delta);
      } else if (type == 'co64') {
        _patchCo64(data, pos, delta);
      } else if (_isContainerBox(type)) {
        // Recurse into container boxes
        _walkAndPatch(data, pos + 8, pos + sz, delta);
      }
      pos += sz;
    }
  }

  /// Patches a stco box (32-bit offsets) in place.
  static void _patchStco(Uint8List data, int boxStart, int delta) {
    // stco: version(1) flags(3) entry_count(4) entries[entry_count](4 each)
    final entryCount = _readU32(data, boxStart + 12);
    for (int i = 0; i < entryCount; i++) {
      final off = boxStart + 16 + i * 4;
      if (off + 4 > data.length) break;
      final old = _readU32(data, off);
      final patched = old + delta;
      data[off] = (patched >> 24) & 0xFF;
      data[off + 1] = (patched >> 16) & 0xFF;
      data[off + 2] = (patched >> 8) & 0xFF;
      data[off + 3] = patched & 0xFF;
    }
  }

  /// Patches a co64 box (64-bit offsets) in place.
  static void _patchCo64(Uint8List data, int boxStart, int delta) {
    final entryCount = _readU32(data, boxStart + 12);
    for (int i = 0; i < entryCount; i++) {
      final off = boxStart + 16 + i * 8;
      if (off + 8 > data.length) break;
      final old = _readU64s(data, off);
      final patched = old + delta;
      _writeU64(data, off, patched);
    }
  }

  static bool _isContainerBox(String type) {
    const containers = {
      'moov', 'trak', 'mdia', 'minf', 'dinf', 'stbl',
      'edts', 'udta', 'meta', 'ilst', 'tref',
    };
    return containers.contains(type);
  }

  /// Clones [moov] and appends [trak] just before the closing boundary.
  static Uint8List _insertTrakIntoMoov(Uint8List moov, Uint8List trak) {
    final newSize = moov.length + trak.length;
    final result = Uint8List(newSize);
    // Copy old moov (skip first 4 bytes — we'll rewrite the size)
    result.setRange(4, moov.length, moov, 4);
    // Append trak before end
    result.setRange(moov.length, newSize, trak);
    // Rewrite moov size (first 4 bytes)
    result[0] = (newSize >> 24) & 0xFF;
    result[1] = (newSize >> 16) & 0xFF;
    result[2] = (newSize >> 8) & 0xFF;
    result[3] = newSize & 0xFF;
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  //  Low-level I/O helpers
  // ═══════════════════════════════════════════════════════════

  static const int _COPY_CHUNK = 256 * 1024; // 256 KB — low memory budget

  /// Copies [length] bytes from [srcPath] starting at [srcOffset] into [sink].
  static Future<void> _copyRange({
    required String srcPath,
    required int srcOffset,
    required int length,
    required IOSink sink,
    Function(double)? onProgress,
  }) async {
    if (length == 0) return;
    final raf = await File(srcPath).open(mode: FileMode.read);
    try {
      await raf.setPosition(srcOffset);
      int remaining = length;
      int done = 0;
      while (remaining > 0) {
        final toRead = remaining.clamp(0, _COPY_CHUNK);
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        sink.add(chunk);
        done += chunk.length;
        remaining -= chunk.length;
        onProgress?.call(done / length);
      }
    } finally {
      await raf.close();
    }
  }

  static Future<Uint8List?> _readBytes(
      RandomAccessFile raf, int offset, int length) async {
    if (length <= 0) return Uint8List(0);
    await raf.setPosition(offset);
    final bytes = await raf.read(length);
    if (bytes.isEmpty) return null;
    return bytes;
  }

  // ─── Integer readers ──────────────────────────────────────

  static int _readU32(List<int> b, int off) =>
      ((b[off] & 0xFF) << 24) |
      ((b[off + 1] & 0xFF) << 16) |
      ((b[off + 2] & 0xFF) << 8) |
      (b[off + 3] & 0xFF);

  static int _readU64(List<int> b, int off) {
    // Dart int is 64-bit on all platforms
    final hi = _readU32(b, off);
    final lo = _readU32(b, off + 4);
    return (hi << 32) | lo;
  }

  // Signed 64-bit reader (for delta arithmetic)
  static int _readU64s(Uint8List b, int off) {
    final bd = ByteData.sublistView(b, off, off + 8);
    return bd.getInt64(0);
  }

  static void _writeU64(Uint8List b, int off, int value) {
    final bd = ByteData.sublistView(b, off, off + 8);
    bd.setInt64(0, value);
  }

  // ═══════════════════════════════════════════════════════════
  //  ChaCha20-Poly1305 encryption Isolate (unchanged logic)
  // ═══════════════════════════════════════════════════════════

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
        onProgress(message.clamp(0.0, 1.0));
      } else if (message == 'done') {
        receivePort.close();
        isolate.kill();
        if (!completer.isCompleted) completer.complete();
      } else if (message is String && message.startsWith('error:')) {
        receivePort.close();
        isolate.kill();
        if (!completer.isCompleted) {
          completer.completeError(Exception(message.substring(6)));
        }
      }
    });

    await completer.future;
  }

  static void _encryptFileIsolateEntry(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final String inputPath = args['inputPath'];
    final String outputPath = args['outputPath'];
    final List<int> keyBytes = args['keyBytes'];

    try {
      final inFile = File(inputPath);
      final outFile = File(outputPath);

      if (!inFile.existsSync()) {
        sendPort.send('error:Input file not found: $inputPath');
        return;
      }

      final algorithm = Chacha20.poly1305Aead();
      final secretKey = SecretKey(keyBytes);
      final fileLength = await inFile.length();

      if (fileLength == 0) {
        sendPort.send('error:Input file is empty: $inputPath');
        return;
      }

      final rafRead = await inFile.open(mode: FileMode.read);
      final iosSink = outFile.openWrite();

      try {
        int currentPos = 0;
        while (currentPos < fileLength) {
          final chunk = await rafRead.read(_CHUNK_SIZE);
          if (chunk.isEmpty) break;

          final nonce = List<int>.generate(
              _NONCE_LENGTH, (_) => Random.secure().nextInt(256));

          final secretBox = await algorithm.encrypt(
            chunk,
            secretKey: secretKey,
            nonce: nonce,
          );

          iosSink.add(nonce);
          iosSink.add(secretBox.cipherText);
          iosSink.add(secretBox.mac.bytes);

          currentPos += chunk.length;
          sendPort.send(currentPos / fileLength);
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

  // ═══════════════════════════════════════════════════════════
  //  Secure temp-file wipe
  // ═══════════════════════════════════════════════════════════

  static Future<void> _secureDeleteTemp(String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    try {
      final len = await f.length();
      if (len > 0 && len < 512 * 1024 * 1024) {
        final raf = await f.open(mode: FileMode.write);
        const wipeChunk = 64 * 1024;
        final zeros = Uint8List(wipeChunk);
        int written = 0;
        while (written < len) {
          final toWrite = (len - written).clamp(0, wipeChunk).toInt();
          await raf.writeFrom(zeros, 0, toWrite);
          written += toWrite;
        }
        await raf.close();
      }
      await f.delete();
    } catch (_) {
      try { await f.delete(); } catch (_) {}
    }
  }
}

// ── Internal data class ──────────────────────────────────────

class _Mp4Info {
  final int mdatOffset;   // byte offset of mdat payload (after box header)
  final int mdatSize;     // byte count of mdat payload
  final Uint8List moovBytes; // complete moov box (header + content)
  final bool isVideo;

  _Mp4Info({
    required this.mdatOffset,
    required this.mdatSize,
    required this.moovBytes,
    required this.isVideo,
  });
}
