import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../core/services/flashcard_leitner.dart';
import '../../core/services/flashcard_progress_store.dart';
import '../../core/services/flashcard_service.dart';
import '../../data/models/flashcard_model.dart';
import 'directional_icon.dart';

/// نص عدد البطاقات (مفرد/جمع) من ملفات الترجمة.
String flashcardCountLabel(AppLocalizations l, int n) =>
    n == 1 ? l.flashcardsCountOne : l.flashcardsCountMany(n);

/// رسالة الخطأ المناسبة لسبب فشل تحميل المجموعة.
String flashcardErrorMessage(AppLocalizations l, FlashcardFailure f) {
  switch (f) {
    case FlashcardFailure.offline:
      return l.flashcardErrorOffline;
    case FlashcardFailure.expired:
      return l.flashcardErrorExpired;
    case FlashcardFailure.notOwned:
      return l.flashcardErrorNotOwned;
    case FlashcardFailure.notFound:
      return l.flashcardErrorNotFound;
    case FlashcardFailure.unauthorized:
      return l.flashcardErrorUnauthorized;
    case FlashcardFailure.server:
      return l.flashcardErrorServer;
  }
}

/// عنوان فاصل قسم الفلاش كاردس أسفل بطاقات الامتحانات (مصغّر).
class FlashcardSectionDivider extends StatelessWidget {
  const FlashcardSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: accent.withOpacity(0.3), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              AppLocalizations.of(context)!.flashcardsSectionTitle,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
          Expanded(child: Divider(color: accent.withOpacity(0.3), thickness: 1)),
        ],
      ),
    );
  }
}

/// بطاقة مجموعة فلاش كاردس (مصغّرة): العنوان وعدد البطاقات والمتقنة، شريط تقدم رفيع،
/// ثم صف واحد: شارة «N مستحقة اليوم» (أو «أنهيت كل المستحق ✓ المراجعة التالية …») بجانب زر المذاكرة.
///
/// Step 19 (لايتنر):
///  - الشارة البنفسجية «N مستحقة اليوم» بجانب الزر، والزر «مذاكرة المستحقة» حين يوجد مستحق.
///  - لا مستحق ⇒ «أنهيت كل المستحق ✓» + «المراجعة التالية غداً / بعد 3 أيام»، والزر «مراجعة» (دراسة المجموعة كاملة).
///  - شريط التقدم = المتقنة (الصندوق 4 أو 5) من العدد الكلي.
///
/// العدد الكلي من السيرفر ([FlashcardDeckSummary.cardCount]) والتقدم من Hive ([FlashcardProgressStore]).
/// غيّر [refreshToken] لإعادة قراءة التقدم (مثلاً بعد العودة من شاشة المذاكرة).
class FlashcardDeckCard extends StatefulWidget {
  final FlashcardDeckSummary deck;
  final int refreshToken;
  final bool isLoading;
  final VoidCallback onStudy;

  const FlashcardDeckCard({
    super.key,
    required this.deck,
    required this.onStudy,
    this.refreshToken = 0,
    this.isLoading = false,
  });

  @override
  State<FlashcardDeckCard> createState() => _FlashcardDeckCardState();
}

