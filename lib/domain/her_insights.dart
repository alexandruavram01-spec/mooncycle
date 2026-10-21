import 'cycle_engine.dart';
import 'day_key.dart';
import 'enums.dart';
import 'insights.dart';
import 'models.dart';
import 'profile.dart';

/// Insight cards for her: which card to show today, how it opens, and why.
///
/// Everything here runs on her phone; nothing she logs is sent anywhere to
/// choose a card. The wording lives in `lib/l10n/her_insights_en_gb.dart`;
/// this file only decides which card, by code. The rules are the reviewed
/// ones in `content/her-insights-en-GB.txt` and, for stage 1,
/// `content/her-insights-en-GB-stage1-reviewed.txt`.

/// The order cards are chosen in, most important first.
enum InsightTier {
  /// A warning sign she reported, such as bleeding outside a period.
  safety,

  /// Something she logged today (or yesterday, for evening loggers).
  logged,

  /// A pattern in her own history.
  history,

  /// Moments in her cycle and general information.
  education,
}

/// Days before a card may come back. The 30 reviewed cards and H01–H03 from
/// the first pack, the rest from the stage 1 review (21 October 2026).
const insightCooldownDays = <String, int>{
  'I01': 21, 'I02': 60, 'I03': 100, 'I05': 40, 'I06': 70, 'I07': 120,
  'I08': 365, 'I09': 35, 'I10': 40, 'I11': 60, 'I12': 40, 'I13': 35,
  'I14': 75, 'I16': 30, 'I17': 30, 'I18': 35, 'I19': 35, 'I20': 21,
  'I21': 21, 'I22': 30, 'I23': 28, 'I24': 60, 'I25': 90, 'I26': 120,
  'I27': 80, 'I28': 100, 'I29': 120, 'I30': 28, 'NEW01': 120, 'NEW02': 120,
  'H01': 21, 'H02': 60, 'H03': 45,
  'L01': 21, 'L02': 21, 'L03': 21, 'L04': 21, 'L05': 21, 'L06': 35,
  'L07': 30, 'L08': 60, 'L09': 21, 'L10': 21, 'L11': 21, 'L12': 21,
  'L13': 35, 'L14': 21, 'L15': 21, 'L16': 35, 'L17': 60, 'L18': 60,
  'L19': 45, 'L21': 14,
  'C01': 21, 'C03': 21, 'C04': 35, 'C05': 21, 'C06': 21, 'C08': 60,
};

/// Cards tied to a moment in her cycle: each shows at most once a cycle.
const insightMoments = {'M01', 'M02', 'M04', 'M05'};

/// Cards with a second wording, shown in turn. Both share the card's rest
/// period: a new wording is never a reason to show it again sooner.
const insightWordings = <String, List<String>>{
  'I01': ['I01', 'I01b'],
  'I12': ['I12', 'I12b'],
  'I16': ['I16', 'I16b'],
  'I17': ['I17', 'I17b'],
  'I19': ['I19', 'I19b'],
  'I20': ['I20', 'I20b'],
};

/// Every card code the picker can show, for checking that each has words.
Iterable<String> get allInsightCards => {
      ...insightCooldownDays.keys,
      ...insightMoments,
      for (final wordings in insightWordings.values) ...wordings,
    };

/// Every opening line code (P13 is a plain label, not used on cards).
const insightOpeningIds = [
  'P01', 'P02', 'P03', 'P04', 'P05', 'P06', 'P07', 'P08', 'P09', 'P10',
  'P11', 'P12',
];

/// The same opening line, about the same thing, rests this long.
const openingCooldownDays = 21;

/// What `symptom` holds for a heavy flow, which is not a symptom name.
const heavyFlow = 'heavy flow';

/// What `symptom` holds for under 6 hours of sleep.
const shortSleep = 'short sleep';

/// What `symptom` holds for an energy rating of 1 or 2 out of 5.
const lowEnergy = 'low energy';

/// The personal line a card opens with, and the numbers it needs.
///
/// Values by key: `symptom` (a symptom name, [heavyFlow] or [lowEnergy]),
/// `cycle_window` ([CyclePhase]), `friendly_date`, `start_date`, `end_date`
/// ([DayKey]), `sleep_hours` (double), `relative_to_estimate` (days, negative
/// when early) and plain counts for the rest.
class InsightOpening {
  const InsightOpening(this.id, [this.values = const {}]);

  final String id;
  final Map<String, Object> values;

  /// Openings about a symptom rest per symptom; the others per line.
  String get key {
    final symptom = values['symptom'];
    return symptom == null ? id : '$id:$symptom';
  }
}

/// A card that could be shown today, and what it answers.
class InsightCandidate {
  const InsightCandidate(
    this.id,
    this.tier, {
    this.rank = 1,
    this.symptom,
    this.alsoLogged,
    this.pattern,
    this.cycleLengths = const [],
    this.energyHigh,
    this.energyLow,
    this.openings = const [],
    this.cycleStart,
  });

  final String id;
  final InsightTier tier;

  /// Order within the tier, lowest first: symptoms logged together before
  /// single ones, a symptom with a personal pattern before one without.
  final int rank;

  /// What she logged that it answers ("Headache"), or [heavyFlow],
  /// [shortSleep], [lowEnergy].
  final String? symptom;

