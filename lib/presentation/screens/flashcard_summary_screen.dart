import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';

/// 📊 ملخص نهاية الجولة (Step 15).
///
/// يُعرض داخل شاشة المذاكرة (ليس صفحة منفصلة) كي تبقى الجولات المتتالية في نفس الجلسة:
///  - «كرر التي لم أعرفها» ⇒ جولة جديدة بالبطاقات غير المعروفة فقط.
///  - «ابدأ من جديد» ⇒ تصفير التقدم وجولة بكل البطاقات.
///  - «إنهاء» ⇒ إغلاق شاشة المذاكرة (التقدم محفوظ محلياً).
///
/// الأرقام: [roundKnown]/[roundLearning] لهذه الجولة، و[totalKnown]/[totalCards] للمجموعة كاملة.
class FlashcardRoundSummary extends StatelessWidget {
  final int round;
  final int roundKnown;
  final int roundLearning;
  final int totalKnown;
  final int totalCards;

  /// null ⇒ لا يوجد ما يُكرَّر (أتقن الطالب كل بطاقات هذه الجولة).
  final VoidCallback? onRepeatUnknown;
  final VoidCallback onStartOver;
  final VoidCallback onFinish;

  const FlashcardRoundSummary({
    super.key,
    required this.round,
    required this.roundKnown,
    required this.roundLearning,
    required this.totalKnown,
    required this.totalCards,
    required this.onRepeatUnknown,
    required this.onStartOver,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    final allKnown = totalCards > 0 && totalKnown >= totalCards;
    final roundTotal = roundKnown + roundLearning;
    final ratio = roundTotal == 0 ? 0.0 : roundKnown / roundTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: (allKnown ? AppColors.success : accent).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              allKnown ? LucideIcons.trophy : LucideIcons.layers,
              size: 40,
              color: allKnown ? AppColors.success : accent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            allKnown ? AppLocalizations.of(context)!.flashcardAllKnownTitle : AppLocalizations.of(context)!.flashcardRoundDoneTitle(round),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            allKnown ? AppLocalizations.of(context)!.flashcardAllKnownMessage : AppLocalizations.of(context)!.flashcardRoundDoneMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // أرقام هذه الجولة
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: roundKnown,
                  label: AppLocalizations.of(context)!.flashcardStatKnown,
                  color: AppColors.success,
                  icon: LucideIcons.check,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  value: roundLearning,
                  label: AppLocalizations.of(context)!.flashcardStatLearning,
                  color: AppColors.error,
                  icon: LucideIcons.rotateCcw,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: AppColors.success,
              backgroundColor: AppColors.flashcardTrack,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context)!.flashcardOverallProgress(totalKnown, totalCards),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),

          if (onRepeatUnknown != null)
            _ActionButton(
              label: AppLocalizations.of(context)!.flashcardRepeatUnknown(roundLearning),
              icon: LucideIcons.rotateCcw,
              filled: true,
              onPressed: onRepeatUnknown!,
            ),
          if (onRepeatUnknown != null) const SizedBox(height: 10),
          _ActionButton(
            label: AppLocalizations.of(context)!.flashcardStartOver,
            icon: LucideIcons.refreshCcw,
            filled: onRepeatUnknown == null,
            onPressed: onStartOver,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onFinish,
            style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
            child: Text(
              AppLocalizations.of(context)!.flashcardFinish,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final IconData icon;

  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: filled
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: accent,
                foregroundColor: AppColors.onFlashcardAccent,
                shape: shape,
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withOpacity(0.6)),
                shape: shape,
              ),
              child: child,
            ),
    );
  }
}
