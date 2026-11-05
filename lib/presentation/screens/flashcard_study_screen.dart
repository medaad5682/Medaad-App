import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/attestation_service.dart';
import '../../core/services/flashcard_leitner.dart';
import '../../core/services/flashcard_progress_store.dart';
import '../../core/services/storage_service.dart';
import '../../data/models/flashcard_model.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/flashcard_flip_card.dart';
import 'flashcard_summary_screen.dart';
import 'screen_protect_wrapper.dart';

/// 🃏 شاشة مذاكرة الفلاش كاردس (جلسة واحدة بوضع محدد).
///
/// تُفتح من صفحة المجموعة ([FlashcardStudyMode]) أو مباشرة من قائمة كارت المجموعة:
/// - `newCards`: كل البطاقات التي بلا سجل بترتيب المجموعة (بلا حد).
/// - `review`: الغلط (الصندوق 1) أولاً ثم المستحقة بالأقدم موعداً (بلا حد).
/// - `repeatWrong`: كل بطاقات الصندوق 1 في المجموعة، وتتكرر الجولات حتى لا يبقى غلط.
/// - `studyAnyway`: المجموعة كاملة بترتيبها. «عرفتها» لا ترفع أي بطاقة في الصندوق 2 فما فوق،
///   وتنقل الجديدة/الغلط إلى الصندوق 2 (غداً). «ما زلت أتعلم» تنزل أي بطاقة للصندوق 1.
///
/// القواعد العامة (لايتنر):
/// - «عرفتها» ⇒ صندوق + 1 (مرة واحدة) وموعد من تاريخ المراجعة الفعلي (حتى المتأخرة تترقى عادي).
/// - «ما زلت أتعلم» ⇒ الصندوق 1 (= غلط) وموعدها اليوم.
/// - الغلط مشتق من الصندوق مباشرة؛ لا توجد قائمة «معلّقة» منفصلة.
/// - نهاية الجولة ⇒ [FlashcardRoundSummary] بـ«كرر الغلط» (لو يوجد غلط في المجموعة)
///   و«ابدأ مراجعة المستحقة» (فقط لجلسة بدأت بالجديدة ويوجد مستحق غير الغلط).
///
/// ما قبله:
/// - بطاقة قابلة للقلب؛ أزرار «عرفتها» / «ما زلت أتعلم» تظهر **بعد القلب فقط** وهي التحكم الأساسي.
/// - السحب (يمين=عرفتها، يسار=ما زلت أتعلم) اختصار اختياري يعمل بعد القلب.
/// - تلميح السحب يظهر مرة واحدة فقط (يُحفظ محلياً) عند أول قلب لأول بطاقة.
/// - الرأس: شريط تقدم وعداد، وزر خلط يعيد ترتيب البطاقات المتبقية فوراً عند كل ضغطة.
/// - كل تقييم يُحفظ فوراً في Hive، فالخروج في منتصف الجلسة لا يضيّع شيئاً.
/// - محمية بنفس طبقة الحماية المستخدمة في بقية الشاشات الحساسة ([ScreenProtectWrapper]).
class FlashcardStudyScreen extends StatefulWidget {
  final FlashcardDeckModel deck;
  final FlashcardStudyMode mode;

  const FlashcardStudyScreen({super.key, required this.deck, required this.mode});

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  // نفس نمط شاشة الامتحان لجلب الصور المحمية
  final String _baseUrl = ApiConstants.baseUrl;
  final String _appSecret = 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only';

  bool _ready = false;
  Map<String, String> _imageHeaders = const {};

  // التقدم المحلي (Step 19): سجل لكل بطاقة {box, dueDate}. البطاقة الغائبة = جديدة (الصندوق 1، مستحقة).
  Map<int, FlashcardCardProgress> _progress = <int, FlashcardCardProgress>{};
  Future<void> _saveChain = Future<void>.value(); // يسلسل الكتابات لتفادي سباق القراءة/الكتابة

  // الجولة الحالية
  List<FlashcardModel> _queue = [];
  int _index = 0;
  int _round = 1;
  final List<int> _roundKnownIds = [];
  final List<int> _roundLearningIds = [];
  bool _showSummary = false;

  // وضع الجلسة الحالي (قد يتغير داخل نفس الشاشة: جديدة ← كرر الغلط ← مراجعة)
  late FlashcardStudyMode _mode;