  /// The second thing logged, for cards about two together.
  final String? alsoLogged;

  /// For H01: the pattern it describes.
  final PhasePattern? pattern;

  /// For H02: her last cycle lengths, oldest first.
  final List<int> cycleLengths;

  /// For H03: the phases where her logged energy was highest and lowest.
  final CyclePhase? energyHigh;
  final CyclePhase? energyLow;

  /// Opening lines that fit, best first. The first one not resting is used.
  final List<InsightOpening> openings;

  /// For a moment card: the start of this cycle. It shows once after it.
  final DayKey? cycleStart;

  int get priority => tier.index * 10 + rank;
}

/// A card chosen for today: which wording, and how it opens.
class InsightPick {
  const InsightPick(this.candidate, {required this.wording, this.opening});

  final InsightCandidate candidate;

  /// The card code whose words to show: the card's own, or its second
  /// wording (I01b...).
  final String wording;
  final InsightOpening? opening;

  String get id => candidate.id;
  InsightTier get tier => candidate.tier;
  String? get symptom => candidate.symptom;
}

/// Everything the picker looks at. Built on her phone.
class InsightContext {
  const InsightContext({
    required this.today,
    required this.status,
    required this.logs,
    required this.profile,
    this.screeningReminders = false,
    this.sexualWellbeing = false,
    this.engine = const CycleEngine(),
  });

  final DayKey today;
  final CycleStatus status;
  final List<DayLog> logs;
  final UserProfile profile;

  /// She turned on cervical screening reminders in Settings.
  final bool screeningReminders;

  /// She turned on cards about sex and desire in Settings.
  final bool sexualWellbeing;
  final CycleEngine engine;

  bool get conceiving => profile.goal == TrackingGoal.conceive;

  /// The fertility journey, or fertile days turned on.
  bool get fertilityOn =>
      profile.journey == 'fertility' || profile.showFertileDays;

  bool get hormonalContraception =>
      _answer('affects') == 'Hormonal contraception' ||
      _answer('circumstances') == 'Hormonal contraception';

  /// When cycle-range, late-period and ovulation cards would not describe
  /// her body: contraception, pregnancy or breastfeeding, surgery, HRT.
  bool get estimatesUnsuitable =>
      hormonalContraception ||
      const {
        'Pregnant/breastfeeding',
        'Hysterectomy/ovary removal',
        'HRT (Hormone Replacement Therapy)',
      }.contains(_answer('affects')) ||
      _answer('circumstances') == 'Pregnancy/breastfeeding';

  /// The cards are written for the cycle and fertility journeys only.
  bool get supportedJourney =>
      profile.journey == null ||
      profile.journey == 'cycle' ||
      profile.journey == 'fertility';

  String? _answer(String id) {
    final value = profile.quizAnswers[id];
    return value is String ? value : null;
  }
}

/// What the phone remembers about cards: when each card and opening line was
/// last shown, which she marked "not relevant", which wording she saw last,
/// and today's choice so it stays put all day.
class InsightMemory {
  const InsightMemory({
    this.lastShown = const {},
    this.notRelevant = const {},
    this.lastWording = const {},
    this.pickDay,
    this.pickIds = const [],
    this.pickPriority,
    this.pickWording = const {},
    this.pickOpening = const {},
    this.dismissed = const {},
    this.screeningReminders = false,
    this.sexualWellbeing = false,
  });

  /// By card code, and by opening key ("P01:Headache", "P06").
  final Map<String, DayKey> lastShown;
  final Set<String> notRelevant;

  /// The wording last shown, for cards that have two.
  final Map<String, String> lastWording;

  /// Today's choice. [pickPriority] is that of its first card, or
  /// [nothingPicked] when there was nothing to show.
  final DayKey? pickDay;
  final List<String> pickIds;
  final int? pickPriority;
  final Map<String, String> pickWording;

  /// Opening key by card.
  final Map<String, String> pickOpening;

  /// Cards she closed on [pickDay].
  final Set<String> dismissed;
  final bool screeningReminders;
  final bool sexualWellbeing;

  static const nothingPicked = 1000;

  InsightMemory copyWith({
    Map<String, DayKey>? lastShown,
    Set<String>? notRelevant,
    Map<String, String>? lastWording,
    DayKey? pickDay,
    List<String>? pickIds,
    int? pickPriority,
    Map<String, String>? pickWording,
    Map<String, String>? pickOpening,
    Set<String>? dismissed,
    bool? screeningReminders,
    bool? sexualWellbeing,
  }) =>
      InsightMemory(
        lastShown: lastShown ?? this.lastShown,
        notRelevant: notRelevant ?? this.notRelevant,
        lastWording: lastWording ?? this.lastWording,
        pickDay: pickDay ?? this.pickDay,
        pickIds: pickIds ?? this.pickIds,
        pickPriority: pickPriority ?? this.pickPriority,
        pickWording: pickWording ?? this.pickWording,
        pickOpening: pickOpening ?? this.pickOpening,
        dismissed: dismissed ?? this.dismissed,
        screeningReminders: screeningReminders ?? this.screeningReminders,
        sexualWellbeing: sexualWellbeing ?? this.sexualWellbeing,
      );

