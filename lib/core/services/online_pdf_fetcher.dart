import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// The PDF is bigger than [OnlinePdfFetcher.maxBytes], so it is not safe to
/// hold in RAM. The user should download it and open it offline instead.
class OnlinePdfTooLargeException implements Exception {
  const OnlinePdfTooLargeException({required this.limitBytes, this.sizeBytes});

  final int limitBytes;

  /// Size reported by the server (or received so far); null if unknown.
  final int? sizeBytes;

  @override
  String toString() =>
      'OnlinePdfTooLargeException: size=${sizeBytes ?? 'unknown'} limit=$limitBytes';
}

/// The server answered 200 but the body is not a PDF (empty, an error page,
/// JSON, ...). Caught here so PDFium is never handed garbage.
class OnlinePdfInvalidException implements Exception {
  const OnlinePdfInvalidException(this.reason);

  final String reason;

  @override
  String toString() => 'OnlinePdfInvalidException: $reason';
}

/// Downloads a PDF straight into memory.
///
/// WHY THIS EXISTS
/// `PdfViewer.uri(...)` makes pdfrx download the file itself and write it, as a
/// plaintext PDF, into `<tempDir>/pdfrx.cache/...` where it stays after the
/// viewer closes. Fetching the bytes here and opening them with
/// `PdfViewer.custom` (an in-memory read callback, the same mechanism offline
/// mode uses) means the PDF never touches the disk.
///
/// It also moves the download onto the app's pinned Dio client
/// (`ApiClient.instance`: trusts only the pinned roots, and its interceptor
/// adds the auth / App Check headers), instead of pdfrx's default HTTP client
/// which uses the system trust store.
///
/// TRADE-OFFS
///  * The whole file is downloaded before the first page is shown (no
///    range-based progressive loading).
///  * The whole file is held in RAM while the viewer is open; hence [maxBytes].
class OnlinePdfFetcher {
  OnlinePdfFetcher._();

  /// Largest PDF we will hold in memory. Larger files fail with
  /// [OnlinePdfTooLargeException] (the user can download them for offline use,
  /// which streams to disk in encrypted form instead of using RAM).
  static const int maxBytes = 100 * 1024 * 1024;

  /// Max wait for the server to START answering (connect + TLS + App Check
  /// token + response headers).
  static const Duration _headersTimeout = Duration(seconds: 40);

  /// Max silence between two chunks of the body. Without this, a connection
  /// that dies mid-download (Wi-Fi drops without closing the socket) would hang
  /// until the OS gives up. Dio can watch for this itself (receiveTimeout),
  /// but only when one is configured: ApiClient's shared Dio sets none, and
  /// setting it per request would also shorten the header phase. Enforcing it
  /// here behaves the same on every Dio 5.x.
  static const Duration _idleTimeout = Duration(seconds: 30);

  /// Starting buffer size when the server does not announce a length.
  static const int _initialCapacity = 1024 * 1024;

  /// Fetches [url] into one contiguous buffer.
  ///
  /// [onProgress] receives bytes received so far and the announced total
  /// (null when the server did not send a usable Content-Length).
  ///
  /// Throws:
  ///  * [DioException] for transport / HTTP-status failures (403, 404, 5xx,
  ///    DNS, TLS / pinning mismatch, cancel, ...)
  ///  * [TimeoutException] if the server or the connection stalls
  ///  * [OnlinePdfTooLargeException], [OnlinePdfInvalidException]
  static Future<Uint8List> fetch({
    required Dio dio,
    required String url,
    required CancelToken cancelToken,
    Map<String, dynamic>? queryParameters,
    void Function(int received, int? total)? onProgress,
  }) async {
    final Response<ResponseBody> response = await dio
        .get<ResponseBody>(
          url,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          // Stream: lets us enforce the size cap and an idle timeout, and fill
          // ONE buffer instead of letting Dio assemble the body for us.
          options: Options(responseType: ResponseType.stream),
        )
        .timeout(_headersTimeout, onTimeout: () {
      cancelToken.cancel('timed out waiting for the server');
      throw TimeoutException(
          'No response from the server within ${_headersTimeout.inSeconds}s');
    });

    final ResponseBody body = response.data!;

    // Content-Length is only a hint: it is absent for chunked responses, and
    // for a transparently decompressed body it describes the compressed size.
    final int? declared = int.tryParse(
        response.headers[Headers.contentLengthHeader]?.first ?? '');
    final int? total = (declared != null && declared > 0) ? declared : null;

    if (total != null && total > maxBytes) {
      cancelToken.cancel('PDF larger than the in-memory limit'); // frees the socket
      throw OnlinePdfTooLargeException(limitBytes: maxBytes, sizeBytes: total);
    }

    var buffer = Uint8List(total ?? _initialCapacity);
    var length = 0;

    final Stream<Uint8List> chunks = body.stream.timeout(
      _idleTimeout,
      onTimeout: (sink) {
        sink.addError(TimeoutException(
            'No data received for ${_idleTimeout.inSeconds}s'));
        sink.close();
      },
    );

    // Leaving this loop by throwing cancels the subscription, which closes
    // the connection.
    await for (final chunk in chunks) {
      final int needed = length + chunk.length;
      if (needed > maxBytes) {
        throw OnlinePdfTooLargeException(
            limitBytes: maxBytes, sizeBytes: needed);
      }
      if (needed > buffer.length) {
        // No (or wrong) length hint: grow geometrically, never past the cap.
        var capacity = buffer.length * 2;
        if (capacity < needed) capacity = needed;
        if (capacity > maxBytes) capacity = maxBytes;
        final bigger = Uint8List(capacity)..setRange(0, length, buffer);
        buffer.fillRange(0, length, 0); // don't leave a stale copy behind
        buffer = bigger;
      }
      buffer.setRange(length, needed, chunk);
      length = needed;
      onProgress?.call(length, total);
    }

    if (length == 0) {
      throw const OnlinePdfInvalidException('empty response body');
    }

    // A view, not a copy, when the buffer is larger than what was received.
    final Uint8List bytes =
        length == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, length);

    if (!_hasPdfHeader(bytes)) {
      bytes.fillRange(0, bytes.length, 0);
      throw const OnlinePdfInvalidException('response is not a PDF');
    }
    return bytes;
  }

  /// PDFium accepts the "%PDF-" marker anywhere in the first 1024 bytes.
  static bool _hasPdfHeader(Uint8List b) {
    final int scan = (b.length < 1024 ? b.length : 1024) - 4;
    for (var i = 0; i < scan; i++) {
      if (b[i] == 0x25 && // %
          b[i + 1] == 0x50 && // P
          b[i + 2] == 0x44 && // D
          b[i + 3] == 0x46 && // F
          b[i + 4] == 0x2D) {
        // -
        return true;
      }
    }
    return false;
  }
}
