import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../services/storage_service.dart';

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
  
  // ✅ [FIX] نفس صنف الحماية first_unlock_this_device المستخدم لـ hive_key —
  // بلا هذا، القراءة الافتراضية (whenUnlocked) تفشل بشكل متقطع
  // (errSecInteractionNotAllowed / -25308) في نفس اللحظات التي كانت تسبب
  // مشكلة hive_key: إطلاق بارد فور فتح القفل، أو عودة من الخلفية أثناء
  // استكمال iOS لتفعيل الـ scene.
  static final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// تهيئة المفتاح ومحرك التشفير
  static Future<void> init() async {
    try {
      // ✅ [FIX] نمر عبر StorageService.readSecureValueSafely() بدل قراءة
      // Keychain مباشرة: هذا ينتظر _AppReadyGate (الإطار الأول + resumed)
      // ويعيد المحاولة 3 مرات — بالضبط نفس الحماية المطبّقة على hive_key،
      // وهي التي كانت غائبة هنا وتسبب كراش "EncryptionHelper.init failed".
      String? storedKey = await StorageService.readSecureValueSafely(
        'app_master_key',
        storage: _storage,
      );

      if (storedKey == null) {
        // [FIX F-10] تم إزالة سجلات Crashlytics التي تفشي وقت توليد المفتاح
        final keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
        storedKey = base64UrlEncode(keyBytes);
        await StorageService.writeSecureValueSafely(
          'app_master_key',
          storedKey,
          storage: _storage,
        );
      } else {
        // [FIX F-10] تم إزالة سجل تحميل المفتاح من التخزين
      }
      
      _key = encrypt.Key.fromBase64(storedKey);

      // ✅ إنشاء المحرك مرة واحدة فقط
      _encrypter = encrypt.Encrypter(encrypt.AES(_key!, mode: encrypt.AESMode.gcm));

    } catch (e, stack) {
      // ✅ [FIX] لم يعد fatal: true. هذا الاستثناء مُلتقَط ومُعالَج فعلياً من
      // قِبل المستدعي (LocalProxyService.start() يوقف نفسه بأمان عبر
      // stop() ولا ينهار التطبيق) — ترقيته إلى "قاتل" هنا كان يزيّف معدل
      // Crashlytics بكراشات وهمية لخطأ تمت معالجته فعلاً، ويخفي في نفس
      // الوقت الرسالة الأصلية (OSStatus) خلف موقع استدعاء recordError نفسه.
      // بعد إصلاح سباق Keychain أعلاه، من المتوقع أن يصبح هذا نادراً جداً؛
      // لو استمر تكراره رغم ذلك، هذا مؤشر حقيقي على مشكلة تستحق non-fatal
      // لتتبعها، وليس فتح تنبيه "تعطل قاتل" كاذب.
      FirebaseCrashlytics.instance.recordError(
        e, 
        stack, 
        reason: 'EncryptionHelper.init failed',
        fatal: false,
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
}
