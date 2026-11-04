// نماذج بيانات الفلاش كاردس (Step 12)
//
// - FlashcardDeckSummary: ما يرجعه get-subject-content داخل flashcard_decks (قائمة المجموعات في تبويب الامتحانات).
// - FlashcardDeckModel + FlashcardModel: ما يرجعه /api/flashcards/get-deck (المجموعة مع بطاقاتها).
// - toJson موجودة لأن المجموعة تُخزَّن في Hive للدراسة بدون إنترنت.

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

String? _toNullableString(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

class FlashcardModel {
  final int id;
  final String? frontText;
  final String? backText;
  final String? frontImageFileId;
  final String? backImageFileId;
  final int sortOrder;

  const FlashcardModel({
    required this.id,
    this.frontText,
    this.backText,
    this.frontImageFileId,
    this.backImageFileId,
    this.sortOrder = 0,
  });

  factory FlashcardModel.fromJson(Map<String, dynamic> json) {
    return FlashcardModel(
      id: _toInt(json['id']),
      frontText: _toNullableString(json['front_text']),
      backText: _toNullableString(json['back_text']),
      frontImageFileId: _toNullableString(json['front_image_file_id']),
      backImageFileId: _toNullableString(json['back_image_file_id']),
      sortOrder: _toInt(json['sort_order']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'front_text': frontText,
        'back_text': backText,
        'front_image_file_id': frontImageFileId,
        'back_image_file_id': backImageFileId,
        'sort_order': sortOrder,
      };

  bool get hasFrontImage => frontImageFileId != null;
  bool get hasBackImage => backImageFileId != null;
}

class FlashcardDeckModel {
  final int id;
  final int subjectId;
  final String title;
  final String? description;

  /// ISO timestamp من السيرفر — يُستخدم لمعرفة هل نسخة الكاش قديمة.
  final String? updatedAt;

  /// يرجع فقط للمعلم المالك (null للطلاب).
  final bool? isActive;
  final List<FlashcardModel> cards;

  const FlashcardDeckModel({
    required this.id,
    required this.subjectId,
    required this.title,
    this.description,
    this.updatedAt,
    this.isActive,
    this.cards = const [],
  });

  factory FlashcardDeckModel.fromJson(Map<String, dynamic> json) {
    final rawCards = json['cards'];
    final cards = <FlashcardModel>[];
    if (rawCards is List) {
      for (final c in rawCards) {
        if (c is Map) cards.add(FlashcardModel.fromJson(Map<String, dynamic>.from(c)));
      }
    }
    // الترتيب يأتي مرتباً من السيرفر؛ نعيد الترتيب احتياطاً (ثابت بالـ id عند التساوي)
    cards.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return FlashcardDeckModel(
      id: _toInt(json['id']),
      subjectId: _toInt(json['subject_id']),
      title: (json['title'] ?? '').toString(),
      description: _toNullableString(json['description']),
      updatedAt: _toNullableString(json['updated_at']),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : null,
      cards: cards,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_id': subjectId,
        'title': title,
        'description': description,
        'updated_at': updatedAt,
        if (isActive != null) 'is_active': isActive,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  List<int> get cardIds => cards.map((c) => c.id).toList();
}

/// عنصر قائمة المجموعات داخل get-subject-content (بدون البطاقات).
class FlashcardDeckSummary {
  final int id;
  final String title;
  final String? description;
  final int sortOrder;
  final int cardCount;
  final String? updatedAt;

  /// true للطلاب دائماً (المخفية لا تصلهم)؛ للمعلم المالك قد تكون false ⇒ شارة «مخفية».
  final bool isActive;

  const FlashcardDeckSummary({
    required this.id,
    required this.title,
    this.description,
    this.sortOrder = 0,
    this.cardCount = 0,
    this.updatedAt,
    this.isActive = true,
  });

  factory FlashcardDeckSummary.fromJson(Map<String, dynamic> json) {
    return FlashcardDeckSummary(
      id: _toInt(json['id']),
      title: (json['title'] ?? '').toString(),
      description: _toNullableString(json['description']),
      sortOrder: _toInt(json['sort_order']),
      cardCount: _toInt(json['card_count']),
      updatedAt: _toNullableString(json['updated_at']),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
    );
  }

  /// يحوّل حقل flashcard_decks من استجابة المادة (قد يكون null عند سيرفر قديم).
  static List<FlashcardDeckSummary> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => FlashcardDeckSummary.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}
