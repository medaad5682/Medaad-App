import 'package:flutter/material.dart';

import '../models/text_note_model.dart';
import '../services/pdf_annotation_store.dart';

/// يدير أداة "النص" (كتابة نص مباشرة على الصفحة): الإضافة، النقل، التعديل،
/// تغيير اللون والحجم، والحذف.
class PdfTextNoteController {
  PdfTextNoteController({
    required this.store,
    required this.onChanged,
  });

  final PdfAnnotationStore store;
  final VoidCallback onChanged;

  bool isActive = false;
  int defaultColor = 0xFFFFFFFF;
  double defaultFontSize = 0.022;
  bool defaultBold = false;
  bool defaultUnderline = false;

  final Map<int, List<TextNoteModel>> _notes = {};

  List<TextNoteModel> notesForPage(int page) => _notes[page] ?? const [];

  Future<void> ensurePageLoaded(int pageNumber) async {
    if (!_notes.containsKey(pageNumber)) {
      _notes[pageNumber] = await store.loadTextNotes(pageNumber);
    }
  }

  Future<void> _persist(int pageNumber) => store.saveTextNotes(pageNumber, _notes[pageNumber] ?? const []);

  TextNoteModel addNote(int pageNumber, Offset relativePoint) {
    final note = TextNoteModel(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: '',
      dx: relativePoint.dx,
      dy: relativePoint.dy,
      color: defaultColor,
      fontSize: defaultFontSize,
      bold: defaultBold,
      underline: defaultUnderline,
    );
    _notes.putIfAbsent(pageNumber, () => []).add(note);
    onChanged();
    return note;
  }

  Future<void> commitNote(int pageNumber, TextNoteModel note) async {
    // إذا تُرك النص فارغاً، يُحذف بدلاً من حفظه ككائن فارغ بلا فائدة.
    if (note.text.trim().isEmpty) {
      _notes[pageNumber]?.removeWhere((n) => n.id == note.id);
    }
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> moveNote(int pageNumber, TextNoteModel note, Offset deltaRelative) async {
    note.dx += deltaRelative.dx;
    note.dy += deltaRelative.dy;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateColor(int pageNumber, TextNoteModel note, int color) async {
    note.color = color;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateFontSize(int pageNumber, TextNoteModel note, double size) async {
    note.fontSize = size;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateBold(int pageNumber, TextNoteModel note, bool bold) async {
    note.bold = bold;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> updateUnderline(int pageNumber, TextNoteModel note, bool underline) async {
    note.underline = underline;
    await _persist(pageNumber);
    onChanged();
  }

  Future<void> deleteNote(int pageNumber, TextNoteModel note) async {
    _notes[pageNumber]?.removeWhere((n) => n.id == note.id);
    await _persist(pageNumber);
    onChanged();
  }
}
