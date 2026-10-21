import 'cycle_engine.dart';
import 'day_key.dart';
import 'enums.dart';
import 'insights.dart';
import 'models.dart';
import 'profile.dart';

/// Insight cards for her: which card to show today, and why.
///
/// Everything here runs on her phone; nothing she logs is sent anywhere to
/// choose a card. The wording lives in `lib/l10n/her_insights_en_gb.dart`;
/// this file only decides which card, by code. The reviewed rules are in
/// `content/her-insights-en-GB.txt`.

/// The order cards are chosen in, most important first.
enum InsightTier {
  /// A warning sign she reported, such as bleeding outside a period.
  safety,

  /// Something she logged today (or yesterday, for evening loggers).
  logged,

  /// A pattern in her own history.
  history,

  /// General information when nothing more relevant applies.
  education,
}

/// Days before a card may come back, from the reviewed pack.
const insightCooldownDays = <String, int>{
  'I01': 21, 'I02': 60, 'I03': 100, 'I05': 40, 'I06': 70, 'I07': 120,
  'I08': 365, 'I09': 35, 'I10': 40, 'I11': 60, 'I12': 40, 'I13': 35,
  'I14': 75, 'I16': 30, 'I17': 30, 'I18': 35, 'I19': 35, 'I20': 21,
  'I21': 21, 'I22': 30, 'I23': 28, 'I24': 60, 'I25': 90, 'I26': 120,
  'I27': 80, 'I28': 100, 'I29': 120, 'I30': 28, 'NEW01': 120, 'NEW02': 120,
  'H01': 21, 'H02': 60, 'H03': 45,
};

/// What `symptom` holds for a heavy flow, which is not a symptom name.
const heavyFlow = 'heavy flow';

/// A card that could be shown today, and what it answers.
class InsightCandidate {
  const InsightCandidate(
    this.id,
    this.tier, {
    this.symptom,
    this.pattern,
    this.cycleLengths = const [],
    this.energyHigh,
    this.energyLow,
  });

  final String id;
  final InsightTier tier;

  /// The logged symptom it answers ("Headache"), or [heavyFlow].
  final String? symptom;

  /// For H01: the pattern it describes.
  final PhasePattern? pattern;

  /// For H02: her last cycle lengths, oldest first.
  final List<int> cycleLengths;

  /// For H03: the phases where her logged energy was highest and lowest.
  final CyclePhase? energyHigh;
  final CyclePhase? energyLow;
}

/// Everything the picker looks at. Built on her phone.
class InsightContext {
  const InsightContext({
    required this.today,
    required this.status,
    required this.logs,
    required this.profile,
    this.screeningReminders = false,
    this.engine = const CycleEngine(),
  });

  final DayKey today;
  final CycleStatus status;
  final List<DayLog> logs;
  final UserProfile profile;

  /// She turned on cervical screening reminders in Settings.
  final bool screeningReminders;
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

/// What the phone remembers about cards: when each was last shown, which
/// she marked "not relevant", and today's choice so it stays put all day.
class InsightMemory {
  const InsightMemory({
    this.lastShown = const {},
    this.notRelevant = const {},
    this.pickDay,
    this.pickIds = const [],
    this.pickTier,
    this.dismissed = const {},
    this.screeningReminders = false,
  });

  final Map<String, DayKey> lastShown;
  final Set<String> notRelevant;

  /// Today's choice. [pickTier] is the tier of its first card, or
  /// `InsightTier.values.length` when there was nothing to show.
  final DayKey? pickDay;
  final List<String> pickIds;
  final int? pickTier;

  /// Cards she closed on [pickDay].
  final Set<String> dismissed;
  final bool screeningReminders;

  InsightMemory copyWith({
    Map<String, DayKey>? lastShown,
    Set<String>? notRelevant,
    DayKey? pickDay,
    List<String>? pickIds,
    int? pickTier,
    Set<String>? dismissed,
    bool? screeningReminders,
  }) =>
      InsightMemory(
        lastShown: lastShown ?? this.lastShown,
        notRelevant: notRelevant ?? this.notRelevant,
        pickDay: pickDay ?? this.pickDay,
        pickIds: pickIds ?? this.pickIds,
        pickTier: pickTier ?? this.pickTier,
        dismissed: dismissed ?? this.dismissed,
        screeningReminders: screeningReminders ?? this.screeningReminders,
      );

  Map<String, Object?> toJson() => {
        'lastShown': {
          for (final MapEntry(:key, :value) in lastShown.entries)
            key: value.iso,
        },
        'notRelevant': notRelevant.toList(),
        'pickDay': pickDay?.iso,
        'pickIds': pickIds,
        'pickTier': pickTier,
        'dismissed': dismissed.toList(),
        'screeningReminders': screeningReminders,
      };