  Map<String, Object?> toJson() => {
        'lastShown': {
          for (final MapEntry(:key, :value) in lastShown.entries)
            key: value.iso,
        },
        'notRelevant': notRelevant.toList(),
        'lastWording': lastWording,
        'pickDay': pickDay?.iso,
        'pickIds': pickIds,
        'pickPriority': pickPriority,
        'pickWording': pickWording,
        'pickOpening': pickOpening,
        'dismissed': dismissed.toList(),
        'screeningReminders': screeningReminders,
        'sexualWellbeing': sexualWellbeing,
      };

  static InsightMemory fromJson(Map<String, Object?> j) {
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    Map<String, String> stringMap(Object? v) => {
          if (v is Map)
            for (final MapEntry(:key, :value) in v.entries)
              if (key is String && value is String) key: value,
        };
    final shown = j['lastShown'];
    final day = j['pickDay'];
    return InsightMemory(
      lastShown: {
        if (shown is Map)
          for (final MapEntry(:key, :value) in shown.entries)
            if (key is String && value is String) key: DayKey.parse(value),
      },
      notRelevant: strings(j['notRelevant']).toSet(),
      lastWording: stringMap(j['lastWording']),
      pickDay: day is String ? DayKey.parse(day) : null,
      pickIds: strings(j['pickIds']),
      pickPriority: j['pickPriority'] as int?,
      pickWording: stringMap(j['pickWording']),
      pickOpening: stringMap(j['pickOpening']),
      dismissed: strings(j['dismissed']).toSet(),
      screeningReminders: j['screeningReminders'] as bool? ?? false,
      sexualWellbeing: j['sexualWellbeing'] as bool? ?? false,
    );
  }
}

class HerInsightPicker {
  const HerInsightPicker({this.insights = const InsightsEngine()});

  final InsightsEngine insights;

  static const _lowMood = ['Sad', 'Anxious'];
  static const _moodSymptoms = ['Sad', 'Anxious', 'Irritable', 'Sensitive'];
  static const _goodDay = ['Happy', 'Calm', 'Confident'];
  static const _discharge = ['Dry', 'Sticky', 'Creamy', 'Watery'];
  static const _premenstrual = ['Bloating', 'Food cravings', 'Breast tenderness'];

