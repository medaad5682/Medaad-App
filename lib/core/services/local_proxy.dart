import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:cryptography/cryptography.dart' as crypto; // لتشفير ChaCha20
import 'package:crypto/crypto.dart' as hmac_crypto; // ✅ [FIX F-08] مكتبة التوقيع HMAC

import '../utils/encryption_helper.dart';
import 'file_crypto_service.dart';

// ✅ إضافة دالة آمنة للطباعة تظهر فقط في وضع التطوير (Debug) 
// ويتم إزالتها تلقائياً في نسخة الإنتاج (Release) لمنع تسريب السجلات
void _safePrint(Object? message) {
  assert(() {
    print(message);
    return true;
  }());
}

class LocalProxyService {
  static final LocalProxyService _instance = LocalProxyService._internal();

  factory LocalProxyService() {
    return _instance;
  }

  LocalProxyService._internal();

  // Separate processing threads
  Isolate? _videoServerIsolate;
  Isolate? _audioServerIsolate;

  int _videoPort = 0;
  int _audioPort = 0;

  // ✅ [FIX F-08] سر التوقيع الديناميكي بدلاً من التوكن الثابت
  String _hmacSecret = "";

  int get videoPort => _videoPort;
  int get audioPort => _audioPort;

  ReceivePort? _videoReceivePort;
  ReceivePort? _audioReceivePort;

  Completer<void>? _readyCompleter;

  // ✅ [FIX - RACE] يمنع أكثر من عملية start() من التنفيذ بالتوازي على نفس
  // الـ singleton. قبل هذا الإصلاح، فتح شاشتي فيديو بسرعة (قبل أن تنتهي
  // start() الأولى) كان يتسبب في: (1) تعارض على _readyCompleter يؤدي إلى
  // "Bad state: Future already completed"، (2) تسريب Isolates لأن مرجع
  // الـ Isolate الأول يُستبدل بمرجع الثاني قبل قتله، (3) توليد _hmacSecret
  // جديد يُبطل روابط موقّعة سبق إنشاؤها. الحل: أي استدعاء ثانٍ يحدث أثناء
  // تنفيذ استدعاء أول ينتظر نفس الـ Future بدل أن يبدأ عملية منافسة.
  Future<void>? _startFuture;

  // ✅ [FIX F-08] دالة ذكية لتوليد روابط آمنة ومشفرة للمشغل مع وقت انتهاء الصلاحية
  String getSignedUrl(String filePath, {bool isAudio = false}) {
    if (_hmacSecret.isEmpty) throw Exception("Proxy not initialized");
    final port = isAudio ? _audioPort : _videoPort;
    
    // الرابط صالح لمدة ساعتين فقط (لمنع Replay Attacks)
    final expires = DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
    
    // ربط التوقيع بالمسار ووقت الانتهاء
    final dataToSign = "path=$filePath&expires=$expires";
    final hmac = hmac_crypto.Hmac(hmac_crypto.sha256, utf8.encode(_hmacSecret));
    final sig = hmac.convert(utf8.encode(dataToSign)).toString();
    
    final encodedPath = Uri.encodeComponent(filePath);
    return 'http://127.0.0.1:$port/video?path=$encodedPath&expires=$expires&sig=$sig';
  }