class _FlashcardDeckCardState extends State<FlashcardDeckCard> {
  FlashcardDeckStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  @override
  void didUpdateWidget(covariant FlashcardDeckCard old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken ||
        old.deck.id != widget.deck.id ||
        old.deck.cardCount != widget.deck.cardCount ||
        old.deck.updatedAt != widget.deck.updatedAt) {
      _loadProgress();
    }
  }

  Future<void> _loadProgress() async {
    try {
      final deck = widget.deck;
      // إن توفرت نسخة مخزّنة محدّثة نعرف معرّفات البطاقات فنستبعد بدقة سجلات المحذوف
      List<int>? validIds;
      final cached = await FlashcardService.getCachedDeck(deck.id);
      if (cached != null && deck.updatedAt != null && cached.updatedAt == deck.updatedAt) {
        validIds = cached.cardIds;
      }
      final stats = await FlashcardProgressStore.deckStats(
        deck.id,
        deck.cardCount,
        validCardIds: validIds,
      );
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // تعذّر قراءة التقدم مؤقتاً: نبقي القيمة الحالية بدل كسر القائمة
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(AppLocalizations.of(context)!.flashcardResetTitle,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(AppLocalizations.of(context)!.flashcardResetMessage,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.cancel,
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.flashcardReset,
                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FlashcardProgressStore.resetDeck(widget.deck.id);
      await _loadProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final deck = widget.deck;
    final accent = AppColors.flashcardAccent;
    final total = deck.cardCount;
    final hasCards = total > 0;

    // قبل اكتمال القراءة: كل البطاقات تُعدّ مستحقة (جديدة) — الشاشة نفسها تتصرف بالصواب عند الفتح
    final stats = _stats;
    final due = stats?.due ?? total;
    final mastered = stats?.mastered ?? 0;
    final hasProgress = stats?.hasProgress ?? false;
    final allMastered = hasCards && mastered >= total;
    final progress = hasCards ? (mastered / total).clamp(0.0, 1.0) : 0.0;
    final caughtUp = hasCards && stats != null && due == 0;
    final nextDays = stats?.nextReviewInDays;

    final String buttonLabel = caughtUp ? l.flashcardReview : l.flashcardStudyDue;

    return Opacity(
      // المخفية (تظهر للمعلم فقط) أخفت قليلاً
      opacity: deck.isActive ? 1.0 : 0.75,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.35), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان + العدد + (مخفية) + إعادة الضبط
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.flashcardAccentSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withOpacity(0.5)),
                  ),
                  child: Icon(LucideIcons.layers, color: accent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              hasCards
                                  ? '${flashcardCountLabel(l, total)} · ${l.flashcardMasteredCount(mastered)}'
                                  : l.flashcardNoCards,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (!deck.isActive) ...[
                            const SizedBox(width: 8),
                            Icon(LucideIcons.eyeOff, size: 11, color: AppColors.accentYellow),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                l.flashcardHidden,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentYellow,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasProgress)
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: l.flashcardResetTooltip,
                      icon: Icon(LucideIcons.refreshCcw, size: 15, color: AppColors.textSecondary),
                      onPressed: widget.isLoading ? null : _confirmReset,
                    ),
                  ),
              ],
            ),

            // شريط التقدم (المتقنة) رفيع
            if (hasCards) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: allMastered ? AppColors.success : accent,
                  backgroundColor: AppColors.flashcardTrack,
                ),
              ),
            ],

            // صف الحالة + الزر
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: hasCards
                      ? (caughtUp
                          ? _CaughtUpStatus(nextDays: nextDays)
                          : Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: _DueBadge(label: l.flashcardDueToday(due)),
                            ))
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: (hasCards && !widget.isLoading) ? widget.onStudy : null,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: accent,
                      foregroundColor: AppColors.onFlashcardAccent,
                      disabledBackgroundColor: AppColors.flashcardTrack,
                      disabledForegroundColor: AppColors.textSecondary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.onFlashcardAccent,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(buttonLabel,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 4),
                              DirectionalFlip(
                                child: const Icon(LucideIcons.chevronRight, size: 15),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// الشارة البنفسجية «N مستحقة اليوم».
class _DueBadge extends StatelessWidget {
  final String label;
  const _DueBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.flashcardAccentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
      ),
    );
  }
}

/// «أنهيت كل المستحق ✓» + «المراجعة التالية غداً / بعد 3 أيام».
class _CaughtUpStatus extends StatelessWidget {
  final int? nextDays;
  const _CaughtUpStatus({required this.nextDays});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.flashcardAllCaughtUp,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.success),
        ),
        if (nextDays != null)
          Text(
            l.flashcardNextReviewIn(nextDays!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
