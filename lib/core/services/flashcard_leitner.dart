import '../../data/models/flashcard_model.dart';

/// أوضاع المذاكرة الأربعة (صفحة المجموعة ← جلسة المذاكرة).
///
/// - [newCards]: البطاقات الجديدة فقط (لا سجل لها).
/// - [review]: كروت المراجعة (الغلط أولاً ثم المستحقة بالأقدم).
/// - [repeatWrong]: كل بطاقات الصندوق 1 في المجموعة، وتتكرر جولاتها حتى لا يبقى غلط.
/// - [studyAnyway]: المجموعة كاملة بدون ترقية (انظر [FlashcardLeitner.afterGotItStudyAnyway]).
enum FlashcardStudyMode { newCards, review, repeatWrong, studyAnyway }

/// 🗓️ نظام لايتنر للتكرار المتباعد — منطق صرف (بدون Flutter/Hive) كي يسهل اختباره.
///
/// الصناديق الخمسة والفواصل بالأيام التقويمية (وليس الساعات):
///
/// | الصندوق | المعنى               | المراجعة التالية بعد «عرفتها» |
/// |---------|----------------------|-------------------------------|
/// | 1       | غلط / نُسيت للتو      | في نفس الجلسة (تكرار)          |
/// | 2       | أجبت صح مرة          | يوم                           |
/// | 3       | تصبح مألوفة          | 3 أيام                         |
/// | 4       | متينة نسبياً         | 7 أيام                         |
/// | 5       | متقنة                | 14 يوماً                       |
///
/// ## التعريفات
/// - **جديدة**: بطاقة بلا أي سجل (ليست في أي صندوق).
/// - **غلط**: أي بطاقة لها سجل وهي في الصندوق 1 (مشتقة من الصندوق، بلا علامة منفصلة).
/// - **مراجعة**: كل الغلط + باقي السجلات التي `dueDate <= today`.
///   الترتيب: الغلط أولاً ثم الباقي، وداخل كل مجموعة الأقدم موعداً ثم ترتيب المجموعة.
/// - لا يوجد حد لحجم الجلسة ولا تقسيم دفعات.
///
/// ## الانتقالات
/// - «عرفتها»: صندوق + 1 (الصندوق 5 يبقى 5)، والموعد = **تاريخ المراجعة الفعلي** + فاصل الصندوق الجديد.
///   المتأخرة لا تُعاقَب: تترقى عادي ويُحسب موعدها من يوم المراجعة.
/// - «ما زلت أتعلم»: عودة للصندوق 1 مهما كان صندوقها السابق، والموعد = اليوم.
/// - «ذاكر المجموعة كاملة» (Study Anyway): «عرفتها» لا ترفع أي بطاقة أبداً (انظر [afterGotItStudyAnyway]).
/// - المعروف = الصناديق 3/4/5، وغير المعروف = 1/2، و«المتقن» (شريط تقدم المجموعة) = 4/5.
class FlashcardLeitner {
  FlashcardLeitner._();

  static const int boxCount = 5;

  /// فاصل كل صندوق بالأيام (الفهرس = رقم الصندوق؛ الصندوق 1 = نفس الجلسة = 0).
  static const List<int> _intervals = [0, 0, 1, 3, 7, 14];

  /// أول موعد للبطاقات المهاجَرة من النظام القديم (معروفة سابقاً ⇒ الصندوق 3 وبعد 3 أيام).
  static const int migratedBox = 3;
  static const int migratedDueInDays = 3;

  static int clampBox(int box) => box < 1 ? 1 : (box > boxCount ? boxCount : box);

  /// الفاصل (بالأيام) الذي يلي «عرفتها» حين تكون البطاقة في [box].
  static int intervalDays(int box) => _intervals[clampBox(box)];

  /// الصندوق بعد «عرفتها»: خطوة واحدة فقط للأعلى، والصندوق 5 يبقى 5.
  static int boxAfterGotIt(int box) => clampBox(clampBox(box) + 1);

  static bool isWrongBox(int box) => box <= 1;
  static bool isKnownBox(int box) => box >= 3;
  static bool isMasteredBox(int box) => box >= 4;

  // ───────────────────────── التواريخ (تقويمية محلية) ─────────────────────────