  /// Every card that applies today, in each tier's preferred order. A card
  /// can appear in more than one tier; [choose] keeps its most important.
  List<InsightCandidate> candidates(InsightContext c) {
    if (!c.supportedJourney || !c.status.hasData) return const [];
    final cycles = c.engine.deriveCycles(c.logs);
    if (cycles.isEmpty) return const [];
    final f = _Facts(c, cycles, insights);
    final out = <InsightCandidate>[];
    void add(
      String id,
      InsightTier tier, {
      int rank = 1,
      String? symptom,
      String? also,
      List<InsightOpening?> openings = const [],
      DayKey? cycleStart,
    }) =>
        out.add(
          InsightCandidate(
            id,
            tier,
            rank: rank,
            symptom: symptom,
            alsoLogged: also,
            openings: openings.whereType<InsightOpening>().toList(),
            cycleStart: cycleStart,
          ),
        );

    final phase = c.status.phase;
    final unsuitable = c.estimatesUnsuitable;
    final completed = f.completed;
    final untilPeriod = c.status.daysUntilNextPeriod;
    final estimateUntil = f.estimateUntil;

    // ---- 1. Safety: only on something she reported. Bleeding on a day
    // that is not part of a logged period, after her first period.
    for (final day in [c.today, c.today.addDays(-1)]) {
      final log = f.byDay[day];
      if (log != null &&
          log.flow.isBleeding &&
          cycles.first.start.isBefore(day) &&
          !_inPeriod(day, cycles)) {
        add('I21', InsightTier.safety);
        break;
      }
    }

    // ---- 2. What she logged: today, or yesterday if today is empty.
    final todayLog = f.byDay[c.today];
    final recent = todayLog != null && _hasEntries(todayLog)
        ? todayLog
        : f.byDay[c.today.addDays(-1)];
    if (recent != null) {
      const logged = InsightTier.logged;
      final s = recent.symptoms;
      final heavy = recent.flow == FlowIntensity.heavy;
      final short = (recent.sleepHours ?? 24) < 6;
      final drained = (recent.energy ?? 5) <= 2;
      final nearPeriod = phase == CyclePhase.menstrual ||
          (untilPeriod != null && untilPeriod >= 0 && untilPeriod <= 2);
      final beforePeriod = estimateUntil != null
          ? estimateUntil >= 1 && estimateUntil <= 7
          : phase == CyclePhase.luteal;
      final heavyThisCycle = c.logs.any(
        (l) => !l.date.isBefore(f.current.start) &&
            l.flow == FlowIntensity.heavy,
      );
      String? firstOf(List<String> names) {
        for (final name in names) {
          if (s.contains(name)) return name;
        }
        return null;
      }

      // Two things logged together, before either on its own.
      if (heavy && s.contains('Cramps')) {
        add('C01', logged,
            rank: 0, symptom: 'Cramps', also: heavyFlow,
            openings: [f.periodHistory()]);
      }
      if (s.contains('Headache') && s.contains('Nausea')) {
        add('C03', logged,
            rank: 0, symptom: 'Headache', also: 'Nausea',
            openings: [f.periodHistory(), f.upcomingPeriod()]);
      }
      final premenstrual = _premenstrual.where(s.contains).toList();
      if (beforePeriod && premenstrual.length >= 2) {
        add('C04', logged,
            rank: 0, symptom: premenstrual[0], also: premenstrual[1],
            openings: [f.upcomingPeriod()]);
      }
      final moody = firstOf(['Sad', 'Anxious', 'Irritable']);
      if (short && moody != null) {
        add('C05', logged,
            rank: 0, symptom: moody, also: shortSleep,
            openings: [f.sleep(recent)]);
      }
      if (short && (s.contains('Fatigue') || drained)) {
        add('C06', logged,
            rank: 0,
            symptom: s.contains('Fatigue') ? 'Fatigue' : lowEnergy,
            also: shortSleep,
            openings: [f.sleep(recent)]);
      }
      final low = firstOf(_lowMood);
      if (c.sexualWellbeing && s.contains('Low drive') && low != null) {
        add('C08', logged, rank: 0, symptom: 'Low drive', also: low);
      }

      // One thing logged. Opens with what she has logged before, if
      // anything; a card with a personal pattern comes first.
      void single(String id, String symptom, {bool private = false}) {
        final personal = private ? const <InsightOpening>[] : f.about(symptom, recent);
        add(id, logged,
            rank: personal.isEmpty ? 2 : 1,
            symptom: symptom,
            openings: [
              ...personal,
              if (symptom == lowEnergy || symptom == 'Fatigue')
                f.energy(recent),
              f.periodHistory(),
              f.upcomingPeriod(),
              f.afterEstimate(),
            ]);
      }

      if (s.contains('Cramps')) single(nearPeriod ? 'I01' : 'L01', 'Cramps');
      if (heavy) single('I02', heavyFlow);
      if (s.contains('Fatigue')) {
        single(heavyThisCycle ? 'I05' : 'I19', 'Fatigue');
      } else if (drained) {
        single('I19', lowEnergy);
      }
      if (s.contains('Ovulation pain')) single('I10', 'Ovulation pain');
      if (s.contains('Headache')) single(nearPeriod ? 'L05' : 'I16', 'Headache');
      if (s.contains('Bloating')) single('I17', 'Bloating');
      if (s.contains('Breast tenderness')) {
        single('I18', 'Breast tenderness');
      }
      final mood = firstOf(_moodSymptoms);
      if (mood != null) {
        final lingering = firstOf(_lowMood);
        if (lingering != null && f.lowMoodLingers()) {
          add('L07', logged, rank: 1, symptom: lingering);
        } else {
          single('I20', mood);
        }
      }
      if (s.contains('Egg white')) {
        single(
          c.conceiving ? 'I30' : (c.fertilityOn ? 'L18' : 'L17'),
          'Egg white',
        );
      }
      if (firstOf(_discharge) case final fluid?) single('L17', fluid);
      if (s.contains('Backache')) single(nearPeriod ? 'L02' : 'L03', 'Backache');
      if (s.contains('Joint pain')) single('L04', 'Joint pain');
      if (s.contains('Acne')) single('L09', 'Acne');
      if (s.contains('Nausea')) single('L10', 'Nausea');
      // Dizziness with a heavy flow needs its own clinician-approved card
      // (C02, on hold), so the plain dizziness card stays out of it.
      if (s.contains('Dizziness') && !heavy) single('L11', 'Dizziness');
      if (s.contains('Hot flush')) single('L12', 'Hot flush');
      if (s.contains('Food cravings')) single('L13', 'Food cravings');
      if (s.contains('Constipation')) single('L14', 'Constipation');
      if (s.contains('Diarrhoea')) single('L15', 'Diarrhoea');
      if (firstOf(['Appetite up', 'Appetite down']) case final appetite?) {
        single('L16', appetite);
      }
      if (s.contains('Low drive')) single('L19', 'Low drive', private: true);
      if (f.shortNights()) {
        add('L21', logged,
            rank: 2, symptom: shortSleep, openings: [f.sleep(recent)]);
      }
      // A good day, only when nothing more useful applies.
      if (firstOf(_goodDay) case final good?) {
        add('L06', InsightTier.education, rank: 9, symptom: good);
      }
    }

    // ---- 3. Her own history.
    const history = InsightTier.history;
    if (!unsuitable &&
        c.status.isLate &&
        untilPeriod != null &&
        untilPeriod <= -3 &&
        (c.status.confidence == PredictionConfidence.medium ||
            c.status.confidence == PredictionConfidence.high)) {
      // Neither card ever says she is pregnant.
      add(c.conceiving ? 'I23' : 'I22', history,
          openings: [f.afterEstimate()]);
    }

    final run = _bleedingRun(f.current, f.byDay);
    if (run >= 8 &&
        c.today.differenceInDays(f.current.start.addDays(run - 1)) <= 2) {
      add('I24', history);
    }

    final lengths = f.plausibleLengths;
    if (!unsuitable && _cyclesLookDifferent(lengths)) add('I25', history);

    var fatigueWithHeavy = 0;
    for (final cy in cycles) {
      final days = c.logs.where((l) => cy.contains(l.date));
      if (days.any((l) => l.flow == FlowIntensity.heavy) &&
          days.any((l) => l.symptoms.contains('Fatigue'))) {
        fatigueWithHeavy++;
      }
    }
    if (fatigueWithHeavy >= 2) add('I05', history);

    // Mood changes before her period in 3 or more recorded cycles.
    final beforeNow = estimateUntil != null
        ? estimateUntil >= 1 && estimateUntil <= 7
        : phase == CyclePhase.luteal;
    if (beforeNow && f.premenstrualMoodCycles() >= 3) {
      add('L08', history, rank: 0);
    }

    // A symptom that keeps coming back at this point of her cycle.
    for (final pattern in insights.phasePatterns(c.logs)) {
      if (pattern.phase == phase && _patternGroups.contains(pattern.symptom)) {
        out.add(InsightCandidate('H01', history, pattern: pattern));
        break;
      }
    }

    // Steady cycles: a reassuring fact, never a judgement.
    if (!unsuitable && lengths.length >= 3) {
      final last = lengths.sublist(lengths.length - 3);
      final steady = last.every((l) => l >= 21 && l <= 35) &&
          last.reduce((a, b) => a > b ? a : b) -
                  last.reduce((a, b) => a < b ? a : b) <=
              4;
      if (steady) {
        out.add(InsightCandidate('H02', history, cycleLengths: last));
      }
    }

    if (completed.length >= 2) {
      final energy = [
        for (final p in insights.byPhase(c.logs))
          if (p.energySamples >= 3 && p.averageEnergy != null) p,
      ]..sort((a, b) => b.averageEnergy!.compareTo(a.averageEnergy!));
      if (energy.length >= 2 &&
          energy.first.averageEnergy! - energy.last.averageEnergy! >= 1.0) {
        out.add(
          InsightCandidate(
            'H03',
            history,
            energyHigh: energy.first.phase,
            energyLow: energy.last.phase,
          ),
        );
      }
    }

    // ---- 4. Moments in her cycle, then general information.
    const edu = InsightTier.education;
    final start = f.current.start;
    final periodDay = c.today.differenceInDays(start);
    final bleedingToday = todayLog?.flow.isBleeding ?? false;

    if (periodDay >= 0 && periodDay <= 1) {
      add('M01', edu,
          rank: 0,
          cycleStart: start,
          openings: [if (!c.conceiving) f.startVersusEstimate(), f.cycleLengths()]);
    }
    if (periodDay >= 2 &&
        bleedingToday &&
        todayLog!.flow != FlowIntensity.heavy) {
      add('M02', edu,
          rank: 0, cycleStart: start, openings: [f.periodHistory()]);
    }
    final fertile = f.fertileWindow();
    if (fertile != null) {
      final sinceStart =
          c.today.differenceInDays(fertile.values['start_date']! as DayKey);
      if (sinceStart >= 0 && sinceStart <= 1) {
        add('M04', edu, rank: 0, cycleStart: start, openings: [fertile]);
      }
    }
    if (estimateUntil != null && estimateUntil >= 1 && estimateUntil <= 2) {
      add('M05', edu,
          rank: 0, cycleStart: start, openings: [f.upcomingPeriod()]);
    }

    switch (phase) {
      case CyclePhase.menstrual:
        final opening = [f.periodHistory()];
        add('I01', edu, openings: opening);
        add('I02', edu, openings: opening);
        add('I03', edu, openings: opening);
      case CyclePhase.follicular:
        add('I06', edu);
        if (!unsuitable) add('I07', edu);
        if (c.profile.showFertileDays && !c.conceiving && !unsuitable) {
          add('I11', edu, openings: [fertile]);
        }
      case CyclePhase.ovulatory:
        if (c.fertilityOn && !unsuitable) {
          add('I09', edu, openings: [fertile]);
          add('I10', edu, openings: [fertile]);
        }
        if (c.profile.showFertileDays && !c.conceiving && !unsuitable) {
          add('I11', edu, openings: [fertile]);
        }
      case CyclePhase.luteal:
        // With an estimate, the days-before cards come 3 to 7 days ahead.
        if (estimateUntil == null ||
            (estimateUntil >= 3 && estimateUntil <= 7)) {
          add('I12', edu, openings: [f.upcomingPeriod()]);
          add('I13', edu, openings: [f.upcomingPeriod()]);
        }
        if (completed.length >= 2) add('I14', edu);
    }
    if (c.conceiving) {
      add('I26', edu);
      add('I27', edu, openings: [fertile]);
      add('I29', edu);
      if (c.profile.tryingSince == 'year') add('I28', edu);
    }
    // Around the estimated day: a reminder that it is only an estimate.
    if (completed.isNotEmpty &&
        estimateUntil != null &&
        estimateUntil >= -2 &&
        estimateUntil <= 0) {
      add('NEW01', edu, openings: [f.upcomingPeriod(), f.afterEstimate()]);
    }
    if (c.hormonalContraception) add('NEW02', edu);
    if (c.screeningReminders) add('I08', edu);

    return out;
  }

