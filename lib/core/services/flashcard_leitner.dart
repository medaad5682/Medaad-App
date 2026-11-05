import '../../data/models/flashcard_model.dart';

/// 🗓️ نظام لايتنر للتكرار المتباعد (Step 19) — منطق صرف (بدون Flutter/Hive) كي يسهل اختباره.
///
/// الصناديق الخمسة والفواصل بالأيام التقويمية (وليس الساعات):
///
/// | الصندوق | المعنى               | المراجعة التالية بعد «عرفتها» |
/// |---------|----------------------|-------------------------------|
/// | 1       | جديدة / نُسيت للتو   | في نفس الجلسة (تكرار)          |
/// | 2       | أجبت صح مرة          | يوم                           |
/// | 3       | تصبح مألوفة          | 3 أيام                         |
/// | 4       | متينة نسبياً         | 7 أيام                         |
/// | 5       | متقنة                | 14 يوماً                       |
///
/// - «عرفتها»: صندوق + 1 (الصندوق 5 يبقى 5)، والموعد = **تاريخ المراجعة الفعلي** + فاصل الصندوق الجديد.
/// - «ما زلت أتعلم»: عودة للصندوق 1 مهما كان صندوقها السابق، والموعد = اليوم (تُعاد في نفس الجلسة،
///   وإن أُغلق التطبيق تبقى مستحقة فوراً في الجلسة القادمة).
/// - المعروف = الصناديق 3/4/5، وغير المعروف = 1/2، و«المتقن» (شريط تقدم المجموعة) = 4/5.
class FlashcardLeitner {
  FlashcardLeitner._();

  static const int boxCount = 5;

  /// الهدف اليومي الافتراضي: حجم دفعة (هدف مرن وليس حداً صارماً — «مراجعة المزيد» تحمّل دفعة أخرى).
  static const int dailyReviewTarget = 30;

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

  /// سجل بطاقة هاجرناها من قائمة «المعروفة» القديمة.
  static FlashcardCardProgress migratedKnown(int cardId, DateTime today) {
    return FlashcardCardProgress(
      cardId: cardId,
      box: migratedBox,
      dueDate: dateKey(addDays(today, migratedDueInDays)),
    );
  }

  // ───────────────────────── الاستحقاق ─────────────────────────

  /// مستحقة حين: لا سجل لها (بطاقة جديدة لم تُدرَس)، أو `dueDate <= today`.
  static bool isDue(FlashcardCardProgress? p, DateTime today) {
    if (p == null) return true;
    return p.dueDayNumber(today) <= dayNumber(today);
  }

  /// يختار البطاقات المستحقة للجلسة بالأولوية:
  ///  1) التي عُلّمت «ما زلت أتعلم» سابقاً (الصندوق 1 ولها سجل)،
  ///  2) الأقدم تأخراً (أقدم موعد أولاً)،
  ///  3) باقي المستحقة اليوم،
  ///  4) الجديدة التي لم تُدرَس أبداً.
  ///
  /// لا يغيّر أي موعد: ما لم يدخل الدفعة يبقى متأخراً بموعده الأصلي.
  /// [exclude] تُستبعد (مثلاً بطاقات «ما زلت أتعلم» المعلّقة في الجلسة الحالية).
  /// [limit] حجم الدفعة (null = الكل).
  static List<FlashcardModel> selectDue({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
    Set<int> exclude = const <int>{},
    int? limit,
  }) {
    final todayN = dayNumber(today);
    final learning = <_Ranked>[];
    final overdue = <_Ranked>[];
    final dueToday = <_Ranked>[];
    final fresh = <FlashcardModel>[];

    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      if (exclude.contains(c.id)) continue;
      final p = progress[c.id];
      if (p == null) {
        fresh.add(c);
        continue;
      }
      final dn = p.dueDayNumber(today);
      if (dn > todayN) continue; // غير مستحقة بعد
      final entry = _Ranked(c, dn, i);
      if (p.box <= 1) {
        learning.add(entry);
      } else if (dn < todayN) {
        overdue.add(entry);
      } else {
        dueToday.add(entry);
      }
    }

    int byDueThenOrder(_Ranked a, _Ranked b) {
      final c = a.dueDay.compareTo(b.dueDay);
      return c != 0 ? c : a.index.compareTo(b.index);
    }

    learning.sort(byDueThenOrder);
    overdue.sort(byDueThenOrder);
    dueToday.sort((a, b) => a.index.compareTo(b.index));

    final result = <FlashcardModel>[
      ...learning.map((e) => e.card),
      ...overdue.map((e) => e.card),
      ...dueToday.map((e) => e.card),
      ...fresh,
    ];
    if (limit != null && result.length > limit) return result.sublist(0, limit);
    return result;
  }

  /// عدد البطاقات المستحقة في [cards] (يشمل الجديدة) مع استبعاد [exclude].
  static int countDue({
    required List<FlashcardModel> cards,
    required Map<int, FlashcardCardProgress> progress,
    required DateTime today,
    Set<int> exclude = const <int>{},
  }) {
    var n = 0;
    for (final c in cards) {
      if (exclude.contains(c.id)) continue;
      if (isDue(progress[c.id], today)) n++;
    }
    return n;
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

  /// المستحقة اليوم (تشمل الجديدة والمتأخرة و«ما زلت أتعلم»).
  final int due;

  /// المتقنة (الصندوق 4 أو 5) — شريط التقدم.
  final int mastered;

  /// المعروفة (الصناديق 3 و4 و5).
  final int known;

  /// وجود أي تقدم محفوظ (لإظهار زر إعادة الضبط).
  final bool hasProgress;

  /// إن لم يوجد مستحق: بعد كم يوم أقرب مراجعة (null إن لا يوجد).
  final int? nextReviewInDays;

  const FlashcardDeckStats({
    required this.total,
    required this.due,
    required this.mastered,
    required this.known,
    required this.hasProgress,
    required this.nextReviewInDays,
  });

  static const FlashcardDeckStats empty = FlashcardDeckStats(
    total: 0,
    due: 0,
    mastered: 0,
    known: 0,
    hasProgress: false,
    nextReviewInDays: null,
  );
}
