// نماذج بيانات الاستبيان (Survey / Feedback Feature)

class SurveyQuestionModel {
  final int id;
  final String questionText;
  // mcq_single | mcq_multiple | written | rating
  final String questionType;
  final List<String> options;
  final int maxRating;
  final bool isRequired;

  SurveyQuestionModel({
    required this.id,
    required this.questionText,
    required this.questionType,
    this.options = const [],
    this.maxRating = 5,
    this.isRequired = true,
  });

  factory SurveyQuestionModel.fromJson(Map<String, dynamic> json) {
    return SurveyQuestionModel(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      questionText: json['question_text'] ?? '',
      questionType: json['question_type'] ?? 'written',
      options: json['options'] != null
          ? List<String>.from(
              (json['options'] as List).map((e) => e.toString()))
          : const [],
      maxRating: json['max_rating'] is int
          ? json['max_rating']
          : int.tryParse('${json['max_rating']}') ?? 5,
      isRequired: json['is_required'] ?? true,
    );
  }

  bool get isMcqSingle => questionType == 'mcq_single';
  bool get isMcqMultiple => questionType == 'mcq_multiple';
  bool get isWritten => questionType == 'written';
  bool get isRating => questionType == 'rating';
}

class SurveyModel {
  final int id;
  final String title;
  final String? description;
  final bool isObligatory;
  final String? startsAt;
  final String? expiresAt;
  final List<SurveyQuestionModel> questions;

  SurveyModel({
    required this.id,
    required this.title,
    this.description,
    this.isObligatory = false,
    this.startsAt,
    this.expiresAt,
    this.questions = const [],
  });

  factory SurveyModel.fromJson(Map<String, dynamic> json) {
    return SurveyModel(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      title: json['title'] ?? '',
      description: json['description'],
      isObligatory: json['is_obligatory'] ?? false,
      startsAt: json['starts_at'],
      expiresAt: json['expires_at'],
      questions: json['questions'] != null
          ? List<SurveyQuestionModel>.from((json['questions'] as List)
              .map((q) => SurveyQuestionModel.fromJson(q)))
          : const [],
    );
  }
}

// إجابة سؤال واحد يقوم المستخدم بتعبئتها محلياً قبل الإرسال
class SurveyAnswerDraft {
  final int questionId;
  String? answerText;
  List<String> selectedOptions;
  int? ratingValue;

  SurveyAnswerDraft({
    required this.questionId,
    this.answerText,
    List<String>? selectedOptions,
    this.ratingValue,
  }) : selectedOptions = selectedOptions ?? [];

  bool get isEmpty =>
      (answerText == null || answerText!.trim().isEmpty) &&
      selectedOptions.isEmpty &&
      ratingValue == null;

  Map<String, dynamic> toJson() => {
        'question_id': questionId,
        if (answerText != null) 'answer_text': answerText,
        if (selectedOptions.isNotEmpty) 'selected_options': selectedOptions,
        if (ratingValue != null) 'rating_value': ratingValue,
      };
}