  static InsightMemory fromJson(Map<String, Object?> j) {
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    final shown = j['lastShown'];
    final day = j['pickDay'];
    return InsightMemory(
      lastShown: {
        if (shown is Map)
          for (final MapEntry(:key, :value) in shown.entries)
            if (key is String && value is String) key: DayKey.parse(value),
      },
      notRelevant: strings(j['notRelevant']).toSet(),
      pickDay: day is String ? DayKey.parse(day) : null,
      pickIds: strings(j['pickIds']),
      pickTier: j['pickTier'] as int?,
      dismissed: strings(j['dismissed']).toSet(),
      screeningReminders: j['screeningReminders'] as bool? ?? false,
    );
  }
}

class HerInsightPicker {
  const HerInsightPicker({this.insights = const InsightsEngine()});

  final InsightsEngine insights;

  static const _moodSymptoms = ['Sad', 'Anxious', 'Irritable', 'Sensitive'];

  /// Every card that applies today, in each tier's preferred order. A card
  /// can appear in more than one tier; [choose] keeps its most important.
  List<InsightCandidate> candidates(InsightContext c) {
    if (!c.supportedJourney || !c.status.hasData) return const [];
    final out = <InsightCandidate>[];
    void add(String id, InsightTier tier, {String? symptom}) =>
        out.add(InsightCandidate(id, tier, symptom: symptom));

    final cycles = c.engine.deriveCycles(c.logs);
    if (cycles.isEmpty) return const [];
    final byDay = {for (final log in c.logs) log.date: log};
    final current = cycles.last;
    final phase = c.status.phase;
    final unsuitable = c.estimatesUnsuitable;
    final completed = cycles.where((cy) => cy.isComplete).toList();
    final untilPeriod = c.status.daysUntilNextPeriod;

    // ---- 1. Safety: only on something she reported. Bleeding on a day
    // that is not part of a logged period, after her first period.
    for (final day in [c.today, c.today.addDays(-1)]) {
      final log = byDay[day];
      if (log != null &&
          log.flow.isBleeding &&
          cycles.first.start.isBefore(day) &&
          !_inPeriod(day, cycles)) {
        add('I21', InsightTier.safety);
        break;
      }
    }

    // ---- 2. What she logged: today, or yesterday if today is empty.
    final todayLog = byDay[c.today];
    final recent = todayLog != null &&
            (todayLog.symptoms.isNotEmpty ||
                todayLog.flow != FlowIntensity.none)
        ? todayLog
        : byDay[c.today.addDays(-1)];
    final heavyThisCycle = c.logs.any(
      (l) => !l.date.isBefore(current.start) && l.flow == FlowIntensity.heavy,
    );
    if (recent != null) {
      final s = recent.symptoms;
      final nearPeriod = phase == CyclePhase.menstrual ||
          (untilPeriod != null && untilPeriod >= 0 && untilPeriod <= 2);
      if (s.contains('Cramps') && nearPeriod) {
        add('I01', InsightTier.logged, symptom: 'Cramps');
      }
      if (recent.flow == FlowIntensity.heavy) {
        add('I02', InsightTier.logged, symptom: heavyFlow);
      }
      if (s.contains('Fatigue')) {
        add(heavyThisCycle ? 'I05' : 'I19', InsightTier.logged,
            symptom: 'Fatigue');
      }
      if (s.contains('Ovulation pain')) {
        add('I10', InsightTier.logged, symptom: 'Ovulation pain');
      }
      if (s.contains('Headache')) {
        add('I16', InsightTier.logged, symptom: 'Headache');
      }
      if (s.contains('Bloating')) {
        add('I17', InsightTier.logged, symptom: 'Bloating');
      }
      if (s.contains('Breast tenderness')) {
        add('I18', InsightTier.logged, symptom: 'Breast tenderness');
      }
      for (final mood in _moodSymptoms) {
        if (s.contains(mood)) {
          add('I20', InsightTier.logged, symptom: mood);
          break;
        }
      }
      if (c.conceiving && s.contains('Egg white')) {
        add('I30', InsightTier.logged, symptom: 'Egg white');
      }
    }

    // ---- 3. Her own history.
    if (!unsuitable &&
        c.status.isLate &&
        untilPeriod != null &&
        untilPeriod <= -3 &&
        (c.status.confidence == PredictionConfidence.medium ||
            c.status.confidence == PredictionConfidence.high)) {
      // Neither card ever says she is pregnant.
      add(c.conceiving ? 'I23' : 'I22', InsightTier.history);
    }

    final run = _bleedingRun(current, byDay);
    if (run >= 8 &&
        c.today.differenceInDays(current.start.addDays(run - 1)) <= 2) {
      add('I24', InsightTier.history);
    }

    final lengths = [
      for (final cy in completed)
        if (cy.length! <= c.engine.maxPlausibleCycleLength) cy.length!,
    ];
    if (!unsuitable && _cyclesLookDifferent(lengths)) {
      add('I25', InsightTier.history);
    }

    var fatigueWithHeavy = 0;
    for (final cy in cycles) {
      final days = c.logs.where((l) => cy.contains(l.date));
      if (days.any((l) => l.flow == FlowIntensity.heavy) &&
          days.any((l) => l.symptoms.contains('Fatigue'))) {
        fatigueWithHeavy++;
      }
    }
    if (fatigueWithHeavy >= 2) add('I05', InsightTier.history);

    // A symptom that keeps coming back at this point of her cycle.
    for (final pattern in insights.phasePatterns(c.logs)) {
      if (pattern.phase == phase && _patternGroups.contains(pattern.symptom)) {
        out.add(InsightCandidate('H01', InsightTier.history, pattern: pattern));
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
        out.add(
          InsightCandidate('H02', InsightTier.history, cycleLengths: last),
        );
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
            InsightTier.history,
            energyHigh: energy.first.phase,
            energyLow: energy.last.phase,
          ),
        );
      }
    }