  /// true ⇒ بدأت هذه السلسلة من «الكروت الجديدة»، فيبقى زر «ابدأ مراجعة المستحقة»
  /// متاحاً في الملخص حتى بعد جولات «كرر الغلط».
  bool _startedFromNew = false;

  /// تلميح «المراجعة التالية بعد N يوم» الذي يظهر تحت البطاقة بعد «عرفتها».
  int? _nextReviewDays;
  int _nextReviewSeq = 0;
  Timer? _nextReviewTimer;

  // حالة البطاقة الحالية
  GlobalKey<FlashcardFlipCardState> _cardKey = GlobalKey<FlashcardFlipCardState>();
  bool _flipped = false;
  bool _rating = false; // يمنع النقر المزدوج أثناء خروج البطاقة

  bool _hintSeen = true; // true افتراضياً حتى نقرأ القيمة الفعلية
  final math.Random _random = math.Random();

  List<FlashcardModel> get _cards => widget.deck.cards;
  DateTime get _today => FlashcardLeitner.today();
  /// عدد البطاقات التي أجاب عنها الطالب «عرفتها» ولم تعد غلطاً (الصندوق 2 فما فوق).
  /// كان يُعدّ الصندوق 3+ فقط، فكانت أول جلسة تعرض 0 دائماً لأن «عرفتها» الأولى تنقل البطاقة للصندوق 2.
  int get _knownCount => math.min(
        _progress.values.where((p) => !FlashcardLeitner.isWrongBox(p.box)).length,
        _cards.length,
      );

  @override
  void dispose() {
    _nextReviewTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _init();
  }

  Future<void> _init() async {
    try {
      final box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');
      // getHeaders() لا ترمي أبداً (تعود بخريطة فارغة عند الفشل)
      final attestation = await AttestationService.instance.getHeaders();
      _imageHeaders = {
        'Authorization': 'Bearer $token',
        'x-device-id': (deviceId ?? '').toString(),
        'x-app-secret': _appSecret,
        ...attestation,
      };
    } catch (_) {
      _imageHeaders = {'x-app-secret': _appSecret};
    }

    try {
      // pruneToCards يهاجر تقدم النظام القديم تلقائياً (المعروف ⇒ الصندوق 3 وبعد 3 أيام) ثم ينظّف المحذوف
      _progress = Map<int, FlashcardCardProgress>.of(
        await FlashcardProgressStore.pruneToCards(widget.deck.id, widget.deck.cardIds),
      );
      _hintSeen = await FlashcardProgressStore.hasSeenSwipeHint();
    } catch (_) {
      _progress = <int, FlashcardCardProgress>{};
      _hintSeen = true; // لا نزعج الطالب بالتلميح إن تعذّر القراءة
    }

    _startSession(widget.mode);

    if (!mounted) return;
    setState(() => _ready = true);
    _prefetchUpcoming();
  }

  // ───────────────────────── بناء الجولة ─────────────────────────

  /// جلسة جديدة بوضع محدد. الطابور كامل بلا حد ولا دفعات.
  void _startSession(FlashcardStudyMode mode) {
    _mode = mode;
    _startedFromNew = mode == FlashcardStudyMode.newCards;
    _startRound(
      FlashcardLeitner.buildQueue(mode: mode, cards: _cards, progress: _progress, today: _today),
      keepRoundNumber: false,
    );
  }

  void _startRound(List<FlashcardModel> queue, {required bool keepRoundNumber}) {
    _queue = queue;
    _index = 0;
    if (!keepRoundNumber) _round = 1;
    _roundKnownIds.clear();
    _roundLearningIds.clear();
    _showSummary = queue.isEmpty; // طابور فارغ ⇒ نذهب للملخص مباشرة
    _nextReviewTimer?.cancel();
    _nextReviewDays = null;
    _resetCardState();
  }

  void _resetCardState() {
    _cardKey = GlobalKey<FlashcardFlipCardState>();
    _flipped = false;
    _rating = false;
  }

  // ───────────────────────── التقييم ─────────────────────────

  void _rate(bool known) {
    if (_rating || !_flipped) return;
    final state = _cardKey.currentState;
    if (state == null) return;
    // _rating يصبح true فقط إن بدأ الخروج فعلاً (قد تكون البطاقة مشغولة بتلميح السحب)
    if (state.flyOut(known)) _rating = true;
  }

