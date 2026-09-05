import 'dart:io';
import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'storage_service.dart';
import '../utils/encryption_helper.dart';

/// خدمة "لقطات الفيديو" (Video Frame Screenshots).
///
/// ⚠️ ليست لقطة شاشة حقيقية (لا تستخدم أي API لتصوير الشاشة، ولا تتعارض مع
/// FLAG_SECURE) — هي التقاط لإطار الفيديو + العلامة المائية فقط عبر
/// RepaintBoundary داخل شجرة الودجت، ثم يتم تشفيرها فوراً قبل أي كتابة على
/// القرص.
///
/// ✅ لا يوجد أي نص صريح (plaintext) للصورة يُكتب على القرص في أي لحظة:
/// - البايتات الخام (PNG) تبقى في الذاكرة فقط.
/// - تُشفَّر عبر [EncryptionHelper.encryptBlock] (AES-256-GCM، نفس المفتاح
///   الرئيسي المستخدم لتشفير الفيديوهات) قبل أي `writeAsBytes`.
/// - القراءة تسير بنفس الاتجاه المعاكس: تُفك التشفير في الذاكرة فقط عند
///   العرض، ولا تُكتب نسخة مفكوكة على القرص أبداً.
///
/// البيانات الوصفية (العنوان، المسار، التاريخ...) تُخزَّن في صندوق Hive
/// مخصص (`screenshots_box`) الذي يُفتح عبر [StorageService.openBox] —
/// وبالتالي هو نفسه مشفّر على مستوى الصندوق (HiveAesCipher)، تماماً مثل
/// `downloads_box`.
class VideoScreenshotRecord {
  final String id;
  final String lessonId;
  final String videoTitle;
  final String? courseTitle;
  final String? subjectTitle;
  final String? chapterTitle;
  final String filePath; // مسار الملف المشفّر (.enc) على القرص
  final DateTime createdAt;

  VideoScreenshotRecord({
    required this.id,
    required this.lessonId,
    required this.videoTitle,
    this.courseTitle,
    this.subjectTitle,
    this.chapterTitle,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'lessonId': lessonId,
        'videoTitle': videoTitle,
        'courseTitle': courseTitle,
        'subjectTitle': subjectTitle,
        'chapterTitle': chapterTitle,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VideoScreenshotRecord.fromMap(Map map) => VideoScreenshotRecord(
        id: map['id'] as String,
        lessonId: map['lessonId'] as String? ?? '',
        videoTitle: map['videoTitle'] as String? ?? '',
        courseTitle: map['courseTitle'] as String?,
        subjectTitle: map['subjectTitle'] as String?,
        chapterTitle: map['chapterTitle'] as String?,
        filePath: map['filePath'] as String,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class VideoScreenshotService {
  static const String boxName = 'screenshots_box';
  static const String _subDir = 'video_screenshots';

  static Future<Box> _box() => StorageService.openBox(boxName);

  static Future<Directory> _dir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_subDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// يشفّر بايتات PNG الخام (من RepaintBoundary.toImage) ويحفظها كملف
  /// `.enc`، ثم يسجّل بيانات وصفية عنها. لا تُكتب أي بايتات غير مشفّرة على
  /// القرص في أي مرحلة من هذه الدالة.
  static Future<VideoScreenshotRecord> saveEncrypted({
    required Uint8List pngBytes,
    required String lessonId,
    required String videoTitle,
    String? courseTitle,
    String? subjectTitle,
    String? chapterTitle,
  }) async {
    final dir = await _dir();
    final now = DateTime.now();
    final id = '${lessonId}_${now.microsecondsSinceEpoch}';
    final filePath = '${dir.path}/$id.png.enc';

    try {
      // ✅ التشفير يتم في الذاكرة فقط — لا ملف مؤقت غير مشفّر إطلاقاً.
      final encryptedBytes = EncryptionHelper.encryptBlock(pngBytes);
      await File(filePath).writeAsBytes(encryptedBytes, flush: true);

      final record = VideoScreenshotRecord(
        id: id,
        lessonId: lessonId,
        videoTitle: videoTitle,
        courseTitle: courseTitle,
        subjectTitle: subjectTitle,
        chapterTitle: chapterTitle,
        filePath: filePath,
        createdAt: now,
      );

      final box = await _box();
      await box.put(id, record.toMap());

      return record;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'VideoScreenshotService.saveEncrypted failed',
        fatal: false,
      );
      rethrow;
    }
  }

  /// يفك تشفير لقطة معينة في الذاكرة فقط (لا يكتب أي نسخة مفكوكة على
  /// القرص) — يُستخدم للعرض في المعرض/الشاشة الكاملة.
  static Future<Uint8List> decryptForView(String filePath) async {
    final file = File(filePath);
    final encryptedBytes = await file.readAsBytes();
    return EncryptionHelper.decryptBlock(encryptedBytes);
  }

  /// كل اللقطات (لكل الفيديوهات)، الأحدث أولاً.
  static Future<List<VideoScreenshotRecord>> listAll() async {
    final box = await _box();
    final records = box.values
        .whereType<Map>()
        .map((m) => VideoScreenshotRecord.fromMap(m))
        .toList();
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  /// اللقطات الخاصة بفصل/مجلد تنزيل معيّن فقط (يُطابق أياً من العنوانين
  /// الممرَّرة إن وُجدت، لأن بعض الشاشات لا تملك كل الحقول الثلاثة).
  static Future<List<VideoScreenshotRecord>> listForChapter({
    String? courseTitle,
    String? subjectTitle,
    String? chapterTitle,
  }) async {
    final all = await listAll();
    return all.where((r) {
      if (courseTitle != null && r.courseTitle != courseTitle) return false;
      if (subjectTitle != null && r.subjectTitle != subjectTitle) {
        return false;
      }
      if (chapterTitle != null && r.chapterTitle != chapterTitle) {
        return false;
      }
      return true;
    }).toList();
  }

  static Future<void> delete(String id) async {
    final box = await _box();
    final map = box.get(id);
    if (map is Map) {
      final record = VideoScreenshotRecord.fromMap(map);
      final file = File(record.filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e, stack) {
          FirebaseCrashlytics.instance.recordError(
            e,
            stack,
            reason: 'VideoScreenshotService.delete: failed removing file',
            fatal: false,
          );
        }
      }
    }
    await box.delete(id);
  }
}
