import '../models/drawing_model.dart';
import '../models/comment_model.dart';
import '../models/highlight_model.dart';
import '../models/text_note_model.dart';
import '../models/shape_model.dart';
import '../models/image_annotation_model.dart';
import '../models/pdf_tool_settings.dart';
import 'storage_service.dart';

/// مسؤول عن حفظ واسترجاع كل أنواع التعليقات والرسومات الخاصة بملف PDF معين،
/// بالإضافة إلى الإعدادات العامة للأدوات (المحفوظة بين كل الملفات).
class PdfAnnotationStore {
  static const String _drawingsBox = 'pdf_drawings_db';
  static const String _settingsBox = 'pdf_tool_settings_db';
  static const String _settingsKey = 'global_settings';

  final String pdfId;
  PdfAnnotationStore(this.pdfId);

  String _k(String suffix, [int? page]) =>
      page != null ? '${pdfId}_${page}_$suffix' : '${pdfId}_$suffix';

  // ------------------------- إعدادات الأدوات العامة -------------------------

  static Future<PdfToolSettings> loadGlobalSettings() async {
    final box = await StorageService.openBox(_settingsBox);
    final data = box.get(_settingsKey);
    if (data == null) return PdfToolSettings();
    try {
      return PdfToolSettings.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return PdfToolSettings();
    }
  }

  static Future<void> saveGlobalSettings(PdfToolSettings settings) async {
    final box = await StorageService.openBox(_settingsBox);
    await box.put(_settingsKey, settings.toJson());
  }

  // ------------------------------ الرسومات (القلم) ------------------------------

  Future<List<DrawingLine>> loadDrawings(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('drawings', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => DrawingLine.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveDrawings(int page, List<DrawingLine> lines) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (lines.isEmpty) {
      await box.delete(_k('drawings', page));
    } else {
      await box.put(_k('drawings', page), lines.map((l) => l.toJson()).toList());
    }
  }

  // ------------------------------ الملاحظات (Comments) ------------------------------

  Future<List<CommentModel>> loadComments(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('comments', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => CommentModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveComments(int page, List<CommentModel> comments) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (comments.isEmpty) {
      await box.delete(_k('comments', page));
    } else {
      await box.put(_k('comments', page), comments.map((c) => c.toJson()).toList());
    }
  }

  static Future<CommentDefaults> loadCommentDefaults() async {
    final box = await StorageService.openBox(_settingsBox);
    final data = box.get('comment_defaults');
    if (data == null) return CommentDefaults();
    return CommentDefaults.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<void> saveCommentDefaults(CommentDefaults d) async {
    final box = await StorageService.openBox(_settingsBox);
    await box.put('comment_defaults', d.toJson());
  }

  // ------------------------------ التمييز (Highlights) ------------------------------

  Future<List<HighlightModel>> loadHighlights(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('highlights', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => HighlightModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveHighlights(int page, List<HighlightModel> items) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (items.isEmpty) {
      await box.delete(_k('highlights', page));
    } else {
      await box.put(_k('highlights', page), items.map((h) => h.toJson()).toList());
    }
  }

  // ------------------------------ التسطير (Underlines) ------------------------------

  Future<List<UnderlineModel>> loadUnderlines(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('underlines', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => UnderlineModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveUnderlines(int page, List<UnderlineModel> items) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (items.isEmpty) {
      await box.delete(_k('underlines', page));
    } else {
      await box.put(_k('underlines', page), items.map((u) => u.toJson()).toList());
    }
  }

  // ------------------------------ النصوص (TextNotes) ------------------------------

  Future<List<TextNoteModel>> loadTextNotes(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('texts', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => TextNoteModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveTextNotes(int page, List<TextNoteModel> items) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (items.isEmpty) {
      await box.delete(_k('texts', page));
    } else {
      await box.put(_k('texts', page), items.map((t) => t.toJson()).toList());
    }
  }

  // ------------------------------ الأشكال (Shapes) ------------------------------

  Future<List<ShapeModel>> loadShapes(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('shapes', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => ShapeModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveShapes(int page, List<ShapeModel> items) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (items.isEmpty) {
      await box.delete(_k('shapes', page));
    } else {
      await box.put(_k('shapes', page), items.map((s) => s.toJson()).toList());
    }
  }

  // ------------------------------ الصور (Images) ------------------------------

  Future<List<ImageAnnotationModel>> loadImages(int page) async {
    final box = await StorageService.openBox(_drawingsBox);
    final data = box.get(_k('images', page));
    if (data == null) return [];
    return (data as List<dynamic>)
        .map((e) => ImageAnnotationModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveImages(int page, List<ImageAnnotationModel> items) async {
    final box = await StorageService.openBox(_drawingsBox);
    if (items.isEmpty) {
      await box.delete(_k('images', page));
    } else {
      await box.put(_k('images', page), items.map((i) => i.toJson()).toList());
    }
  }
}
