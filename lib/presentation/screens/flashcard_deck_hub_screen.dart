import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/flashcard_leitner.dart';
import '../../core/services/flashcard_progress_store.dart';
import '../../data/models/flashcard_model.dart';
import '../../l10n/generated/app_localizations.dart';
import 'flashcard_study_screen.dart';
import 'flashcard_summary_screen.dart' show FlashcardScheduleCard;

enum _HubTab { newCards, review }

/// 🗂️ صفحة المجموعة: نقطة الدخول للمذاكرة (تفتح من كارت المجموعة).
///
/// - تبويبان: **جديدة** (كل بطاقة لم تُجب أبداً) و**مراجعة** (الغلط أولاً ثم المستحقة بالأقدم).
/// - التبويب الافتراضي «جديدة». التبويب الفارغ يختفي، وإن بقي تبويب واحد يختفي شريط التبويبات.
/// - إن كان التبويبان فارغين: «أنهيت المطلوب» + جدول المراجعات القادمة.
/// - زر «ذاكر المجموعة كاملة» (Study Anyway) ظاهر دائماً.
/// - عند العودة من أي جلسة تُعاد قراءة التقدم فتتحدث الأعداد.
class FlashcardDeckHubScreen extends StatefulWidget {
  final FlashcardDeckModel deck;

  const FlashcardDeckHubScreen({super.key, required this.deck});

  @override
  State<FlashcardDeckHubScreen> createState() => _FlashcardDeckHubScreenState();
}

class _FlashcardDeckHubScreenState extends State<FlashcardDeckHubScreen> {
  bool _loading = true;
  Map<int, FlashcardCardProgress> _progress = <int, FlashcardCardProgress>{};

  /// اختيار الطالب الأخير للتبويب (null = الافتراضي). يُتجاهل إن صار التبويب مخفياً.
  _HubTab? _selected;

  List<FlashcardModel> get _cards => widget.deck.cards;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    Map<int, FlashcardCardProgress> progress;
    try {
      // pruneToCards يهاجر تقدم النظام القديم ويحذف سجلات البطاقات المحذوفة
      progress = Map<int, FlashcardCardProgress>.of(
        await FlashcardProgressStore.pruneToCards(widget.deck.id, widget.deck.cardIds),
      );
    } catch (_) {
      progress = <int, FlashcardCardProgress>{};
    }
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _loading = false;
    });
  }

  Future<void> _start(FlashcardStudyMode mode) async {
    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FlashcardStudyScreen(deck: widget.deck, mode: mode),
      ),
    );
    if (!mounted) return;
    // «إنهاء» من ملخص الجلسة ⇒ نخرج من صفحة المجموعة أيضاً (شاشة المواد تحدّث الأعداد عند عودتها)
    if (finished == true) {
      Navigator.of(context).pop();
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppColors.flashcardAccent))
                  : _cards.isEmpty
                      ? _buildEmpty()
                      : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.flashcardClose,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              widget.deck.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          AppLocalizations.of(context)!.flashcardNoCards,
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l = AppLocalizations.of(context)!;
    final today = FlashcardLeitner.today();

    final newCount = FlashcardLeitner.countNew(cards: _cards, progress: _progress);
    final reviewCount =
        FlashcardLeitner.countReview(cards: _cards, progress: _progress, today: today);

    final visible = <_HubTab>[
      if (newCount > 0) _HubTab.newCards,
      if (reviewCount > 0) _HubTab.review,
    ];
    final _HubTab? current =
        visible.isEmpty ? null : (visible.contains(_selected) ? _selected : visible.first);

    Widget content;
    if (current == _HubTab.newCards) {
      content = _TabPanel(
        icon: LucideIcons.layers,
        count: newCount,
        title: l.flashcardTabNew,
        hint: l.flashcardNewTabHint,
        buttonLabel: l.flashcardStudy,
        onStart: () => _start(FlashcardStudyMode.newCards),
      );
    } else if (current == _HubTab.review) {
      final b = FlashcardLeitner.reviewBreakdown(
        cards: _cards,
        progress: _progress,
        today: today,
      );
      content = _TabPanel(
        icon: LucideIcons.rotateCcw,
        count: reviewCount,
        title: l.flashcardTabReview,
        hint: l.flashcardReviewTabHint,
        buttonLabel: l.flashcardStudy,
        onStart: () => _start(FlashcardStudyMode.review),
        extra: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (b.wrong > 0)
              _MiniChip(label: l.flashcardBreakdownWrong(b.wrong), color: AppColors.error),
            if (b.overdue > 0)
              _MiniChip(label: l.flashcardBreakdownOverdue(b.overdue), color: AppColors.accentYellow),
            if (b.dueToday > 0)
              _MiniChip(label: l.flashcardBreakdownToday(b.dueToday), color: AppColors.flashcardAccent),
          ],
        ),
      );
    } else {
      content = _buildAllDone(today);
    }

    return Column(
      children: [
        if (visible.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: '${l.flashcardTabNew} ($newCount)',
                    selected: current == _HubTab.newCards,
                    onTap: () => setState(() => _selected = _HubTab.newCards),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TabButton(
                    label: '${l.flashcardTabReview} ($reviewCount)',
                    selected: current == _HubTab.review,
                    onTap: () => setState(() => _selected = _HubTab.review),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: content,
          ),
        ),
        _buildStudyAnyway(),
      ],
    );
  }

  Widget _buildAllDone(DateTime today) {
    final l = AppLocalizations.of(context)!;
    final schedule = FlashcardLeitner.upcomingSchedule(_progress.values, today);
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.trophy, size: 40, color: AppColors.success),
        ),
        const SizedBox(height: 20),
        Text(
          l.flashcardAllKnownTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.flashcardAllKnownMessage,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
        ),
        if (schedule.isNotEmpty) ...[
          const SizedBox(height: 24),
          FlashcardScheduleCard(schedule: schedule),
        ],
      ],
    );
  }

  /// «ذاكر المجموعة كاملة» — ظاهر دائماً.
  Widget _buildStudyAnyway() {
    final l = AppLocalizations.of(context)!;
    final accent = AppColors.flashcardAccent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.flashcardStudyAnywayHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _start(FlashcardStudyMode.studyAnyway),
              icon: const Icon(LucideIcons.refreshCcw, size: 18),
              label: Text(
                l.flashcardStudyAnyway,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withOpacity(0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? accent : accent.withOpacity(0.35)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: selected ? AppColors.onFlashcardAccent : accent,
          ),
        ),
      ),
    );
  }
}

/// محتوى تبويب: العدد الكبير + وصف + (تفصيل اختياري) + زر البدء.
class _TabPanel extends StatelessWidget {
  final IconData icon;
  final int count;
  final String title;
  final String hint;
  final String buttonLabel;
  final VoidCallback onStart;
  final Widget? extra;

  const _TabPanel({
    required this.icon,
    required this.count,
    required this.title,
    required this.hint,
    required this.buttonLabel,
    required this.onStart,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.flashcardAccent;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 40, color: accent),
        ),
        const SizedBox(height: 20),
        Text(
          '$count',
          style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: accent),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
        ),
        if (extra != null) ...[
          const SizedBox(height: 16),
          extra!,
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onStart,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: accent,
              foregroundColor: AppColors.onFlashcardAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
