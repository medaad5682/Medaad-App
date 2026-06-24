import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// ✅ خدمة التعامل الآمن مع الملفات المؤقتة غير المشفرة (فيديو/صوت/دمج)
///
/// الهدف: ضمان عدم بقاء أي ملف فيديو "مفكوك التشفير" بشكل دائم على التخزين.
/// كل ملفات هذه الخدمة هي ملفات عابرة (transient) فقط أثناء مرحلة:
/// تحميل -> دمج (Mux) -> تشفير -> حذف فوري وآمن للملفات الوسيطة.
///
/// ملاحظة: هذا "ضمان الحالة المستقرة" (steady-state guarantee) - أي أنه لا يوجد
/// ملف غير مشفر دائم على القرص في أي وقت يكون التطبيق فيه خاملاً أو بعد انتهاء
/// أي عملية. لا يضمن صفر بايت غير مشفر يلمس القرص لحظياً أثناء التنفيذ نفسه.
class SecureTempService {
  static const String _tempSubDir = 'mux_tmp';

  /// مجلد العمل المؤقت الخاص بعمليات التحميل/الدمج (داخل تخزين التطبيق الخاص،
  /// غير قابل للوصول من تطبيقات أخرى وغير ظاهر للمستخدم عبر مدير الملفات العام)
  static Future<Directory> getWorkDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/$_tempSubDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// توليد مسار مؤقت فريد لمهمة تحميل/دمج معيّنة (بحسب lessonId)
  static Future<String> newTempPath(String lessonId, String suffix) async {
    final dir = await getWorkDir();
    final rand = Random.secure().nextInt(1 << 32);
    return '${dir.path}/${lessonId}_${suffix}_$rand.tmp';
  }

  /// ✅ الحذف الآمن: الكتابة فوق محتوى الملف بالكامل ببيانات عشوائية قبل حذفه.
  ///
  /// السبب: `File.delete()` العادية تحذف فقط الإشارة (inode/entry) من نظام
  /// الملفات، لكنها لا تضمن مسح المحتوى الفعلي فوراً من تخزين الفلاش - قد
  /// تبقى البيانات قابلة للاستعادة حتى تُعاد كتابة تلك القطاعات لاحقاً.
  /// الكتابة فوق المحتوى تجعل استرجاعه عملياً غير ممكن عبر أدوات استرجاع الملفات
  /// العادية، دون الحاجة لعمليات تمسح متعددة الجولات (غير ضرورية على SSD/Flash
  /// الحديثة وتزيد فقط من تآكل التخزين على الأجهزة الضعيفة).
  static Future<void> secureDelete(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) return;

      final length = await file.length();
      if (length > 0) {
        final raf = await file.open(mode: FileMode.write);
        try {
          const int chunkSize = 256 * 1024; // 256KB لتفادي ضغط الذاكرة على أجهزة 2GB RAM
          final rand = Random.secure();
          int remaining = length;
          await raf.setPosition(0);
          while (remaining > 0) {
            final int toWrite = min(chunkSize, remaining);
            final junk = Uint8List.fromList(
                List<int>.generate(toWrite, (_) => rand.nextInt(256)));
            await raf.writeFrom(junk);
            remaining -= toWrite;
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
      }

      await file.delete();
    } catch (e) {
      // لو فشلت الكتابة فوق المحتوى (مثلاً نفاد المساحة)، نحاول الحذف العادي
      // على الأقل كخط دفاع أخير بدلاً من ترك الملف بدون أي محاولة حذف
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current,
          reason: 'secureDelete failed for $path', fatal: false);
    }
  }

  /// حذف عدة ملفات مؤقتة دفعة واحدة (يُستخدم بعد كل مرحلة تحميل/دمج/تشفير)
  static Future<void> secureDeleteAll(List<String?> paths) async {
    for (final p in paths) {
      if (p != null && p.isNotEmpty) {
        await secureDelete(p);
      }
    }
  }

  /// ✅ تنظيف الملفات اليتيمة (orphans) المتبقية من تعطل التطبيق أو إيقافه
  /// قسرياً في منتصف عملية تحميل/دمج سابقة. يُستحسن استدعاؤها مرة واحدة
  /// عند بدء تشغيل التطبيق (main.dart) قبل أي تحميل جديد.
  static Future<void> sweepOrphans() async {
    try {
      final dir = await getWorkDir();
      if (!await dir.exists()) return;

      final entries = await dir.list().toList();
      for (final entity in entries) {
        if (entity is File) {
          await secureDelete(entity.path);
        }
      }
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current,
          reason: 'sweepOrphans failed', fatal: false);
    }
  }
}