  void _onDecision(bool known) {
    if (_showSummary || _index >= _queue.length) return; // حماية: لا تقييم خارج الجولة
    final card = _queue[_index];
    final today = _today;
    final previous = _progress[card.id];

    final FlashcardCardProgress updated;
    if (known) {
      // «ذاكر المجموعة كاملة»: لا ترفع بطاقة في الصندوق 2+؛ غير ذلك خطوة واحدة فقط للأعلى
      // والموعد من تاريخ المراجعة الفعلي (وليس موعداً قديماً)
      updated = _mode == FlashcardStudyMode.studyAnyway
          ? FlashcardLeitner.afterGotItStudyAnyway(card.id, previous, today)
          : FlashcardLeitner.afterGotIt(card.id, previous?.box, today);
      _roundKnownIds.add(card.id);
    } else {
      // دائماً الصندوق 1 (غلط) حتى لو كانت متقنة
      updated = FlashcardLeitner.afterStillLearning(card.id, today);
      _roundLearningIds.add(card.id);
    }
    final changed =
        previous == null || previous.box != updated.box || previous.dueDate != updated.dueDate;
    _progress[card.id] = updated;
    if (changed) _persist(updated);

    final next = _index + 1;
    if (next >= _queue.length) {
      _nextReviewTimer?.cancel();
      setState(() {
        _index = next;
        _showSummary = true;
        _rating = false;
        _nextReviewDays = null;
      });
      return;
    }
    setState(() {
      _index = next;
      _resetCardState();
    });
    if (known) {
      // من الموعد الفعلي للبطاقة (قد لا يتغير في «ذاكر المجموعة كاملة»)
      final due = FlashcardLeitner.parseDateKey(updated.dueDate) ?? today;
      final days = FlashcardLeitner.daysBetween(today, due);
      if (days >= 1) _showNextReviewHint(days);
    }
    _prefetchUpcoming();
  }