  Future<void> start() async {
    // Keep-Alive: If server is already running, do nothing and return immediately
    if (_videoServerIsolate != null &&
        _audioServerIsolate != null &&
        _videoPort != 0 &&
        _audioPort != 0) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        await _readyCompleter!.future;
      }
      return;
    }

    // ✅ [FIX - RACE] لو فيه عملية بدء شغّالة بالفعل (استدعاء سابق لم ينتهِ
    // بعد)، ننتظر نتيجتها بدل ما نبدأ عملية ثانية منافسة تكتب فوق نفس
    // الحقول (isolates, ports, hmacSecret, completer).
    if (_startFuture != null) {
      return _startFuture;
    }

    final future = _doStart();
    _startFuture = future;
    try {
      await future;
    } finally {
      _startFuture = null;
    }
  }

  Future<void> _doStart() async {
    _readyCompleter = Completer<void>();

    try {
      // 1. تهيئة كلا الخدمتين لضمان وجود المفاتيح قبل قراءتها
      await EncryptionHelper.init();
      await FileCryptoService.init();

      // 2. جلب كلا المفتاحين (AES و ChaCha20)
      String aesKeyBase64 = EncryptionHelper.key.base64;

      // ✅ [FIX] لم نعد نعيد قراءة docs_chacha_key من Keychain هنا بمثيل
      // FlutterSecureStorage منفصل وغير محمي (بلا first_unlock_this_device
      // وبلا انتظار _AppReadyGate). FileCryptoService.init() أعلاه قرأه أو
      // ولّده بالفعل بأمان تام؛ نأخذه مباشرة من هناك بدل تكرار عملية
      // Keychain كاملة (وتعريض الكود مجدداً لنفس سباق -25308).
      final String chachaKeyBase64 = FileCryptoService.keyBase64 ?? '';

      if (chachaKeyBase64.isEmpty) {
        throw Exception("CRITICAL: ChaCha20 key is missing!");
      }

      // ✅ 3. [FIX F-08] توليد سر قوي (256-bit) لعمليات التوقيع HMAC
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      _hmacSecret = base64UrlEncode(values);
      _safePrint('🔒 [SECURITY] HMAC Secret Generated for Local Proxy');

      // 4. Start Video Server (Port 0 = Random)
      _videoReceivePort = ReceivePort();
      _videoServerIsolate = await Isolate.spawn(
          _proxyServerEntryPoint,
          _ProxyInitData(_videoReceivePort!.sendPort, aesKeyBase64,
              chachaKeyBase64, "VideoIsolate", _hmacSecret));

      // Wait for ready message with port number
      await for (final message in _videoReceivePort!) {
        if (message is String && message.startsWith("READY:")) {
          _videoPort = int.parse(message.split(':')[1]);
          _safePrint('🔍 [DIAGNOSIS] Video Proxy Started on dynamic port: $_videoPort');
          break;
        } else if (message.toString().startsWith("ERROR")) {
          throw Exception("Video Proxy Failed: $message");
        }
      }

      // 5. Start Audio Server (Port 0 = Random)
      _audioReceivePort = ReceivePort();
      _audioServerIsolate = await Isolate.spawn(
          _proxyServerEntryPoint,
          _ProxyInitData(_audioReceivePort!.sendPort, aesKeyBase64,
              chachaKeyBase64, "AudioIsolate", _hmacSecret));

      // Wait for ready message with port number
      await for (final message in _audioReceivePort!) {
        if (message is String && message.startsWith("READY:")) {
          _audioPort = int.parse(message.split(':')[1]);
          _safePrint('🔍 [DIAGNOSIS] Audio Proxy Started on dynamic port: $_audioPort');
          break;
        } else if (message.toString().startsWith("ERROR")) {
          throw Exception("Audio Proxy Failed: $message");
        }
      }

      _readyCompleter?.complete();
    } catch (e) {
      _safePrint("❌ Proxy Launch Error: $e");
      _readyCompleter?.completeError(e);
      stop();
    }
  }

  void stop() {
    _readyCompleter = null;
    _videoPort = 0;
    _audioPort = 0;
    _hmacSecret = ""; // تصفير السر

    if (_videoServerIsolate != null) {
      _safePrint('🛑 Stopping Video Proxy');
      _videoReceivePort?.close();
      _videoServerIsolate?.kill(priority: Isolate.immediate);
      _videoServerIsolate = null;
    }

    if (_audioServerIsolate != null) {
      _safePrint('🛑 Stopping Audio Proxy');
      _audioReceivePort?.close();
      _audioServerIsolate?.kill(priority: Isolate.immediate);
      _audioServerIsolate = null;
    }
  }
}

class _ProxyInitData {
  final SendPort sendPort;
  final String aesKeyBase64;
  final String chachaKeyBase64;
  final String name;
  final String hmacSecret; // ✅ السر الخاص بالتوقيع

