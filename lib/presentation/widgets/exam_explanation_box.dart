import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';

/// صندوق "الشرح" لأسئلة الاختيار من متعدد.
/// بنفس شكل صندوق الإجابة النموذجية للأسئلة المقالية.
/// لا يرسم شيئاً إذا كان النص فارغاً/null.
class ExamExplanationBox extends StatelessWidget {
  final String? text;

  const ExamExplanationBox({Key? key, required this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String value = (text ?? '').trim();
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.success, size: 14),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.explanationLabel,
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
