import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/image_annotation_model.dart';
import '../services/pdf_annotation_store.dart';

/// يدير أداة "إدراج صورة": اختيار صورة من الجهاز، نسخها لمجلد دائم
/// (بدلاً من استخدام المسار المؤقت لـ image_picker الذي قد يُحذف)، ثم وضعها
/// على الصفحة بإمكانية تغيير الحجم، النقل، أو الحذف.
class PdfImageAnnotationController {
  PdfImageAnnotationController({
    required this.pdfId,
    required this.store,
    required this.onChanged,
  });

  final String pdfId;
  final PdfAnnotationStore store;
  final VoidCallback onChanged;

  bool isActive = false;

  final Map<int, List<ImageAnnotationModel>> _images = {};

  List<ImageAnnotationModel> imagesForPage(int page) => _images[page] ?? const [];

  Future<void> ensurePageLoaded(int pageNumber) async {
    if (!_images.containsKey(pageNumber)) {
      _images[pageNumber] = await store.loadImages(pageNumber);
    }
  }

  Future<void> _persist(int pageNumber) => store.saveImages(pageNumber, _images[pageNumber] ?? const []);

  Future<Directory> _imagesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/pdf_annotation_images/$pdfId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// يفتح معرض الصور، ينسخ الصورة المختارة لمجلد دائم، ويضيفها كأداة تعليق
  /// في منتصف الصفحة بحجم افتراضي معقول.
  Future<ImageAnnotationModel?> pickAndAddImage(int pageNumber) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return null;

    final dir = await _imagesDir();
    final ext = picked.path.split('.').last;
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$ext';
    final savedFile = await File(picked.path).copy('${dir.path}/$fileName');

    final model = ImageAnnotationModel(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      path: savedFile.path,
      dx: 0.3,
      dy: 0.3,
      width: 0.4,
      height: 0.3,
    );

    _images.putIfAbsent(pageNumber, () => []).add(model);
    await _persist(pageNumber);
    onChanged();
    return model;
  }

  Future<void> moveImage(int pageNumber, ImageAnnotationModel img, Offset deltaRelative) async {
    img.dx += deltaRelative.dx;
    img.dy += deltaRelative.dy;
    await _persist(pageNumber);
    onChanged();
  }

  /// تغيير الحجم أثناء السحب (معاينة مباشرة).
  /// [deltaRelative] هو مقدار التغيير النسبي في العرض/الارتفاع.
  Future<void> resizeImage(int pageNumber, ImageAnnotationModel img, Offset deltaRelative) async {
    img.width  = (img.width  + deltaRelative.dx).clamp(0.05, 1.0);
    img.height = (img.height + deltaRelative.dy).clamp(0.05, 1.0);
    // لا نحفظ أثناء السحب — يُحفظ فقط عند setFinalSize
  }

  /// يُستدعى مرة واحدة عند رفع الإصبع لحفظ الحجم النهائي بدقة.
  /// [finalWidth] و[finalHeight] هي القيم الحالية في النموذج كما هي بعد التعديل.
  Future<void> setFinalSize(
    int pageNumber,
    ImageAnnotationModel img,
    double finalWidth,
    double finalHeight,
  ) async {
    img.width  = finalWidth.clamp(0.05, 1.0);
    img.height = finalHeight.clamp(0.05, 1.0);
    await _persist(pageNumber);
    onChanged();
  }

  /// يُستدعى عند انتهاء تحريك الحافة (يحفظ الموضع الجديد بدقة).
  Future<void> setFinalPosition(
    int pageNumber,
    ImageAnnotationModel img,
    double finalDx,
    double finalDy,
  ) async {
    img.dx = finalDx;
    img.dy = finalDy;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> deleteImage(int pageNumber, ImageAnnotationModel img) async {
    _images[pageNumber]?.removeWhere((i) => i.id == img.id);
    await _persist(pageNumber);
    onChanged();
    // حذف الملف الفعلي من التخزين لتفادي تراكم صور غير مستخدمة
    try {
      final file = File(img.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // تجاهل أي خطأ حذف؛ ليس حرجاً لاستمرار عمل التطبيق
    }
  }
}
