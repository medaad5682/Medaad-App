import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/flashcard_progress_store.dart';
import '../../core/services/flashcard_service.dart';
import '../../data/models/flashcard_model.dart';
import 'directional_icon.dart';

/// نصوص الفلاش كاردس (عربي/إنجليزي).
/// ملاحظة: مؤقتة هنا وتُنقل إلى ملفات ARB (app_ar/app_en) في Step 16.
class FlashcardStrings {
  FlashcardStrings._();
  static bool get _ar => AppState.isArabic;

  static String get sectionTitle => _ar ? '🗂️ بطاقات الفلاش' : '🗂️ Flashcards';
  static String cardsCount(int n) {
    if (_ar) return n == 1 ? 'بطاقة واحدة' : '$n بطاقة';
    return n == 1 ? '1 card' : '$n cards';
  }

  static String get noCards => _ar ? 'لا توجد بطاقات بعد' : 'No cards yet';
  static String get study => _ar ? 'ابدأ المذاكرة' : 'Study';
  static String get continueStudy => _ar ? 'متابعة' : 'Continue';
  static String get review => _ar ? 'مراجعة' : 'Review';
  static String get hidden => _ar ? 'مخفية عن الطلاب' : 'Hidden from students';
  static String get resetTooltip => _ar ? 'إعادة ضبط التقدم' : 'Reset progress';
  static String get resetTitle => _ar ? 'إعادة ضبط التقدم' : 'Reset progress';
  static String get resetMessage => _ar
      ? 'سيتم مسح تقدمك في هذه المجموعة على هذا الجهاز فقط. هل تريد المتابعة؟'
      : 'Your progress in this deck will be cleared on this device only. Continue?';
  static String get cancel => _ar ? 'إلغاء' : 'Cancel';
  static String get reset => _ar ? 'إعادة ضبط' : 'Reset';

  static String errorFor(FlashcardFailure f) {
    switch (f) {
      case FlashcardFailure.offline:
        return _ar
            ? 'لا يوجد اتصال بالإنترنت ولم تُحفظ هذه المجموعة على جهازك بعد.'
            : 'No internet connection and this deck is not saved on your device yet.';
      case FlashcardFailure.expired:
        return _ar ? 'انتهت صلاحية اشتراكك في هذه المادة.' : 'Your access to this subject has expired.';
      case FlashcardFailure.notOwned:
        return _ar ? 'لا تملك اشتراكاً في هذه المادة.' : "You don't have access to this subject.";
      case FlashcardFailure.notFound:
        return _ar ? 'هذه المجموعة لم تعد متاحة.' : 'This deck is no longer available.';
      case FlashcardFailure.unauthorized:
        return _ar ? 'انتهت الجلسة، أعد تسجيل الدخول.' : 'Session expired, please sign in again.';
      case FlashcardFailure.server:
        return _ar ? 'تعذّر تحميل المجموعة، حاول مجدداً.' : 'Could not load the deck, please try again.';
    }
  }

  static String loadedTemp(int n) =>
      _ar ? 'تم تحميل $n بطاقة' : 'Loaded $n cards';
}

/// عنوان فاصل قسم الفلاش كاردس أسفل بطاقات الامتحانات.
class FlashcardSectionDivider extends StatelessWidget {
  const FlashcardSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: accent.withOpacity(0.35), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              FlashcardStrings.sectionTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
          Expanded(child: Divider(color: accent.withOpacity(0.35), thickness: 1)),
        ],
      ),
    );
  }
}

/// بطاقة مجموعة فلاش كاردس: العنوان، عدد البطاقات، شريط التقدم المحلي، وزر «ابدأ/متابعة/مراجعة».
///
/// التقدم يُحسب هنا: العدد الكلي من السيرفر ([FlashcardDeckSummary.cardCount])
/// والمعروف من Hive ([FlashcardProgressStore]). غيّر [refreshToken] لإعادة قراءة التقدم
/// (مثلاً بعد العودة من شاشة المذاكرة).
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
  int _known = 0;

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
      final n = await FlashcardProgressStore.knownCount(widget.deck.id, widget.deck.cardCount);
      if (mounted && n != _known) setState(() => _known = n);
    } catch (_) {
      // تعذّر قراءة التقدم مؤقتاً: نبقي القيمة الحالية بدل كسر القائمة
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(FlashcardStrings.resetTitle,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(FlashcardStrings.resetMessage,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(FlashcardStrings.cancel,
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(FlashcardStrings.reset,
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
    final deck = widget.deck;
    final accent = AppColors.flashcardAccent;
    final total = deck.cardCount;
    final hasCards = total > 0;
    final known = _known;
    final done = hasCards && known >= total;
    final progress = hasCards ? (known / total).clamp(0.0, 1.0) : 0.0;

    final String buttonLabel = done
        ? FlashcardStrings.review
        : (known > 0 ? FlashcardStrings.continueStudy : FlashcardStrings.study);

    return Opacity(
      // المخفية (تظهر للمعلم فقط) أخفت قليلاً
      opacity: deck.isActive ? 1.0 : 0.75,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withOpacity(0.35), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.flashcardAccentSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withOpacity(0.5)),
                  ),
                  child: Icon(LucideIcons.layers, color: accent, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCards ? FlashcardStrings.cardsCount(total) : FlashcardStrings.noCards,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (known > 0)
                  IconButton(
                    tooltip: FlashcardStrings.resetTooltip,
                    icon: Icon(LucideIcons.refreshCcw, size: 18, color: AppColors.textSecondary),
                    onPressed: widget.isLoading ? null : _confirmReset,
                  ),
              ],
            ),

            if (!deck.isActive) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accentYellow.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.eyeOff, size: 13, color: AppColors.accentYellow),
                    const SizedBox(width: 6),
                    Text(
                      FlashcardStrings.hidden,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentYellow,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (hasCards) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: done ? AppColors.success : accent,
                        backgroundColor: AppColors.flashcardTrack,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$known/$total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: done ? AppColors.success : accent,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: (hasCards && !widget.isLoading) ? widget.onStudy : null,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: accent,
                  foregroundColor: AppColors.onFlashcardAccent,
                  disabledBackgroundColor: AppColors.flashcardTrack,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.onFlashcardAccent,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(buttonLabel,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(width: 6),
                          DirectionalFlip(
                            child: const Icon(LucideIcons.chevronRight, size: 18),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
