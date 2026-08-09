import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/survey_service.dart';
import '../../data/models/survey_model.dart';

/// يعرض نافذة الاستبيان للمستخدم في أعلى أي شاشة (يُستدعى من MainWrapper
/// بعد التأكد من تسجيل الدخول). يتعامل تلقائياً مع:
/// - كون الاستبيان إلزامياً (عدم السماح بالإغلاق / زر الرجوع).
/// - أنواع الأسئلة الأربعة (اختيار واحد، اختيار متعدد، كتابي، تقييم نجوم).
Future<void> showSurveyDialog(BuildContext context, SurveyModel survey) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.65),
    builder: (ctx) => _SurveyDialogContent(survey: survey),
  );
}

class _SurveyDialogContent extends StatefulWidget {
  final SurveyModel survey;
  const _SurveyDialogContent({required this.survey});

  @override
  State<_SurveyDialogContent> createState() => _SurveyDialogContentState();
}

class _SurveyDialogContentState extends State<_SurveyDialogContent> {
  late final Map<int, SurveyAnswerDraft> _drafts;
  final Map<int, TextEditingController> _textControllers = {};
  bool _submitting = false;
  String? _errorText;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _drafts = {
      for (final q in widget.survey.questions) q.id: SurveyAnswerDraft(questionId: q.id),
    };
    for (final q in widget.survey.questions) {
      if (q.isWritten) _textControllers[q.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t({required String ar, required String en}) => _isArabic ? ar : en;

  bool _validate() {
    for (final q in widget.survey.questions) {
      if (!q.isRequired) continue;
      final draft = _drafts[q.id];
      if (draft == null || draft.isEmpty) return false;
    }
    return true;
  }

  Future<void> _handleSubmit() async {
    if (!_validate()) {
      setState(() {
        _errorText = _t(
          ar: 'يرجى الإجابة على جميع الأسئلة المطلوبة',
          en: 'Please answer all required questions',
        );
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final ok = await SurveyService.submitSurvey(
        surveyId: widget.survey.id,
        answers: _drafts.values.toList(),
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(ar: 'شكراً لمشاركتك رأيك معنا 🎉', en: 'Thanks for your feedback 🎉')),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _errorText = _t(ar: 'حدث خطأ، حاول مرة أخرى', en: 'Something went wrong, try again');
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = _t(ar: 'تعذر الاتصال بالخادم', en: 'Could not connect to server');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleSkip() {
    SurveyService.markSkippedThisSession(widget.survey.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? AppColors.backgroundSecondary : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF212529);
    final Color subTextColor = isDark ? Colors.white70 : const Color(0xFF6C757D);
    final bool obligatory = widget.survey.isObligatory;

    return WillPopScope(
      onWillPop: () async => !obligatory,
      child: Dialog(
        backgroundColor: cardColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.survey.title,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          if (widget.survey.description != null && widget.survey.description!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                widget.survey.description!,
                                style: TextStyle(fontSize: 13, color: subTextColor),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!obligatory)
                      IconButton(
                        icon: Icon(Icons.close, color: subTextColor),
                        onPressed: _submitting ? null : _handleSkip,
                        tooltip: _t(ar: 'تخطي', en: 'Skip'),
                      ),
                  ],
                ),
              ),
              if (obligatory)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _t(ar: 'إلزامي', en: 'Required'),
                        style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.survey.questions
                        .map((q) => _buildQuestion(q, textColor, subTextColor))
                        .toList(),
                  ),
                ),
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(_errorText!, style: TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
                          )
                        : Text(
                            _t(ar: 'إرسال', en: 'Submit'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion(SurveyQuestionModel q, Color textColor, Color subTextColor) {
    final draft = _drafts[q.id]!;

    Widget field;
    switch (q.questionType) {
      case 'mcq_single':
        field = Column(
          children: q.options.map((opt) {
            return RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.accentYellow,
              title: Text(opt, style: TextStyle(color: textColor, fontSize: 14)),
              value: opt,
              groupValue: draft.selectedOptions.isEmpty ? null : draft.selectedOptions.first,
              onChanged: (val) {
                setState(() => draft.selectedOptions = val == null ? [] : [val]);
              },
            );
          }).toList(),
        );
        break;
      case 'mcq_multiple':
        field = Column(
          children: q.options.map((opt) {
            final checked = draft.selectedOptions.contains(opt);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.accentYellow,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(opt, style: TextStyle(color: textColor, fontSize: 14)),
              value: checked,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    draft.selectedOptions.add(opt);
                  } else {
                    draft.selectedOptions.remove(opt);
                  }
                });
              },
            );
          }).toList(),
        );
        break;
      case 'rating':
        field = Row(
          children: List.generate(q.maxRating, (i) {
            final starIndex = i + 1;
            final filled = (draft.ratingValue ?? 0) >= starIndex;
            return IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: AppColors.accentYellow,
                size: 32,
              ),
              onPressed: () => setState(() => draft.ratingValue = starIndex),
            );
          }),
        );
        break;
      case 'written':
      default:
        field = TextField(
          controller: _textControllers[q.id],
          maxLines: 3,
          style: TextStyle(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: _t(ar: 'اكتب رأيك هنا...', en: 'Write your feedback...'),
            hintStyle: TextStyle(color: subTextColor),
            filled: true,
            fillColor: subTextColor.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(12),
          ),
          onChanged: (val) => draft.answerText = val,
        );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (q.isRequired)
                Text(' *', style: TextStyle(color: AppColors.error, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          field,
        ],
      ),
    );
  }
}