  /// تاريخ اليوم المحلي بدون وقت.
  static DateTime today([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// `yyyy-MM-dd` (يُرتَّب أبجدياً كما يُرتَّب زمنياً).
  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// يقرأ `yyyy-MM-dd` ويرجع null إن كان غير صالح.
  static DateTime? parseDateKey(String? s) {
    if (s == null) return null;
    final parts = s.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  /// إضافة أيام تقويمية (آمنة مع تغيير التوقيت الصيفي).
  static DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  /// رقم اليوم (عدد الأيام منذ 1970 بتوقيت UTC) — يتفادى مشاكل الساعات الصيفية.
  static int dayNumber(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// عدد الأيام التقويمية من [from] إلى [to] (موجب = في المستقبل).
  static int daysBetween(DateTime from, DateTime to) => dayNumber(to) - dayNumber(from);

  // ───────────────────────── الانتقالات ─────────────────────────

  /// نتيجة «عرفتها»: يُحسب الموعد من تاريخ المراجعة الفعلي [today] وليس من موعد قديم.
  /// تُستدعى **مرة واحدة** لكل تقييم.
  static FlashcardCardProgress afterGotIt(int cardId, int? previousBox, DateTime today) {
    final box = boxAfterGotIt(previousBox ?? 1);
    return FlashcardCardProgress(
      cardId: cardId,
      box: box,
      dueDate: dateKey(addDays(today, intervalDays(box))),
    );
  }

  /// نتيجة «ما زلت أتعلم»: الصندوق 1 دائماً، ومستحقة اليوم.
  static FlashcardCardProgress afterStillLearning(int cardId, DateTime today) {
    return FlashcardCardProgress(cardId: cardId, box: 1, dueDate: dateKey(today));
  }

  /// «عرفتها» داخل «ذاكر المجموعة كاملة»: لا تُرفع أي بطاقة بسبب المذاكرة المبكرة.
  ///  - بطاقة جديدة (لا سجل) أو في الصندوق 1 ⇒ الصندوق 2 وموعدها غداً.
  ///  - بطاقة في الصندوق 2 أو أعلى ⇒ يُرجَع سجلها كما هو بلا أي تغيير (لا صندوق ولا موعد).
  static FlashcardCardProgress afterGotItStudyAnyway(
    int cardId,
    FlashcardCardProgress? existing,
    DateTime today,
  ) {
    if (existing == null || isWrongBox(existing.box)) {
      return afterGotIt(cardId, existing?.box, today);
    }
    return existing;
  }

  /// سجل بطاقة هاجرناها من قائمة «المعروفة» القديمة.
  static FlashcardCardProgress migratedKnown(int cardId, DateTime today) {
    return FlashcardCardProgress(
      cardId: cardId,
      box: migratedBox,
      dueDate: dateKey(addDays(today, migratedDueInDays)),
    );
  }

  // ───────────────────────── الاستحقاق والاختيار ─────────────────────────

  /// مستحقة حين: لا سجل لها (بطاقة جديدة لم تُدرَس)، أو `dueDate <= today`.
  static bool isDue(FlashcardCardProgress? p, DateTime today) {
    if (p == null) return true;
    return p.dueDayNumber(today) <= dayNumber(today);
  }

  /// **الجديدة**: كل بطاقة بلا سجل، بترتيب المجموعة. بلا حد.
  static List<FlashcardModel> selectNew({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
  }) {
    return cards.where((c) => !progress.containsKey(c.id)).toList();
  }

  /// **الغلط**: كل بطاقة لها سجل وهي في الصندوق 1 (في المجموعة كلها)،
  /// الأقدم موعداً أولاً، وعند التساوي ترتيب المجموعة.
  static List<FlashcardModel> selectWrong({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
  }) {
    final wrong = <_Ranked>[];
    for (var i = 0; i < cards.length; i++) {
      final p = progress[cards[i].id];
      if (p == null || !isWrongBox(p.box)) continue;
      wrong.add(_Ranked(cards[i], p.dueDayNumber(today), i));
    }
    wrong.sort(_byDueThenOrder);
    return wrong.map((e) => e.card).toList();
  }

  /// **المراجعة**: الغلط أولاً (يدخل دائماً حتى لو موعده غير واضح)، ثم باقي السجلات المستحقة
  /// (`dueDate <= today`) بالأقدم موعداً ثم ترتيب المجموعة. لا تشمل الجديدة. بلا حد.
  ///
  /// لا يغيّر أي موعد: ما لم تُقيَّم بطاقة يبقى موعدها الأصلي.
  static List<FlashcardModel> selectReview({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
  }) {
    final todayN = dayNumber(today);
    final wrong = <_Ranked>[];
    final rest = <_Ranked>[];
    for (var i = 0; i < cards.length; i++) {
      final p = progress[cards[i].id];
      if (p == null) continue; // الجديدة لها تبويبها
      final dn = p.dueDayNumber(today);
      if (isWrongBox(p.box)) {
        wrong.add(_Ranked(cards[i], dn, i));
      } else if (dn <= todayN) {
        rest.add(_Ranked(cards[i], dn, i));
      }
    }
    wrong.sort(_byDueThenOrder);
    rest.sort(_byDueThenOrder);
    return [...wrong.map((e) => e.card), ...rest.map((e) => e.card)];
  }

  /// طابور الجلسة حسب الوضع. «ذاكر المجموعة كاملة» = كل البطاقات بترتيب المجموعة.
  static List<FlashcardModel> buildQueue({
    required FlashcardStudyMode mode,
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
  }) {
    switch (mode) {
      case FlashcardStudyMode.newCards:
        return selectNew(cards: cards, progress: progress);
      case FlashcardStudyMode.review:
        return selectReview(cards: cards, progress: progress, today: today);
      case FlashcardStudyMode.repeatWrong:
        return selectWrong(cards: cards, progress: progress, today: today);
      case FlashcardStudyMode.studyAnyway:
        return List<FlashcardModel>.of(cards);
    }
  }

  static int countNew({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
  }) =>
      selectNew(cards: cards, progress: progress).length;

  static int countWrong({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
  }) {
    var n = 0;
    for (final c in cards) {
      final p = progress[c.id];
      if (p != null && isWrongBox(p.box)) n++;
    }
    return n;
  }

  /// المستحق من غير الغلط (الصندوق 2 فما فوق وموعده ≤ اليوم).
  static int countDueNonWrong({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
  }) {
    final todayN = dayNumber(today);
    var n = 0;
    for (final c in cards) {
      final p = progress[c.id];
      if (p == null || isWrongBox(p.box)) continue;
      if (p.dueDayNumber(today) <= todayN) n++;
    }
    return n;
  }

  /// عدد كروت المراجعة = الغلط + المستحق من غير الغلط.
  static int countReview({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
  }) =>
      countWrong(cards: cards, progress: progress) +
      countDueNonWrong(cards: cards, progress: progress, today: today);

  /// تفصيل تبويب المراجعة: غلط / متأخرة / مستحقة اليوم.
  static FlashcardReviewBreakdown reviewBreakdown({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
  }) {
    final todayN = dayNumber(today);
    var wrong = 0;
    var overdue = 0;
    var dueToday = 0;
    for (final c in cards) {
      final p = progress[c.id];
      if (p == null) continue;
      if (isWrongBox(p.box)) {
        wrong++;
        continue;
      }
      final dn = p.dueDayNumber(today);
      if (dn < todayN) {
        overdue++;
      } else if (dn == todayN) {
        dueToday++;
      }
    }
    return FlashcardReviewBreakdown(wrong: wrong, overdue: overdue, dueToday: dueToday);
  }

  /// جدول المراجعات القادمة: عدد البطاقات لكل «بعد كم يوم» (من الغد فصاعداً)، الأقرب أولاً.
  /// [maxEntries] لإبقاء الملخص مختصراً.
  static List<FlashcardScheduleEntry> upcomingSchedule(
    Iterable<FlashcardCardProgress> records,
    DateTime today, {
    int maxEntries = 4,
  }) {
    final counts = <int, int>{};
    for (final p in records) {
      final days = p.dueDayNumber(today) - dayNumber(today);
      if (days < 1) continue;
      counts[days] = (counts[days] ?? 0) + 1;
    }
    final days = counts.keys.toList()..sort();
    return days
        .take(maxEntries)
        .map((d) => FlashcardScheduleEntry(days: d, count: counts[d]!))
        .toList();
  }

  /// أقرب موعد قادم بالأيام (≥ 1) أو null إن لم توجد مراجعات قادمة.
  static int? nextReviewInDays(Iterable<FlashcardCardProgress> records, DateTime today) {
    int? best;
    for (final p in records) {
      final days = p.dueDayNumber(today) - dayNumber(today);
      if (days < 1) continue;
      if (best == null || days < best) best = days;
    }
    return best;
  }
}

class _Ranked {
  final FlashcardModel card;
  final int dueDay;
  final int index;
  const _Ranked(this.card, this.dueDay, this.index);
}

/// الأقدم موعداً أولاً، وعند التساوي ترتيب المجموعة.
int _byDueThenOrder(_Ranked a, _Ranked b) {
  final c = a.dueDay.compareTo(b.dueDay);
  return c != 0 ? c : a.index.compareTo(b.index);
}

/// تفصيل كروت المراجعة (للعرض في صفحة المجموعة).
class FlashcardReviewBreakdown {
  /// بطاقات الصندوق 1.
  final int wrong;

  /// مستحقة وموعدها قبل اليوم (الصندوق 2 فما فوق).
  final int overdue;

  /// مستحقة اليوم (الصندوق 2 فما فوق).
  final int dueToday;

  const FlashcardReviewBreakdown({
    required this.wrong,
    required this.overdue,
    required this.dueToday,
  });

  int get total => wrong + overdue + dueToday;
}

/// سجل تقدم بطاقة واحدة: مستقل تماماً عن بقية البطاقات.
///
/// `{ "cardId": "123", "box": 3, "dueDate": "2026-11-08" }`
class FlashcardCardProgress {
  final int cardId;
  final int box;

  /// تاريخ تقويمي محلي `yyyy-MM-dd`.
  final String dueDate;

  const FlashcardCardProgress({
    required this.cardId,
    required this.box,
    required this.dueDate,
  });

  bool get isKnown => FlashcardLeitner.isKnownBox(box);
  bool get isMastered => FlashcardLeitner.isMasteredBox(box);

  /// رقم يوم الاستحقاق. موعد تالف/غير مقروء ⇒ نعدّه مستحقاً اليوم (لا نخفي البطاقة أبداً).
  int dueDayNumber(DateTime today) {
    final d = FlashcardLeitner.parseDateKey(dueDate);
    return FlashcardLeitner.dayNumber(d ?? today);
  }

  Map<String, dynamic> toJson() => {
        'cardId': cardId.toString(),
        'box': box,
        'dueDate': dueDate,
      };

  /// يرجع null إن كان السجل غير صالح (بلا cardId). صندوق غير صالح ⇒ 1، موعد غير صالح ⇒ [today].
  static FlashcardCardProgress? fromJson(dynamic json, DateTime today) {
    if (json is! Map) return null;
    final rawId = json['cardId'];
    final id = rawId is int ? rawId : (rawId is num ? rawId.toInt() : int.tryParse('$rawId'));
    if (id == null) return null;
    final rawBox = json['box'];
    final box = rawBox is num ? rawBox.toInt() : (int.tryParse('$rawBox') ?? 1);
    final rawDue = json['dueDate']?.toString();
    final due = FlashcardLeitner.parseDateKey(rawDue) != null
        ? rawDue!.trim()
        : FlashcardLeitner.dateKey(today);
    return FlashcardCardProgress(
      cardId: id,
      box: FlashcardLeitner.clampBox(box),
      dueDate: due,
    );
  }
}

/// سطر في «المراجعات القادمة»: [count] بطاقة بعد [days] يوم.
class FlashcardScheduleEntry {
  final int days;
  final int count;
  const FlashcardScheduleEntry({required this.days, required this.count});
}

/// أرقام بطاقة المجموعة (تبويب الامتحانات والفلاش كاردس).
class FlashcardDeckStats {
  final int total;

  /// الجديدة: بلا سجل (لم تُجب أبداً).
  final int newCount;

  /// كروت المراجعة: الغلط + المستحق من غير الغلط.
  final int reviewCount;

  /// الغلط: بطاقات الصندوق 1 (جزء من [reviewCount]).
  final int wrongCount;

  /// المتقنة (الصندوق 4 أو 5) — شريط التقدم.
  final int mastered;

  /// المعروفة (الصناديق 3 و4 و5).
  final int known;

  /// وجود أي تقدم محفوظ (لإظهار «إعادة الضبط»).
  final bool hasProgress;

  /// إن لم يوجد جديد ولا مراجعة: بعد كم يوم أقرب مراجعة (null إن لا يوجد).
  final int? nextReviewInDays;

  const FlashcardDeckStats({
    required this.total,
    required this.newCount,
    required this.reviewCount,
    required this.wrongCount,
    required this.mastered,
    required this.known,
    required this.hasProgress,
    required this.nextReviewInDays,
  });

  static const FlashcardDeckStats empty = FlashcardDeckStats(
    total: 0,
    newCount: 0,
    reviewCount: 0,
    wrongCount: 0,
    mastered: 0,
    known: 0,
    hasProgress: false,
    nextReviewInDays: null,
  );
}
