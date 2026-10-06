import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../services/online_pdf_fetcher.dart';

/// Why a PDF could not be opened. Used to pick the icon and the message on the
/// error page, and as a tag on the Crashlytics report.
enum PdfLoadFailureKind {
  noInternet,
  timeout,

  /// TLS handshake failed (pinned certificate mismatch, wrong device clock,
  /// a network intercepting HTTPS, ...).
  insecureConnection,
  unauthorized,
  notFound,
  server,

  /// Bigger than the in-memory limit of [OnlinePdfFetcher].
  tooLarge,
  corrupted,
  unknown,
}

/// A load failure translated into something safe to show the user.
///
/// Raw exception text is not user-safe: a Dio error can include the request
/// URL, and an offline failure can include the local path of the encrypted
/// file. [message] never contains any of that: it is chosen from a fixed set
/// of strings.
///
/// The raw exception is NOT discarded: callers keep it and send it to
/// Crashlytics. Only the UI is sanitised.
class PdfLoadFailure {
  const PdfLoadFailure(this.kind, this.message);

  final PdfLoadFailureKind kind;

  /// Safe to display. Never contains URLs, hosts, file paths or stack traces.
  final String message;

  // NOTE: strings are hardcoded Arabic on purpose, matching the rest of
  // pdf_viewer_screen.dart (which does not use AppLocalizations). If you move
  // them into the .arb files later, this is the only place to change.
  static const String _msgNoInternet =
      'تعذّر الاتصال بالإنترنت.\nتحقّق من اتصالك ثم حاول مرة أخرى.';
  static const String _msgTimeout =
      'استغرق تحميل الملف وقتاً طويلاً.\nتحقّق من سرعة الإنترنت ثم حاول مرة أخرى.';
  static const String _msgInsecure =
      'تعذّر إنشاء اتصال آمن بالخادم.\nتأكد من صحة التاريخ والوقت على جهازك ومن اتصالك بشبكة موثوقة، ثم حاول مرة أخرى.';
  static const String _msgUnauthorized =
      'تعذّر التحقق من صلاحية الوصول إلى هذا الملف.\nأعد المحاولة، وإن استمرت المشكلة فسجّل الدخول من جديد.';
  static const String _msgNotFound = 'هذا الملف غير متاح حالياً.';
  static const String _msgServer =
      'حدث خطأ في الخادم أثناء تحميل الملف.\nحاول مرة أخرى بعد قليل.';
  static const String _msgTooLarge =
      'حجم الملف كبير جداً للعرض المباشر.\nنزّله على جهازك ثم افتحه بدون اتصال.';
  static const String _msgCorrupted =
      'تعذّر فتح الملف لأنه تالف أو غير مكتمل.\nحاول مرة أخرى.';
  static const String _msgOfflineFile =
      'تعذّر فتح الملف المحمّل على الجهاز.\nجرّب حذفه من التنزيلات ثم تنزيله من جديد.';
  // Same wording the screen already used for unexpected failures.
  static const String _msgUnknown = 'فشل فتح الملف المحمي.';

  static const PdfLoadFailure _noInternet =
      PdfLoadFailure(PdfLoadFailureKind.noInternet, _msgNoInternet);
  static const PdfLoadFailure _timeout =
      PdfLoadFailure(PdfLoadFailureKind.timeout, _msgTimeout);
  static const PdfLoadFailure _insecure =
      PdfLoadFailure(PdfLoadFailureKind.insecureConnection, _msgInsecure);
  static const PdfLoadFailure _unauthorized =
      PdfLoadFailure(PdfLoadFailureKind.unauthorized, _msgUnauthorized);
  static const PdfLoadFailure _notFound =
      PdfLoadFailure(PdfLoadFailureKind.notFound, _msgNotFound);
  static const PdfLoadFailure _server =
      PdfLoadFailure(PdfLoadFailureKind.server, _msgServer);
  static const PdfLoadFailure _tooLarge =
      PdfLoadFailure(PdfLoadFailureKind.tooLarge, _msgTooLarge);
  static const PdfLoadFailure _corrupted =
      PdfLoadFailure(PdfLoadFailureKind.corrupted, _msgCorrupted);
  static const PdfLoadFailure _unknown =
      PdfLoadFailure(PdfLoadFailureKind.unknown, _msgUnknown);