  _ProxyInitData(this.sendPort, this.aesKeyBase64, this.chachaKeyBase64,
      this.name, this.hmacSecret);
}

void _proxyServerEntryPoint(_ProxyInitData initData) async {
  try {
    // 1. تجهيز مفتاح AES للملفات القديمة
    final aesKey = encrypt.Key.fromBase64(initData.aesKeyBase64);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(aesKey, mode: encrypt.AESMode.gcm));

    // 2. تجهيز مفتاح ChaCha20 للملفات الجديدة
    final List<int> chachaKeyBytes = base64Decode(initData.chachaKeyBase64);

    final router = Router();

    // نمرر المفاتيح وسر الـ HMAC
    router.get(
        '/video',
        (Request req) => _handleRequest(
            req, encrypter, chachaKeyBytes, initData.name, initData.hmacSecret));
    router.head(
        '/video',
        (Request req) => _handleRequest(
            req, encrypter, chachaKeyBytes, initData.name, initData.hmacSecret));

    // إغلاق الثغرة: الاستماع لـ 127.0.0.1 فقط
    final server = await shelf_io.serve(
        router,
        InternetAddress.loopbackIPv4, 
        0, 
        shared: false);

    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 60);

    initData.sendPort.send("READY:${server.port}");
  } catch (e) {
    initData.sendPort.send("ERROR: $e");
  }
}

Future<Response> _handleRequest(Request request, encrypt.Encrypter encrypter,
    List<int> chachaKeyBytes, String isolateName, String hmacSecret) async {
  final requestStopwatch = Stopwatch()..start();

  try {
    // ✅ [FIX F-08] التحقق من التوقيع وتاريخ الصلاحية
    final pathParam = request.url.queryParameters['path'];
    final expiresParam = request.url.queryParameters['expires'];
    final sigParam = request.url.queryParameters['sig'];

    if (pathParam == null || expiresParam == null || sigParam == null) {
      _safePrint("⛔ [$isolateName] Security Breach: Missing URL Parameters!");
      return Response.forbidden('Access Denied: Missing Parameters');
    }

    // التحقق من انتهاء الصلاحية
    final expires = int.tryParse(expiresParam) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch > expires) {
      _safePrint("⛔ [$isolateName] Security Breach: Link Expired!");
      return Response.forbidden('Access Denied: Link Expired');
    }

    // إعادة إنشاء التوقيع ومطابقته
    final dataToSign = "path=$pathParam&expires=$expiresParam";
    final hmac = hmac_crypto.Hmac(hmac_crypto.sha256, utf8.encode(hmacSecret));
    final expectedSig = hmac.convert(utf8.encode(dataToSign)).toString();

    if (sigParam != expectedSig) {
      _safePrint("⛔ [$isolateName] Security Breach: Invalid HMAC Signature!");
      return Response.forbidden('Access Denied: Invalid Signature');
    }

    final decodedPath = pathParam;
    final file = File(decodedPath);

    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    String contentType = 'video/mp4';
    if (decodedPath.contains('aud_')) {
      contentType = 'audio/mp4';
    } else if (decodedPath.toLowerCase().contains('.pdf')) {
      contentType = 'application/pdf';
    }

    final encryptedLength = await file.length();

    // التعرف على إصدار التشفير
    bool isV2 = decodedPath.endsWith('_v2.enc') || decodedPath.endsWith('.pdf.enc');
    int originalFileSize;

    if (isV2) {
      const int CHUNK_SIZE = 32 * 1024;
      const int NONCE_LENGTH = 12;
      const int MAC_LENGTH = 16;
      const int ENCRYPTED_CHUNK_SIZE = NONCE_LENGTH + CHUNK_SIZE + MAC_LENGTH;

      int numChunks = (encryptedLength / ENCRYPTED_CHUNK_SIZE).ceil();
      originalFileSize = encryptedLength - (numChunks * (NONCE_LENGTH + MAC_LENGTH));
    } else {
      final int CHUNK_SIZE = EncryptionHelper.CHUNK_SIZE;
      const int IV_LENGTH = 12;
      const int TAG_LENGTH = 16;
      final int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

      final int totalChunks = (encryptedLength / ENCRYPTED_CHUNK_SIZE).ceil();
      if (totalChunks == 0) return Response.ok('');

      final int plainChunkSize = CHUNK_SIZE;
      final int overhead = ENCRYPTED_CHUNK_SIZE - plainChunkSize;
      originalFileSize = ((totalChunks - 1) * plainChunkSize) +
          max(0, (encryptedLength - ((totalChunks - 1) * ENCRYPTED_CHUNK_SIZE)) - overhead);
    }

    final rangeHeader = request.headers['range'];
    int start = 0;
    int end = originalFileSize - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty)
        end = int.tryParse(parts[1]) ?? originalFileSize - 1;
    }

    if (start >= originalFileSize) {
      return Response(416,
          body: 'Invalid Range',
          headers: {'Content-Range': 'bytes */$originalFileSize'});
    }

    final contentLength = end - start + 1;

    _safePrint("🔍 [PROXY_REQ] $isolateName | Range: $start-$end | V2: $isV2 | Processing: ${requestStopwatch.elapsedMilliseconds}ms");

    final Map<String, Object> headers = {
      'Content-Type': contentType,
      'Content-Length': contentLength.toString(),
      'Accept-Ranges': 'bytes',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Connection': 'keep-alive',
    };

    if (request.method == 'HEAD') {
      return Response.ok(null, headers: headers);
    }

    headers['Content-Range'] = 'bytes $start-$end/$originalFileSize';

    return Response(
      206,
      body: isV2
          ? _createDecryptedStreamV2(file, start, end, chachaKeyBytes, isolateName) 
          : _createDecryptedStream(file, start, end, encrypter, isolateName),
      headers: headers,
    );
  } catch (e) {
    _safePrint("[$isolateName] Request Error: $e");
    return Response.internalServerError(body: 'Proxy Error');
  }
}