  /// Today's cards from [candidates], following the reviewed rules: the
  /// most important tier wins; one card a day, plus a second only when the
  /// first is a safety card; the choice stays put all day unless something
  /// more important comes up, or what it answered is no longer logged; rest
  /// periods, "not relevant" and closed cards are respected; nothing on a
  /// day with nothing new to say.
  ///
  /// Returns the cards and, when it changed, the memory to save.
  static (List<InsightPick>, InsightMemory?) choose(
    List<InsightCandidate> candidates,
    InsightMemory memory,
    DayKey today,
  ) {
    final sameDay = memory.pickDay == today;
    final dismissed = sameDay ? memory.dismissed : const <String>{};

    // One entry per card, from the most important place it qualifies for,
    // remembering the order it was listed in for ties.
    final best = <String, (InsightCandidate, int)>{};
    for (final (index, candidate) in candidates.indexed) {
      final previous = best[candidate.id];
      if (previous == null || candidate.priority < previous.$1.priority) {
        best[candidate.id] = (candidate, previous?.$2 ?? index);
      }
    }

    bool rested(InsightCandidate candidate) {
      final last = memory.lastShown[candidate.id];
      if (last == null || last == today) return true;
      final cycleStart = candidate.cycleStart;
      if (cycleStart != null) return last.isBefore(cycleStart);
      return today.differenceInDays(last) >=
          (insightCooldownDays[candidate.id] ?? 30);
    }

    final usable = [
      for (final entry in best.values)
        if (!memory.notRelevant.contains(entry.$1.id) &&
            !dismissed.contains(entry.$1.id) &&
            rested(entry.$1))
          entry,
    ]..sort((a, b) {
        final order = a.$1.priority.compareTo(b.$1.priority);
        if (order != 0) return order;
        // Never shown first, then the one shown longest ago.
        final aLast = memory.lastShown[a.$1.id];
        final bLast = memory.lastShown[b.$1.id];
        if (aLast != bLast) {
          if (aLast == null) return -1;
          if (bLast == null) return 1;
          return aLast.differenceInDays(bLast);
        }
        return a.$2.compareTo(b.$2);
      });

    final fresh = <InsightCandidate>[];
    if (usable.isNotEmpty) {
      final first = usable.first.$1;
      fresh.add(first);
      if (first.tier == InsightTier.safety) {
        for (final (candidate, _) in usable) {
          if (candidate.tier == InsightTier.logged) {
            fresh.add(candidate);
            break;
          }
        }
      }
    }
    final freshPriority =
        fresh.isEmpty ? InsightMemory.nothingPicked : fresh.first.priority;

    if (sameDay) {
      final usableById = {
        for (final (candidate, _) in usable) candidate.id: candidate,
      };
      final kept = [
        for (final id in memory.pickIds)
          if (usableById[id] case final candidate?) candidate,
      ];
      // What this morning's card answered is no longer logged (a symptom
      // she removed): pick again rather than leave the space empty.
      final lapsed = memory.pickIds.any((id) => !best.containsKey(id));
      final storedPriority = memory.pickPriority ?? InsightMemory.nothingPicked;
      if (freshPriority >= storedPriority && !(lapsed && kept.isEmpty)) {
        return (
          [
            for (final candidate in kept)
              InsightPick(
                candidate,
                wording: memory.pickWording[candidate.id] ?? candidate.id,
                opening: _openingByKey(
                  candidate,
                  memory.pickOpening[candidate.id],
                ),
              ),
          ],
          null,
        );
      }
    }

    // New choice: alternate wordings, and open with the first line that is
    // not resting.
    bool openingRested(InsightOpening opening) {
      final last = memory.lastShown[opening.key];
      return last == null ||
          last == today ||
          today.differenceInDays(last) >= openingCooldownDays;
    }

    final picks = [
      for (final candidate in fresh)
        InsightPick(
          candidate,
          wording: _nextWording(candidate.id, memory.lastWording[candidate.id]),
          opening: candidate.tier == InsightTier.safety
              ? null
              : candidate.openings.where(openingRested).firstOrNull,
        ),
    ];

    return (
      picks,
      memory.copyWith(
        lastShown: {
          ...memory.lastShown,
          for (final pick in picks) pick.id: today,
          for (final pick in picks)
            if (pick.opening case final opening?) opening.key: today,
        },
        lastWording: {
          ...memory.lastWording,
          for (final pick in picks)
            if (insightWordings.containsKey(pick.id)) pick.id: pick.wording,
        },
        pickDay: today,
        pickIds: [for (final pick in picks) pick.id],
        pickPriority: freshPriority,
        pickWording: {for (final pick in picks) pick.id: pick.wording},
        pickOpening: {
          for (final pick in picks)
            if (pick.opening case final opening?) pick.id: opening.key,
        },
        dismissed: dismissed,
      ),
    );
  }