  /// The device reports no network at all (checked before any request is made).
  factory PdfLoadFailure.noInternet() => _noInternet;

  /// Classifies an exception raised while opening a PDF.
  ///
  /// [isOffline] is true when the document comes from the encrypted local file
  /// (no network is involved there, so any failure means the file itself).
  factory PdfLoadFailure.from(Object error, {required bool isOffline}) {
    if (isOffline) {
      return const PdfLoadFailure(
          PdfLoadFailureKind.corrupted, _msgOfflineFile);
    }

    // Thrown by OnlinePdfFetcher itself.
    if (error is OnlinePdfTooLargeException) return _tooLarge;
    if (error is OnlinePdfInvalidException) return _corrupted;
    if (error is TimeoutException) return _timeout;

    if (error is DioException) {
      final fromDio = _fromDio(error);
      if (fromDio != null) return fromDio;
    }

    // Raw transport errors can also escape while the body is streamed
    // (Dio only wraps what happens up to the response headers).
    if (_isTlsFailure(error)) return _insecure;
    if (error is SocketException || error is HttpException) return _noInternet;

    final lower = error.toString().toLowerCase();
    if (_looksLikeNetworkFailure(lower)) return _noInternet;

    // PDFium: "Failed to load PDF document (FPDF_ERR_FORMAT: 3)."
    if (lower.contains('fpdf_err_format') ||
        lower.contains('failed to load pdf document')) {
      return _corrupted;
    }

    return _unknown;
  }

  /// Maps a [DioException]; null means "not conclusive, try the generic
  /// checks".
  ///
  /// The `default` is deliberate and must stay: DioExceptionType gained a value
  /// (`transformTimeout`) between Dio 5.9.0 and 5.10.0 and pubspec allows both,
  /// so an exhaustive switch would fail to compile on one of them, and naming
  /// the new value would fail on the other. Unlisted types are simply treated
  /// as inconclusive.
  static PdfLoadFailure? _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _timeout;
      case DioExceptionType.badCertificate:
        return _insecure;
      case DioExceptionType.badResponse:
        return _fromStatus(e.response?.statusCode);
      case DioExceptionType.connectionError:
        // DNS / refused / unreachable (SocketException). A TLS failure can be
        // reported here too, so look at the wrapped error.
        return _isTlsFailure(e.error) ? _insecure : _noInternet;
      case DioExceptionType.cancel:
        return null;
      case DioExceptionType.unknown:
        // Dio only converts SocketException; a pinned-certificate mismatch
        // (HandshakeException) arrives here, wrapped as `unknown`.
        final inner = e.error;
        if (inner is TimeoutException) return _timeout;
        if (_isTlsFailure(inner)) return _insecure;
        if (inner is SocketException || inner is HttpException) {
          return _noInternet;
        }
        return null;
      default:
        return null;
    }
  }

  static PdfLoadFailure _fromStatus(int? code) {
    if (code == 401 || code == 403) return _unauthorized;
    if (code == 404 || code == 410) return _notFound;
    return _server; // other 4xx, 5xx, or no status at all
  }

  /// HandshakeException and CertificateException both extend TlsException.
  static bool _isTlsFailure(Object? e) => e is TlsException;

  static const List<String> _networkFragments = <String>[
    'socketexception',
    'failed host lookup',
    'no address associated with hostname',
    'nodename nor servname',
    'network is unreachable',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection abort',
    'connection timed out',
    'timed out',
  ];

  static bool _looksLikeNetworkFailure(String lowerCaseText) {
    for (final fragment in _networkFragments) {
      if (lowerCaseText.contains(fragment)) return true;
    }
    return false;
  }
}