Stream<List<int>> _createDecryptedStreamV2(File file, int reqStart, int reqEnd,
    List<int> chachaKeyBytes, String isolateName) async* {
  final streamStopwatch = Stopwatch()..start();
  RandomAccessFile? raf;
  int totalSent = 0;
  final int requiredLength = reqEnd - reqStart + 1;

  try {
    raf = await file.open(mode: FileMode.read);

    final algorithm = crypto.Chacha20.poly1305Aead();
    final secretKey = crypto.SecretKey(chachaKeyBytes);

    const int CHUNK_SIZE = 32 * 1024;
    const int NONCE_LENGTH = 12;
    const int MAC_LENGTH = 16; 
    const int ENCRYPTED_CHUNK_SIZE = NONCE_LENGTH + CHUNK_SIZE + MAC_LENGTH;

    final int fileSize = await file.length();
    int currentReadOffset = reqStart;
    int remainingLength = requiredLength;

    while (remainingLength > 0) {
      if (totalSent >= requiredLength) break;

      int chunkIndex = currentReadOffset ~/ CHUNK_SIZE;
      int chunkStartInFile = chunkIndex * ENCRYPTED_CHUNK_SIZE;

      if (chunkStartInFile >= fileSize) break;

      await raf.setPosition(chunkStartInFile);
      final encryptedBlock = await raf.read(ENCRYPTED_CHUNK_SIZE);

      if (encryptedBlock.isEmpty || encryptedBlock.length <= NONCE_LENGTH + MAC_LENGTH)
        break;

      final nonce = encryptedBlock.sublist(0, NONCE_LENGTH);
      final cipherText = encryptedBlock.sublist(NONCE_LENGTH, encryptedBlock.length - MAC_LENGTH);
      final macBytes = encryptedBlock.sublist(encryptedBlock.length - MAC_LENGTH);

      final decryptedChunk = await algorithm.decrypt(
        crypto.SecretBox(cipherText, nonce: nonce, mac: crypto.Mac(macBytes)),
        secretKey: secretKey,
      );

      int startInChunk = currentReadOffset % CHUNK_SIZE;
      int availableInChunk = decryptedChunk.length - startInChunk;

      if (availableInChunk <= 0) break;

      int bytesToTake = min(remainingLength, availableInChunk);
      final dataChunk = decryptedChunk.sublist(startInChunk, startInChunk + bytesToTake);

      yield dataChunk;

      totalSent += dataChunk.length;
      currentReadOffset += dataChunk.length;
      remainingLength -= dataChunk.length;
    }

    _safePrint("✅ [PROXY_V2_DONE] $isolateName | Sent: $totalSent bytes | Time: ${streamStopwatch.elapsedMilliseconds}ms");
  } catch (e) {
    _safePrint("❌ Stream V2 Error: $e");
  } finally {
    if (totalSent < requiredLength) {
      int missingBytes = requiredLength - totalSent;
      if (missingBytes > 0 && missingBytes < 1024 * 1024) {
        yield Uint8List(missingBytes);
      }
    }
    await raf?.close();
  }
}

Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd,
    encrypt.Encrypter encrypter, String isolateName) async* {
  final streamStopwatch = Stopwatch()..start();
  RandomAccessFile? raf;
  int totalSent = 0;
  final int requiredLength = reqEnd - reqStart + 1;

  try {
    raf = await file.open(mode: FileMode.read);

    final int CHUNK_SIZE = EncryptionHelper.CHUNK_SIZE;

    const int IV_LENGTH = 12;
    const int TAG_LENGTH = 16;
    final int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

    int startChunkIndex = reqStart ~/ CHUNK_SIZE;
    int endChunkIndex = reqEnd ~/ CHUNK_SIZE;
    final fileLen = await file.length();

    int loopCount = 0;

    for (int i = startChunkIndex; i <= endChunkIndex; i++) {
      if (totalSent >= requiredLength) break;

      if (++loopCount % 32 == 0) {
        await Future.delayed(Duration.zero);
      }

      int seekPos = i * ENCRYPTED_CHUNK_SIZE;
      if (seekPos >= fileLen) break;

      await raf.setPosition(seekPos);

      int bytesToRead = min(ENCRYPTED_CHUNK_SIZE, fileLen - seekPos);
      if (bytesToRead <= IV_LENGTH) break;

      Uint8List encryptedBlock = await raf.read(bytesToRead);
      Uint8List outputBlock;

      try {
        if (encryptedBlock.length < IV_LENGTH) {
          outputBlock = Uint8List(0);
        } else {
          final iv = encrypt.IV(encryptedBlock.sublist(0, IV_LENGTH));
          final cipherBytes = encryptedBlock.sublist(IV_LENGTH);

          final decrypted =
              encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: iv);

          outputBlock = (decrypted is Uint8List)
              ? decrypted
              : Uint8List.fromList(decrypted);
        }
      } catch (e) {
        int expectedSize = (bytesToRead == ENCRYPTED_CHUNK_SIZE)
            ? CHUNK_SIZE
            : max(0, bytesToRead - IV_LENGTH - TAG_LENGTH);
        outputBlock = Uint8List(expectedSize);
      }

      if (outputBlock.isNotEmpty) {
        int blockStartInPlain = i * CHUNK_SIZE;
        int sliceStart = max(0, reqStart - blockStartInPlain);
        int sliceEnd = min(outputBlock.length, reqEnd - blockStartInPlain + 1);

        if (sliceStart < sliceEnd) {
          final dataChunk = outputBlock.sublist(sliceStart, sliceEnd);
          totalSent += dataChunk.length;
          yield dataChunk;
        }
      }
    }
  } catch (e) {
    _safePrint("Stream Error: $e");
  } finally {
    if (totalSent < requiredLength) {
      int missingBytes = requiredLength - totalSent;
      if (missingBytes > 0 && missingBytes < 1024 * 1024) {
        yield Uint8List(missingBytes);
      }
    }
    await raf?.close();
  }
}
