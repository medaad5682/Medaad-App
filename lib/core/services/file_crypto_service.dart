import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'storage_service.dart';

class FileCryptoService {
  // ✅ [FIX F-02] استخدام Poly1305 لضمان سلامة وموثوقية التشفير (AEAD)
  static final _algorithm = Chacha20.poly1305Aead();
  static const int NONCE_LENGTH = 12;
  static const int MAC_LENGTH = 16; // ✅ إضافة حجم الـ MAC

  static const int CHUNK_SIZE = 32 * 1024;
  // ✅ الحجم الكلي للجزء المشفر أصبح: 12 (Nonce) + 32768 (البيانات) + 16 (MAC)
  static const int ENCRYPTED_CHUNK_SIZE = NONCE_LENGTH + CHUNK_SIZE + MAC_LENGTH;

  static SecretKey? _key;
  // ✅ [FIX] نحتفظ بالمفتاح كنص base64 أيضاً حتى تستطيع خدمات أخرى
  // (LocalProxyService) الحصول عليه دون إعادة قراءته من Keychain بشكل
  // مستقل ومكرر عبر مثيل FlutterSecureStorage خاص بها.
  static String? keyBase64;

  // ✅ [FIX] نفس صنف الحماية first_unlock_this_device المستخدم لـ hive_key
  // و app_master_key — القيمة الافتراضية القديمة (whenUnlocked) كانت عرضة
  // لنفس سباق -25308.
  static final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> init() async {
    if (_key != null) return;

    // ✅ [FIX] StorageService.readSecureValueSafely() ينتظر _AppReadyGate
    // ويعيد المحاولة بدل قراءة Keychain مباشرة مرة واحدة.
    String? storedKey = await StorageService.readSecureValueSafely(
      'docs_chacha_key',
      storage: _storage,
    );
    List<int> keyBytes;

    if (storedKey == null) {
      keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
      storedKey = base64Encode(keyBytes);
      await StorageService.writeSecureValueSafely(
        'docs_chacha_key',
        storedKey,
        storage: _storage,
      );
    } else {
      keyBytes = base64Decode(storedKey);
    }

    keyBase64 = storedKey;
    _key = SecretKey(keyBytes);
  }

  static Future<Uint8List> encryptChunkOnTheFly(List<int> data) async {
    await init();
    final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));

    final secretBox = await _algorithm.encrypt(
      data,
      secretKey: _key!,
      nonce: nonce,
    );

    final builder = BytesBuilder(copy: false);
    builder.add(nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes); // ✅ دمج الـ MAC في النهاية

    return builder.toBytes();
  }

  static Future<void> encryptFileChunked(String inputPath, String outputPath) async {
    await init();

    final inFile = File(inputPath);
    final outFile = File(outputPath);
    final rafRead = await inFile.open(mode: FileMode.read);
    final iosWrite = outFile.openWrite();

    try {
      final int fileLength = await inFile.length();
      int currentPos = 0;

      while (currentPos < fileLength) {
        final chunk = await rafRead.read(CHUNK_SIZE);
        final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));

        final secretBox = await _algorithm.encrypt(
          chunk,
          secretKey: _key!,
          nonce: nonce,
        );

        iosWrite.add(nonce);
        iosWrite.add(secretBox.cipherText);
        iosWrite.add(secretBox.mac.bytes); // ✅ كتابة الـ MAC

        currentPos += chunk.length;
      }
    } finally {
      await rafRead.close();
      await iosWrite.close();
    }
  }

  static Future<Uint8List> readAndDecryptRange(File encryptedFile, int offset, int length) async {
    await init();
    final raf = await encryptedFile.open(mode: FileMode.read);
    final builder = BytesBuilder(copy: false);

    try {
      final int fileSize = await encryptedFile.length();
      int currentReadOffset = offset;
      int remainingLength = length;

      while (remainingLength > 0) {
        int chunkIndex = currentReadOffset ~/ CHUNK_SIZE;
        int chunkStartInFile = chunkIndex * ENCRYPTED_CHUNK_SIZE;

        if (chunkStartInFile >= fileSize) break;

        await raf.setPosition(chunkStartInFile);
        final encryptedBlock = await raf.read(ENCRYPTED_CHUNK_SIZE);

        // ✅ التحقق من وجود مساحة تكفي للـ Nonce والـ MAC
        if (encryptedBlock.isEmpty || encryptedBlock.length <= NONCE_LENGTH + MAC_LENGTH) break;

        final nonce = encryptedBlock.sublist(0, NONCE_LENGTH);
        final cipherText = encryptedBlock.sublist(NONCE_LENGTH, encryptedBlock.length - MAC_LENGTH);
        final macBytes = encryptedBlock.sublist(encryptedBlock.length - MAC_LENGTH); // ✅ استخراج الـ MAC

        // ── Fix: don't let one bad chunk silently blank the entire read ──
        // This used to be inside the outer try/catch, so a single failed
        // chunk (wrong MAC, truncated block, etc.) made the *whole* read
        // return empty bytes with no signal. That empty/partial buffer was
        // then fed straight to PDFium via the pdfrx custom read callback,
        // which is exactly the kind of malformed input that produced the
        // native EXC_BREAKPOINT crash inside PDFium's cross-ref/stream
        // parser. Now we isolate the decrypt call per chunk, log it, and
        // stop cleanly — returning whatever valid bytes were already
        // decrypted — instead of masking a real corruption as "0 bytes".
        List<int> decryptedChunk;
        try {
          decryptedChunk = await _algorithm.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
            secretKey: _key!,
          );
        } catch (e) {
          debugPrint(
              "FileCryptoService: chunk $chunkIndex failed to decrypt/authenticate ($e) — stopping read at offset $currentReadOffset instead of returning corrupted data.");
          break;
        }

        int startInChunk = currentReadOffset % CHUNK_SIZE;
        int availableInChunk = decryptedChunk.length - startInChunk;

        if (availableInChunk <= 0) break;

        int bytesToTake = min(remainingLength, availableInChunk);
        builder.add(decryptedChunk.sublist(startInChunk, startInChunk + bytesToTake));

        currentReadOffset += bytesToTake;
        remainingLength -= bytesToTake;
      }

      return builder.toBytes();
    } catch (e) {
      return Uint8List(0);
    } finally {
      await raf.close();
    }
  }
}