  static String _nextWording(String id, String? last) {
    final wordings = insightWordings[id];
    if (wordings == null) return id;
    if (last == null) return wordings.first;
    final index = wordings.indexOf(last);
    return wordings[(index + 1) % wordings.length];
  }

  static InsightOpening? _openingByKey(InsightCandidate candidate, String? key) {
    if (key == null) return null;
    for (final opening in candidate.openings) {
      if (opening.key == key) return opening;
    }
    return null;
  }

  static bool _hasEntries(DayLog log) =>
      log.symptoms.isNotEmpty ||
      log.flow != FlowIntensity.none ||
      log.energy != null ||
      log.sleepHours != null;

  /// Symptoms worth describing as a pattern: pain, mood and body, never
  /// discharge or sex.
  static final Set<String> _patternGroups = {
    ...?SymptomCatalog.groups['Pain'],
    ...?SymptomCatalog.groups['Mood'],
    ...?SymptomCatalog.groups['Body'],
  };

  static bool _inPeriod(DayKey day, List<Cycle> cycles) => cycles.any(
        (cy) =>
            !day.isBefore(cy.start) &&
            day.differenceInDays(cy.start) < cy.periodLength,
      );

  /// Days of bleeding logged one after another from the start of [cycle].
  static int _bleedingRun(Cycle cycle, Map<DayKey, DayLog> byDay) {
    var run = 0;
    while (byDay[cycle.start.addDays(run)]?.flow.isBleeding ?? false) {
      run++;
    }
    return run;
  }

