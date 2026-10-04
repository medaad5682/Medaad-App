import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'file_crypto_service.dart';

/// Random-access reader over a file written by [FileCryptoService] /
/// `_pdfDownloadIsolateEntryPoint` (blocks of `[nonce 12][ciphertext ≤32KB][mac 16]`).
///
/// SECURITY MODEL — unchanged from before:
///   * The file on disk is ciphertext only. Nothing here ever writes
///     plaintext to disk (no temp file, no cache file).
///   * Decrypted bytes exist only in this object's RAM cache and in the
///     buffer handed to PDFium.
///   * Every block is authenticated (Poly1305). A block that fails is never
///     returned; the read stops short instead.
///
/// WHY THIS IS FASTER than calling `FileCryptoService.readAndDecryptRange`
/// for every PDFium read:
///   1. PDFium issues MANY small reads (xref, page tree, fonts, image
///      streams, often re-reading the same bytes). The old code opened the
///      file and decrypted a whole 32KB block for EACH of those reads. Here a
///      block is decrypted once and served from an LRU cache afterwards.
///   2. The file handle is opened once, not once per read.
///   3. Two reads that need the same block at the same moment share one
///      decrypt instead of doing it twice.
///
/// Usage: create one per open document, call [close] in `dispose()`.
class SecureChunkReader {
  SecureChunkReader(
    this.file, {
    this.maxCachedChunks = 256, // 256 × 32KB = 8 MB of RAM. Raise if you have headroom.
  }) : _encryptedSize = file.lengthSync();

  final File file;
  final int maxCachedChunks;

  final int _encryptedSize;
  RandomAccessFile? _raf;
  bool _closed = false;

  // chunkIndex -> plaintext. LinkedHashMap keeps insertion order; we re-insert
  // on every hit so `keys.first` is always the least recently used.
  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  final Map<int, Future<Uint8List?>> _inFlight = <int, Future<Uint8List?>>{};

  /// Same contract as pdfrx's `read` callback: fill [buffer] from the start with
  /// up to [size] plaintext bytes beginning at [position]; return how many.
  Future<int> read(Uint8List buffer, int position, int size) async {
    if (_closed || size <= 0 || position < 0) return 0;
    final wanted = math.min(size, buffer.length);
    if (wanted <= 0) return 0;

    const chunkSize = FileCryptoService.CHUNK_SIZE;
    final end = position + wanted; // exclusive; may pass EOF, handled below
    final firstChunk = position ~/ chunkSize;
    final lastChunk = (end - 1) ~/ chunkSize;

    var written = 0;
    for (var i = firstChunk; i <= lastChunk; i++) {
      final chunk = await _chunk(i);
      // null = past EOF, truncated, or failed authentication. Stop and return
      // only what was already verified — never guess or pad.
      if (chunk == null) break;

      final chunkStart = i * chunkSize;
      final from = math.max(position, chunkStart) - chunkStart;
      final to = math.min(end, chunkStart + chunk.length) - chunkStart;
      if (to <= from) break;

      buffer.setRange(written, written + (to - from), chunk, from);
      written += to - from;

      // Short chunk = last block of the file. Nothing more to read.
      if (chunk.length < chunkSize) break;
    }
    return written;
  }

  /// Drop decrypted data and release the file handle. Safe to call twice.
  void close() {
    _closed = true;
    // Best effort: zero what we hold. (Dart can't promise there are no other
    // copies in memory the GC hasn't reclaimed yet — same limitation as any
    // in-memory decryption, including PDFium's own buffers.)
    for (final c in _cache.values) {
      c.fillRange(0, c.length, 0);
    }
    _cache.clear();
    _inFlight.clear();
    try {
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
  }

  // ───────────────────────── internals ─────────────────────────

  Future<Uint8List?> _chunk(int index) async {
    final hit = _cache.remove(index);
    if (hit != null) {
      _cache[index] = hit; // mark as most recently used
      return hit;
    }
    // Share one decrypt between concurrent callers asking for the same block.
    final pending = _inFlight[index];
    if (pending != null) return pending;

    final future = _load(index);
    _inFlight[index] = future;
    // IMPORTANT: block body, returns nothing. `() => _inFlight.remove(index)`
    // would return the removed Future; whenComplete waits for a returned Future,
    // and the one stored here is the future being waited on -> it would wait on
    // itself forever and every read would hang. (_load never throws, so the
    // future derived here can't surface an unhandled error.)
    unawaited(future.whenComplete(() {
      _inFlight.remove(index);
    }));
    return future;
  }

  Future<Uint8List?> _load(int index) async {
    try {
      final encrypted = _readEncryptedBlock(index);
      if (encrypted == null) return null;

      final plain = await FileCryptoService.decryptBlock(encrypted);
      if (plain == null || _closed) return null;

      _cache[index] = plain;
      while (_cache.length > maxCachedChunks) {
        _cache.remove(_cache.keys.first); // evict least recently used
      }
      return plain;
    } catch (e) {
      debugPrint('SecureChunkReader: chunk $index failed ($e)');
      return null;
    }
  }

  /// Synchronous on purpose: one `setPosition` + `read` pair with no `await`
  /// between them cannot be interleaved with another caller's, and
  /// `RandomAccessFile` rejects overlapping async calls anyway. A 32KB read
  /// served from the OS page cache is far cheaper than the decrypt.
  Uint8List? _readEncryptedBlock(int index) {
    if (_closed) return null;
    final start = index * FileCryptoService.ENCRYPTED_CHUNK_SIZE;
    if (start >= _encryptedSize) return null;

    final raf = _raf ??= file.openSync(mode: FileMode.read);
    raf.setPositionSync(start);
    final block = raf.readSync(FileCryptoService.ENCRYPTED_CHUNK_SIZE);
    return block.isEmpty ? null : block;
  }
}