    // ---- 4. Cycle education.
    const edu = InsightTier.education;
    switch (phase) {
      case CyclePhase.menstrual:
        add('I01', edu);
        add('I02', edu);
        add('I03', edu);
      case CyclePhase.follicular:
        add('I06', edu);
        if (!unsuitable) add('I07', edu);
        if (c.profile.showFertileDays && !c.conceiving && !unsuitable) {
          add('I11', edu);
        }
      case CyclePhase.ovulatory:
        if (c.fertilityOn && !unsuitable) {
          add('I09', edu);
          add('I10', edu);
        }
        if (c.profile.showFertileDays && !c.conceiving && !unsuitable) {
          add('I11', edu);
        }
      case CyclePhase.luteal:
        add('I12', edu);
        add('I13', edu);
        if (completed.length >= 2) add('I14', edu);
    }
    if (c.conceiving) {
      add('I26', edu);
      add('I27', edu);
      add('I29', edu);
      if (c.profile.tryingSince == 'year') add('I28', edu);
    }
    if (completed.isNotEmpty && !unsuitable) add('NEW01', edu);
    if (c.hormonalContraception) add('NEW02', edu);
    if (c.screeningReminders) add('I08', edu);

    return out;
  }

  /// Today's cards from [candidates], following the rules agreed for her:
  /// the most important tier wins; one card a day, plus a second only when
  /// the first is a safety card; the choice stays put all day unless
  /// something more important comes up; cooldowns, "not relevant" and
  /// closed cards are respected.
  ///
  /// Returns the cards and, when it changed, the memory to save.
  static (List<InsightCandidate>, InsightMemory?) choose(
    List<InsightCandidate> candidates,
    InsightMemory memory,
    DayKey today,
  ) {
    final sameDay = memory.pickDay == today;
    final dismissed = sameDay ? memory.dismissed : const <String>{};

    // One entry per card, from the most important tier it qualifies for,
    // remembering the order it was listed in for ties.
    final best = <String, (InsightCandidate, int)>{};
    for (final (index, candidate) in candidates.indexed) {
      final previous = best[candidate.id];
      if (previous == null || candidate.tier.index < previous.$1.tier.index) {
        best[candidate.id] = (candidate, previous?.$2 ?? index);
      }
    }

    bool rested(String id) {
      final last = memory.lastShown[id];
      if (last == null || last == today) return true;
      return today.differenceInDays(last) >= (insightCooldownDays[id] ?? 30);
    }

    final usable = [
      for (final entry in best.values)
        if (!memory.notRelevant.contains(entry.$1.id) &&
            !dismissed.contains(entry.$1.id) &&
            rested(entry.$1.id))
          entry,
    ]..sort((a, b) {
        final tier = a.$1.tier.index.compareTo(b.$1.tier.index);
        if (tier != 0) return tier;
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
    final freshTier =
        fresh.isEmpty ? InsightTier.values.length : fresh.first.tier.index;

    if (sameDay) {
      final storedTier = memory.pickTier ?? InsightTier.values.length;
      if (freshTier >= storedTier) {
        // Keep this morning's choice, minus anything closed or no longer
        // applying (for example a symptom she removed from her log).
        final byId = {for (final (candidate, _) in usable) candidate.id: candidate};
        return (
          [
            for (final id in memory.pickIds)
              if (byId[id] case final candidate?) candidate,
          ],
          null,
        );
      }
    }

    return (
      fresh,
      memory.copyWith(
        lastShown: {
          ...memory.lastShown,
          for (final candidate in fresh) candidate.id: today,
        },
        pickDay: today,
        pickIds: [for (final candidate in fresh) candidate.id],
        pickTier: freshTier,
        dismissed: dismissed,
      ),
    );
  }

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
