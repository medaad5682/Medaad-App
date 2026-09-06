import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// تشفير لقطات إطارات الفيديو (Video Frame Screenshots) بخوارزمية
/// ChaCha20-Poly1305 بدلاً من AES-256-GCM.
///
/// لماذا ChaCha20 هنا تحديداً؟
/// ChaCha20 لا تعتمد على تسريع عتادي مخصص (AES-NI / ARMv8 Crypto
/// Extensions) — فهي مبنية على عمليات ALU بسيطة (جمع/تدوير/xor) متوفرة
/// على أي معالج تقريباً. على الأجهزة الضعيفة/القديمة التي لا تملك تسريع
/// AES في العتاد، ينخفض أداء AES بشكل ملحوظ (fallback برمجي بطيء) بينما
/// يبقى أداء ChaCha20 ثابتاً وسريعاً — لذا هي الأنسب لهذا المسار
/// (التقاط لقطات متكررة أثناء تشغيل الفيديو).
///
/// ✅ يستخدم مفتاحاً مستقلاً (`screenshots_chacha_key`) مخزَّناً في
/// Keychain/Keystore عبر flutter_secure_storage، منفصل تماماً عن مفتاح
/// AES الرئيسي (`app_master_key`) المستخدم لتشفير الفيديوهات — بحيث لا
/// يتأثر أي جزء آخر من التطبيق بهذا التغيير.
///
/// تخطيط الملف الناتج مطابق لما تستخدمه [FileCryptoService] لبقاء
/// الاتساق داخل المشروع: `nonce (12 بايت) + cipherText + mac (16 بايت)`.
///
/// ⚠️ ملاحظة توافقية: أي لقطات قديمة كانت مشفّرة بـ AES-256-GCM (عبر
/// EncryptionHelper القديم) لن تُفك بهذه الخوارزمية بعد هذا التحديث.
/// هذا متوقع ومقبول أثناء مرحلة التطوير الحالية (لا حاجة لهجرة اللقطات
/// القديمة).
class ScreenshotCryptoService {
  static final Chacha20 _algorithm = Chacha20.poly1305Aead();

  static const int NONCE_LENGTH = 12;
  static const int MAC_LENGTH = 16;

  static const String _keyStorageName = 'screenshots_chacha_key';

  static SecretKey? _key;

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// تهيئة/تحميل المفتاح (lazy init - يُستدعى تلقائياً عند أول استخدام،
  /// بنفس نمط FileCryptoService.init الموجود مسبقاً في المشروع).
  static Future<void> _ensureInit() async {
    if (_key != null) return;

    try {
      final storedKey = await _storage.read(key: _keyStorageName);

      if (storedKey == null) {
        final keyBytes =
            List<int>.generate(32, (_) => Random.secure().nextInt(256));
        await _storage.write(
          key: _keyStorageName,
          value: base64UrlEncode(keyBytes),
        );
        _key = SecretKey(keyBytes);
      } else {
        _key = SecretKey(base64Url.decode(storedKey));
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'ScreenshotCryptoService.init failed',
        fatal: false,
      );
      throw Exception('Failed to initialize screenshot encryption: $e');
    }
  }

  /// تشفير كتلة بايتات (PNG للقطة فيديو) بـ ChaCha20-Poly1305.
  /// تعمل بالكامل في الذاكرة — لا كتابة على القرص هنا.
  static Future<Uint8List> encryptBlock(Uint8List data) async {
    await _ensureInit();

    try {
      final nonce =
          List<int>.generate(NONCE_LENGTH, (_) => Random.secure().nextInt(256));

      final secretBox = await _algorithm.encrypt(
        data,
        secretKey: _key!,
        nonce: nonce,
      );

      final builder = BytesBuilder(copy: false);
      builder.add(nonce);
      builder.add(secretBox.cipherText);
      builder.add(secretBox.mac.bytes);

      return builder.toBytes();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'ScreenshotCryptoService.encryptBlock failed',
        information: ['Data Length: ${data.length}'],
      );
      rethrow;
    }
  }

  /// فك تشفير كتلة لقطة فيديو (في الذاكرة فقط، لا نسخة مفكوكة تُكتب
  /// على القرص أبداً).
  static Future<Uint8List> decryptBlock(Uint8List encryptedBlock) async {
    await _ensureInit();

    try {
      if (encryptedBlock.length < NONCE_LENGTH + MAC_LENGTH) {
        throw Exception(
            'Invalid encrypted block size: ${encryptedBlock.length}');
      }

      final nonce = encryptedBlock.sublist(0, NONCE_LENGTH);
      final cipherText = encryptedBlock.sublist(
        NONCE_LENGTH,
        encryptedBlock.length - MAC_LENGTH,
      );
      final macBytes =
          encryptedBlock.sublist(encryptedBlock.length - MAC_LENGTH);

      final decrypted = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: _key!,
      );

      return Uint8List.fromList(decrypted);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'ScreenshotCryptoService.decryptBlock failed',
        information: ['Block Size: ${encryptedBlock.length}'],
      );
      rethrow;
    }
  }
}