  /// Two of her last three cycles outside 21 to 35 days, or her last two
  /// both well away from her own usual length.
  static bool _cyclesLookDifferent(List<int> lengths) {
    if (lengths.length >= 3) {
      final last = lengths.sublist(lengths.length - 3);
      if (last.where((l) => l < 21 || l > 35).length >= 2) return true;
    }
    if (lengths.length >= 6) {
      final earlier = [...lengths.sublist(0, lengths.length - 2)]..sort();
      final usual = earlier[earlier.length ~/ 2];
      final lastTwo = lengths.sublist(lengths.length - 2);
      if (lastTwo.every((l) => (l - usual).abs() >= 8)) return true;
    }
    return false;
  }
}

/// What her log says, for the triggers and the opening lines. Every opening
/// is built only from entries she actually made: a day she did not log is
/// unknown, never "no symptom".
class _Facts {
  _Facts(this.c, this.cycles, this.insights)
      : byDay = {for (final log in c.logs) log.date: log},
        current = cycles.last,
        completed = cycles.where((cy) => cy.isComplete).toList();

  final InsightContext c;
  final List<Cycle> cycles;
  final InsightsEngine insights;
  final Map<DayKey, DayLog> byDay;
  final Cycle current;
  final List<Cycle> completed;

  late final Map<DayKey, CyclePhase> phases = insights.phaseMap(c.logs);

  /// Days until the estimated period, only where estimates suit her body.
  int? get estimateUntil =>
      c.estimatesUnsuitable ? null : c.status.daysUntilNextPeriod;

  List<int> get plausibleLengths => [
        for (final cy in completed)
          if (cy.length! <= c.engine.maxPlausibleCycleLength) cy.length!,
      ];

  /// The last few completed cycles, newest first.
  Iterable<Cycle> get recentCompleted =>
      completed.reversed.take(c.engine.historyWindow);

  static bool _isSex(String symptom) =>
      SymptomCatalog.groups['Sex']?.contains(symptom) ?? false;

  bool Function(DayLog) _matcher(String symptom) => switch (symptom) {
        heavyFlow => (l) => l.flow == FlowIntensity.heavy,
        lowEnergy => (l) => (l.energy ?? 5) <= 2,
        _ => (l) => l.symptoms.contains(symptom),
      };

  /// P02, P01, P03, P04 about [symptom], logged on [recent]'s day. Numbers
  /// (sleep) and sex entries get none.
  List<InsightOpening> about(String symptom, DayLog recent) {
    if (symptom == shortSleep || _isSex(symptom)) return const [];
    final matches = _matcher(symptom);
    final day = recent.date;
    final found = <InsightOpening>[];

    // P02: in the same part of the cycle in 2 or more of at least 3
    // recorded cycles that have entries in that part.
    final window = phases[day] ?? c.status.phase;
    var eligible = 0;
    var matching = 0;
    for (final cy in recentCompleted) {
      final logged = [
        for (var d = cy.start; !d.isAfter(cy.end!); d = d.addDays(1))
          if (phases[d] == window)
            if (byDay[d] case final log?) log,
      ];
      if (logged.isEmpty) continue;
      eligible++;
      if (logged.any(matches)) matching++;
    }
    if (eligible >= 3 && matching >= 2) {
      found.add(InsightOpening('P02', {
        'symptom': symptom,
        'cycle_window': window,
        'matching_cycles': matching,
        'eligible_cycles': eligible,
      }));
    }

    // P01: on consecutive days up to that day.
    var streak = 0;
    for (var d = day; byDay[d] != null && matches(byDay[d]!); d = d.addDays(-1)) {
      streak++;
    }
    if (streak >= 2) {
      found.add(InsightOpening('P01', {
        'symptom': symptom,
        'consecutive_logged_days': streak,
      }));
    }

    // P03: within 2 days of the same cycle day in the previous cycle.
    if (cycles.length >= 2 && !day.isBefore(current.start)) {
      final previous = cycles[cycles.length - 2];
      final cycleDay = day.differenceInDays(current.start);
      for (var k = -2; k <= 2; k++) {
        final then = previous.start.addDays(cycleDay + k);
        if (!previous.contains(then)) continue;
        if (byDay[then] case final log? when matches(log)) {
          found.add(InsightOpening('P03', {'symptom': symptom}));
          break;
        }
      }
    }

    // P04: never logged before.
    if (!c.logs.any((l) => l.date.isBefore(day) && matches(l))) {
      found.add(InsightOpening('P04', {'symptom': symptom}));
    }
    return found;
  }