  /// يعرض «المراجعة التالية بعد N يوم» تحت البطاقة لثانيتين تقريباً.
  void _showNextReviewHint(int days) {
    _nextReviewTimer?.cancel();
    setState(() {
      _nextReviewDays = days;
      _nextReviewSeq++;
    });
    _nextReviewTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _nextReviewDays = null);
    });
  }

  /// حفظ محلي متسلسل لسجل البطاقة. الفشل لا يوقف الدراسة (التقدم في الذاكرة يبقى للجلسة).
  void _persist(FlashcardCardProgress progress) {
    _saveChain = _saveChain.then((_) async {
      try {
        await FlashcardProgressStore.saveCardProgress(widget.deck.id, progress);
      } catch (_) {}
    });
  }

  // ───────────────────────── تلميح السحب ─────────────────────────

  void _onFlipChanged(bool flipped) {
    setState(() => _flipped = flipped);
    // التلميح مرة واحدة فقط، وبعد القلب لأن السحب لا يعمل قبله
    if (flipped && !_hintSeen) {
      _hintSeen = true;
      FlashcardProgressStore.markSwipeHintSeen().catchError((_) {});
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _cardKey.currentState?.playSwipeHint();
      });
    }
  }

  // ───────────────────────── الإعدادات ─────────────────────────

  /// خلط فوري: كل ضغطة تعيد ترتيب البطاقات المتبقية عشوائياً (بما فيها الحالية)
  /// وتعرض الطالب بطاقة جديدة مباشرة. ما أُنجز في هذه الجولة يبقى في مكانه.
  void _shuffleRemaining() {
    if (_rating || _showSummary) return; // البطاقة الحالية تخرج الآن
    final remaining = _queue.sublist(_index);
    if (remaining.length < 2) return; // لا شيء يُخلط

    final before = List<FlashcardModel>.of(remaining);
    final shuffled = List<FlashcardModel>.of(remaining);
    // نتأكد أن الترتيب تغيّر فعلاً (احتمال التطابق ضئيل لكن غير معدوم)
    for (var attempt = 0; attempt < 5; attempt++) {
      shuffled.shuffle(_random);
      final same = List.generate(shuffled.length, (i) => shuffled[i].id == before[i].id)
          .every((e) => e);
      if (!same) break;
    }

    setState(() {
      _queue = [..._queue.sublist(0, _index), ...shuffled];
      _resetCardState(); // بطاقة جديدة تظهر من وجهها الأمامي
    });
    _prefetchUpcoming();
  }

  // ───────────────────────── الجولات ─────────────────────────

  /// «كرر الغلط»: كل بطاقات الصندوق 1 في المجموعة. تتكرر الجولات حتى لا يبقى غلط.
  void _repeatWrong() {
    final queue = FlashcardLeitner.selectWrong(cards: _cards, progress: _progress, today: _today);
    if (queue.isEmpty) return;
    setState(() {
      _mode = FlashcardStudyMode.repeatWrong;
      _round += 1;
      _startRound(queue, keepRoundNumber: true);
    });
    _prefetchUpcoming();
  }

  /// «ابدأ مراجعة المستحقة»: الغلط أولاً ثم المستحقة بالأقدم، بلا حد.
  void _startDueReview() {
    final queue = FlashcardLeitner.selectReview(cards: _cards, progress: _progress, today: _today);
    if (queue.isEmpty) return;
    setState(() {
      _mode = FlashcardStudyMode.review;
      _startedFromNew = false;
      _round += 1;
      _startRound(queue, keepRoundNumber: true);
    });
    _prefetchUpcoming();
  }

  // ───────────────────────── الخروج ─────────────────────────

  Future<void> _exit() async {
    await _saveChain; // التقدم يُحفظ عند كل تقييم؛ ننتظر آخر كتابة قبل الإغلاق
    if (mounted) Navigator.of(context).pop();
  }

  /// زر «إنهاء» في الملخص: يغلق المذاكرة ويرجع بنتيجة true ليغلق صفحة المجموعة أيضاً
  /// فيصل الطالب لشاشة المواد (X وزر الرجوع يظلان يرجعان لصفحة المجموعة).
  Future<void> _finish() async {
    await _saveChain;
    if (mounted) Navigator.of(context).pop(true);
  }

  // ───────────────────────── الصور ─────────────────────────

  String _imageUrl(String fileId) =>
      '$_baseUrl/api/exams/get-image?file_id=${Uri.encodeQueryComponent(fileId)}';

  /// يحمّل مسبقاً صور البطاقتين التاليتين لتظهر فوراً.
  void _prefetchUpcoming() {
    if (!mounted || _showSummary) return;
    final end = math.min(_index + 3, _queue.length);
    for (var i = _index; i < end; i++) {
      final c = _queue[i];
      for (final id in [c.frontImageFileId, c.backImageFileId]) {
        if (id == null || id.isEmpty) continue;
        try {
          precacheImage(
            CachedNetworkImageProvider(_imageUrl(id), headers: _imageHeaders),
            context,
            onError: (_, __) {},
          );
        } catch (_) {}
      }
    }
  }

  void _showZoomableImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: url,
                httpHeaders: _imageHeaders,
                placeholder: (context, _) =>
                    Center(child: CircularProgressIndicator(color: AppColors.flashcardAccent)),
                errorWidget: (context, _, __) => const Icon(Icons.error, color: AppColors.error),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.flashcardAccent),
    );
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return ScreenProtectWrapper(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          // زر الرجوع في الموبايل = نفس «إنهاء»: يتخطى صفحة المجموعة ويرجع لشاشة المواد
          await _finish();
        },
        child: Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: SafeArea(
            child: !_ready
                ? Center(child: CircularProgressIndicator(color: AppColors.flashcardAccent))
                : _cards.isEmpty
                    ? _buildEmpty()
                    : _showSummary
                        ? _buildSummary()
                        : _buildStudy(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Column(
      children: [
        _buildHeader(showControls: false),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                AppLocalizations.of(context)!.flashcardNoCards,
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final today = _today;
    final wrong = FlashcardLeitner.countWrong(cards: _cards, progress: _progress);
    final dueNonWrong =
        FlashcardLeitner.countDueNonWrong(cards: _cards, progress: _progress, today: today);
    final newLeft = FlashcardLeitner.countNew(cards: _cards, progress: _progress);
    // «ابدأ مراجعة المستحقة» فقط لسلسلة بدأت بالجديدة ويوجد مستحق غير الغلط
    // (الغلط له زر «كرر الغلط»).
    final canStartReview = _startedFromNew && dueNonWrong > 0;
    return Column(
      children: [
        _buildHeader(showControls: false),
        Expanded(
          child: Center(
            child: FlashcardRoundSummary(
              round: _round,
              roundKnown: _roundKnownIds.length,
              roundLearning: _roundLearningIds.length,
              totalKnown: _knownCount,
              totalCards: _cards.length,
              schedule: FlashcardLeitner.upcomingSchedule(_progress.values, today),
              allDone: wrong == 0 && dueNonWrong == 0 && newLeft == 0,
              wrongCount: wrong,
              dueReviewCount: dueNonWrong,
              onRepeatWrong: wrong > 0 ? _repeatWrong : null,
              onStartDueReview: canStartReview ? _startDueReview : null,
              onFinish: _finish,
            ),
          ),
        ),
      ],
    );
  }

  String _modeLabel(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (_mode) {
      case FlashcardStudyMode.newCards:
        return l.flashcardModeNew;
      case FlashcardStudyMode.review:
        return l.flashcardModeReview;
      case FlashcardStudyMode.repeatWrong:
        return l.flashcardModeRepeatWrong;
      case FlashcardStudyMode.studyAnyway:
        return l.flashcardModeStudyAnyway;
    }
  }

  Widget _buildHeader({required bool showControls}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.flashcardClose,
            onPressed: _exit,
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
          if (showControls)
            IconButton(
              tooltip: AppLocalizations.of(context)!.flashcardShuffleTooltip,
              onPressed: (_queue.length - _index) > 1 ? _shuffleRemaining : null,
              icon: Icon(
                LucideIcons.shuffle,
                color: (_queue.length - _index) > 1
                    ? AppColors.textSecondary
                    : AppColors.textSecondary.withOpacity(0.35),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStudy() {
    final accent = AppColors.flashcardAccent;
    final total = _queue.length;
    final card = _queue[_index];
    final progress = total == 0 ? 0.0 : _index / total;

    return Column(
      children: [
        _buildHeader(showControls: true),

        // شريط التقدم + العداد
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: accent,
                        backgroundColor: AppColors.flashcardTrack,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_index + 1}/$total',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accent),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_round > 1)
                    _Chip(
                      label: AppLocalizations.of(context)!.flashcardRoundChip(_round),
                      color: accent,
                    ),
                  const Spacer(),
                  // اسم وضع الجلسة الحالي
                  _Chip(label: _modeLabel(context), color: accent),
                ],
              ),
            ],
          ),
        ),

        // البطاقة
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: FlashcardFlipCard(
              key: _cardKey,
              card: card,
              imageUrlBuilder: _imageUrl,
              imageHeaders: _imageHeaders,
              onFlipChanged: _onFlipChanged,
              onDecision: _onDecision,
              onImageTap: _showZoomableImage,
            ),
          ),
        ),

        // تلميح «المراجعة التالية…» تحت البطاقة بعد «عرفتها» (ارتفاع ثابت كي لا تقفز البطاقة)
        SizedBox(
          height: 20,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _nextReviewDays == null
                ? const SizedBox.shrink(key: ValueKey('next_hint_none'))
                : Row(
                    key: ValueKey('next_hint_$_nextReviewSeq'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.clock, size: 13, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)!.flashcardNextReviewIn(_nextReviewDays!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        // الأزرار تظهر بعد القلب فقط. ارتفاع ثابت كي لا تقفز البطاقة.
        SizedBox(
          height: 84,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _flipped ? _buildRatingButtons() : _buildFlipHint(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFlipHint() {
    return Center(
      key: const ValueKey('flip_hint'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.rotateCw, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context)!.flashcardTapToFlip,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingButtons() {
    return Padding(
      key: const ValueKey('rating_buttons'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      // الترتيب فيزيائي (يسار = ما زلت أتعلم، يمين = عرفتها) في العربية والإنجليزية
      // ليتطابق مع اتجاه السحب ولا ينعكس مع RTL.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () => _rate(false),
                icon: const Icon(LucideIcons.rotateCcw, size: 18),
                label: Text(
                  AppLocalizations.of(context)!.flashcardStillLearning,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withOpacity(0.7), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _rate(true),
                icon: const Icon(LucideIcons.check, size: 18),
                label: Text(
                  AppLocalizations.of(context)!.flashcardGotIt,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
