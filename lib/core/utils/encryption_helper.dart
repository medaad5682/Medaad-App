import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class EncryptionHelper {
  // ✅ تم التعديل: 512KB (نصف ميجابايت)
  // هذا الحجم مثالي جداً للفيديوهات ويقلل الحمل على المعالج بشكل كبير
  static const int CHUNK_SIZE = 32 * 1024; 
  
  static const int IV_LENGTH = 12;
  static const int TAG_LENGTH = 16;
  
  // الحجم الكلي للكتلة المشفرة (يتم حسابه تلقائياً)
  static const int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

  static encrypt.Key? _key;
  
  // الاحتفاظ بمحرك التشفير لتجنب إعادة تهيئته (سرعة x10)
  static encrypt.Encrypter? _encrypter;
  
  static final _storage = const FlutterSecureStorage();

  /// تهيئة المفتاح ومحرك التشفير
  static Future<void> init() async {
    try {
      String? storedKey = await _storage.read(key: 'app_master_key');
      
      if (storedKey == null) {
        // [FIX F-10] تم إزالة سجلات Crashlytics التي تفشي وقت توليد المفتاح
        final keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
        storedKey = base64UrlEncode(keyBytes);
        await _storage.write(key: 'app_master_key', value: storedKey);
      } else {
        // [FIX F-10] تم إزالة سجل تحميل المفتاح من التخزين
      }
      
      _key = encrypt.Key.fromBase64(storedKey);

      // ✅ إنشاء المحرك مرة واحدة فقط
      _encrypter = encrypt.Encrypter(encrypt.AES(_key!, mode: encrypt.AESMode.gcm));

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'CRITICAL: EncryptionHelper.init failed',
        fatal: true 
      );
      throw Exception("Failed to initialize encryption: $e");
    }
  }

  static encrypt.Key get key {
    if (_key == null) {
      final e = Exception("Encryption Key not initialized! Call EncryptionHelper.init() first.");
      FirebaseCrashlytics.instance.recordError(e, null, reason: 'Key access before init');
      throw e;
    }
    return _key!;
  }

  /// تشفير كتلة من البيانات
  static Uint8List encryptBlock(Uint8List data) {
    if (_encrypter == null) throw Exception("Encryption not initialized! Call init() first.");

    try {
      final iv = encrypt.IV.fromSecureRandom(IV_LENGTH);
      
      // ✅ استخدام المحرك الجاهز
      final encrypted = _encrypter!.encryptBytes(data, iv: iv);

      final result = BytesBuilder();
      result.add(iv.bytes);
      result.add(encrypted.bytes);
      
      return result.toBytes();

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'EncryptBlock Failed',
        information: ['Data Length: ${data.length}']
      );
      throw e;
    }
  }

  /// فك تشفير كتلة
  static Uint8List decryptBlock(Uint8List encryptedBlock) {
    if (_encrypter == null) throw Exception("Encryption not initialized! Call init() first.");

    try {
      if (encryptedBlock.length < IV_LENGTH) {
          throw Exception("Invalid encrypted block size: ${encryptedBlock.length}");
      }

      final iv = encrypt.IV(encryptedBlock.sublist(0, IV_LENGTH));
      final cipherBytes = encryptedBlock.sublist(IV_LENGTH);

      // ✅ استخدام المحرك الجاهز (أسرع عملية في الكود)
      final decrypted = _encrypter!.decryptBytes(
        encrypt.Encrypted(cipherBytes), 
        iv: iv
      );

      return Uint8List.fromList(decrypted);

    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'DecryptBlock Failed',
        information: [
          'Block Size: ${encryptedBlock.length}',
          'IV Length: $IV_LENGTH'
        ]
      );
      throw e;
    }
  }

  /// دالة مساعدة لفك تشفير ملف كامل
  static Future<File> decryptFileFull(File encryptedFile, String outputPath) async {
    if (_key == null) await init();

    if (!await encryptedFile.exists()) {
      throw Exception("Source file does not exist: ${encryptedFile.path}");
    }

    final rafRead = await encryptedFile.open(mode: FileMode.read);
    final rafWrite = await File(outputPath).open(mode: FileMode.write);

    try {
      final int fileLength = await encryptedFile.length();
      int currentPos = 0;
      
      // سيأخذ القيمة الجديدة تلقائياً (512KB + Overhead)
      const int blockSize = ENCRYPTED_CHUNK_SIZE;

      // [FIX F-10] تم إزالة سجلدأ عملية فك التشفير لعدم إعطاء أي معلومات

      while (currentPos < fileLength) {
        int bytesToRead = blockSize;
        if (currentPos + bytesToRead > fileLength) {
          bytesToRead = fileLength - currentPos;
        }

        Uint8List chunk = await rafRead.read(bytesToRead);
        if (chunk.isEmpty) break;

        try {
          Uint8List decryptedChunk = decryptBlock(chunk);
          await rafWrite.writeFrom(decryptedChunk);
        } catch (blockError) {
          FirebaseCrashlytics.instance.log("Failed at position: $currentPos");
          throw blockError;
        }

        currentPos += chunk.length;
      }
      
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'DecryptFileFull Failed');
      throw e;
    } finally {
      await rafRead.close();
      await rafWrite.flush();
      await rafWrite.close();
    }
    
    return File(outputPath);
  }
}