  /// P05: today is a logged period day, and at least 2 earlier periods have
  /// a logged day without bleeding straight after them.
  InsightOpening? periodHistory() {
    final today = byDay[c.today];
    if (today == null || !today.flow.isBleeding) return null;
    if (c.today.isBefore(current.start)) return null;
    final lengths = <int>[];
    for (final cy in recentCompleted) {
      final after = byDay[cy.start.addDays(cy.periodLength)];
      if (after != null && after.flow == FlowIntensity.none) {
        lengths.add(cy.periodLength);
      }
    }
    if (lengths.length < 2) return null;
    lengths.sort();
    return InsightOpening('P05', {
      'period_day': c.today.differenceInDays(current.start) + 1,
      'completed_period_count': lengths.length,
      'min_days': lengths.first,
      'max_days': lengths.last,
    });
  }

  /// P06: her next period is estimated within 7 days.
  InsightOpening? upcomingPeriod() {
    final until = estimateUntil;
    final date = c.status.predictedNextStart;
    if (until == null || date == null || until < 0 || until > 7) return null;
    return InsightOpening('P06', {
      'friendly_date': date,
      'days_from_today': until,
    });
  }

  /// P07: the estimated start has passed and no new period is logged.
  InsightOpening? afterEstimate() {
    final until = estimateUntil;
    if (until == null || until >= 0) return null;
    return InsightOpening('P07', {'days_past_estimate': -until});
  }

  /// P08: on a new period, how it compares with the estimate made before it.
  InsightOpening? startVersusEstimate() {
    if (c.estimatesUnsuitable || cycles.length < 2) return null;
    final before = [
      for (final log in c.logs)
        if (log.date.isBefore(current.start)) log,
    ];
    final earlier =
        c.engine.status(before, today: current.start.addDays(-1));
    final estimate = earlier.predictedNextStart;
    if (estimate == null) return null;
    return InsightOpening('P08', {
      'relative_to_estimate': current.start.differenceInDays(estimate),
    });
  }

  /// P09: at least 3 completed cycles.
  InsightOpening? cycleLengths() {
    if (c.estimatesUnsuitable) return null;
    final lengths = plausibleLengths;
    final recent = lengths.length <= c.engine.historyWindow
        ? lengths
        : lengths.sublist(lengths.length - c.engine.historyWindow);
    if (recent.length < 3) return null;
    final sorted = [...recent]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    return InsightOpening('P09', {
      'last_cycle_days': recent.last,
      'completed_cycles': recent.length,
      'median_cycle_days': median,
    });
  }

  /// P10: the sleep she logged for last night.
  InsightOpening? sleep(DayLog recent) {
    final hours = recent.sleepHours;
    if (hours == null) return null;
    return InsightOpening('P10', {'sleep_hours': hours});
  }

  /// P11: the energy she rated today.
  InsightOpening? energy(DayLog recent) {
    final rating = recent.energy;
    if (rating == null || recent.date != c.today) return null;
    return InsightOpening('P11', {'energy_rating': rating});
  }

  /// P12: her estimated fertile window, when she has fertility content on,
  /// estimates suit her, and her cycles give a reasonable estimate.
  InsightOpening? fertileWindow() {
    final start = c.status.fertileWindowStart;
    final end = c.status.fertileWindowEnd;
    if (!c.fertilityOn ||
        c.estimatesUnsuitable ||
        start == null ||
        end == null ||
        c.today.isAfter(end) ||
        !(c.status.confidence == PredictionConfidence.medium ||
            c.status.confidence == PredictionConfidence.high)) {
      return null;
    }
    return InsightOpening('P12', {'start_date': start, 'end_date': end});
  }

  /// Sad or anxious logged on 4 or more days, spread over at least 14 days,
  /// in the last 4 weeks.
  bool lowMoodLingers() {
    final days = [
      for (final log in c.logs)
        if (!log.date.isAfter(c.today) &&
            c.today.differenceInDays(log.date) < 28 &&
            (log.symptoms.contains('Sad') || log.symptoms.contains('Anxious')))
          log.date,
    ]..sort();
    return days.length >= 4 && days.last.differenceInDays(days.first) >= 13;
  }

  /// Recorded cycles with a mood change logged in their last 7 days. Only
  /// cycles with entries in those days count.
  int premenstrualMoodCycles() {
    var matching = 0;
    for (final cy in recentCompleted) {
      final logged = [
        for (var k = 0; k < 7; k++)
          if (byDay[cy.end!.addDays(-k)] case final log?) log,
      ];
      if (logged.any(
        (l) => l.symptoms.any(HerInsightPicker._moodSymptoms.contains),
      )) {
        matching++;
      }
    }
    return matching;
  }

  /// Under 6 hours of sleep logged on at least 2 of the last 3 nights.
  bool shortNights() {
    var short = 0;
    for (var k = 0; k < 3; k++) {
      final hours = byDay[c.today.addDays(-k)]?.sleepHours;
      if (hours != null && hours < 6) short++;
    }
    return short >= 2;
  }
}
