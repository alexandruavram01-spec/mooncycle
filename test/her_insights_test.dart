import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/domain/cycle_engine.dart';
import 'package:mooncycle/domain/day_key.dart';
import 'package:mooncycle/domain/enums.dart';
import 'package:mooncycle/domain/her_insights.dart';
import 'package:mooncycle/domain/models.dart';
import 'package:mooncycle/domain/profile.dart';
import 'package:mooncycle/l10n/app_language.dart';
import 'package:mooncycle/l10n/her_insights.dart';

void main() {
  const engine = CycleEngine();
  const picker = HerInsightPicker();

  List<DayLog> period(DayKey start) => List.generate(
        5,
        (i) => DayLog(date: start.addDays(i), flow: FlowIntensity.medium),
      );

  // Two complete 28-day cycles, then a third that started on 26 February:
  // 10 March is mid-cycle, 20 March is before the next period.
  final history = [
    ...period(const DayKey(2024, 1, 1)),
    ...period(const DayKey(2024, 1, 29)),
    ...period(const DayKey(2024, 2, 26)),
  ];

  InsightContext context(
    DayKey today, {
    List<DayLog> extra = const [],
    UserProfile profile = const UserProfile(),
  }) {
    final logs = [...history, ...extra];
    return InsightContext(
      today: today,
      status: engine.status(logs, today: today),
      logs: logs,
      profile: profile,
    );
  }

  List<String> ids(InsightContext c) =>
      [for (final candidate in picker.candidates(c)) candidate.id];

  const midCycle = DayKey(2024, 3, 10);
  const beforePeriod = DayKey(2024, 3, 20);

  test('bleeding outside a period is a safety card, shown with what she logged',
      () {
    final c = context(
      midCycle,
      extra: [
        DayLog(
          date: midCycle,
          flow: FlowIntensity.spotting,
          symptoms: const {'Headache'},
        ),
      ],
    );
    final (picks, _) = HerInsightPicker.choose(
      picker.candidates(c),
      const InsightMemory(),
      midCycle,
    );
    expect(picks.map((p) => p.id), ['I21', 'I16']);
    expect(picks.first.tier, InsightTier.safety);
  });

  test('bleeding during a period, or her first period, is not a warning', () {
    expect(ids(context(const DayKey(2024, 2, 28))), isNot(contains('I21')));
    final first = period(const DayKey(2024, 1, 1));
    final c = InsightContext(
      today: const DayKey(2024, 1, 2),
      status: engine.status(first, today: const DayKey(2024, 1, 2)),
      logs: first,
      profile: const UserProfile(),
    );
    expect(ids(c), isNot(contains('I21')));
  });

  test('one card on an ordinary day', () {
    final (picks, _) = HerInsightPicker.choose(
      picker.candidates(context(beforePeriod)),
      const InsightMemory(),
      beforePeriod,
    );
    expect(picks, hasLength(1));
    expect(picks.single.tier, InsightTier.education);
  });

  test('what she logged comes before general information', () {
    final c = context(
      beforePeriod,
      extra: [DayLog(date: beforePeriod, symptoms: const {'Bloating'})],
    );
    final (picks, _) =
        HerInsightPicker.choose(picker.candidates(c), const InsightMemory(), beforePeriod);
    expect(picks.single.id, 'I17');
    expect(picks.single.symptom, 'Bloating');
  });

  test("today's card stays put unless something more important comes up", () {
    final (morning, saved) = HerInsightPicker.choose(
      picker.candidates(context(beforePeriod)),
      const InsightMemory(),
      beforePeriod,
    );
    expect(saved, isNotNull);

    // Nothing new: same card, nothing to save.
    final (again, unchanged) = HerInsightPicker.choose(
      picker.candidates(context(beforePeriod)),
      saved!,
      beforePeriod,
    );
    expect(again.map((p) => p.id), morning.map((p) => p.id));
    expect(unchanged, isNull);

    // She logs bloating: that card takes over.
    final logged = context(
      beforePeriod,
      extra: [DayLog(date: beforePeriod, symptoms: const {'Bloating'})],
    );
    final (later, _) =
        HerInsightPicker.choose(picker.candidates(logged), saved, beforePeriod);
    expect(later.single.id, 'I17');
  });

  test('cooldowns and "not relevant" are respected', () {
    final candidates = picker.candidates(context(beforePeriod));
    final first = HerInsightPicker.choose(
      candidates,
      const InsightMemory(),
      beforePeriod,
    ).$1.single.id;

    final (afterCooldown, _) = HerInsightPicker.choose(
      candidates,
      InsightMemory(lastShown: {first: beforePeriod.addDays(-5)}),
      beforePeriod,
    );
    expect(afterCooldown.single.id, isNot(first));

    final (afterHiding, _) = HerInsightPicker.choose(
      candidates,
      InsightMemory(notRelevant: {first}),
      beforePeriod,
    );
    expect(afterHiding.single.id, isNot(first));
  });

  test('a closed card stays closed for the day, with nothing in its place', () {
    final (picks, saved) = HerInsightPicker.choose(
      picker.candidates(context(beforePeriod)),
      const InsightMemory(),
      beforePeriod,
    );
    final closed = saved!.copyWith(dismissed: {picks.single.id});
    final (after, _) = HerInsightPicker.choose(
      picker.candidates(context(beforePeriod)),
      closed,
      beforePeriod,
    );
    expect(after, isEmpty);
  });

  test('fertility cards need her opt-in; trying-to-conceive cards need the goal',
      () {
    expect(ids(context(midCycle)), isNot(contains('I09')));
    expect(ids(context(midCycle)), isNot(contains('I26')));

    final fertileDays = ids(
      context(midCycle, profile: const UserProfile(showFertileDays: true)),
    );
    expect(fertileDays, containsAll(['I09', 'I11']));

    final trying = ids(
      context(
        midCycle,
        profile: const UserProfile(
          journey: 'fertility',
          goal: TrackingGoal.conceive,
        ),
      ),
    );
    expect(trying, containsAll(['I09', 'I26']));
    expect(trying, isNot(contains('I11')));
  });

  test('hormonal contraception swaps cycle estimates for the contraception card',
      () {
    final found = ids(
      context(
        midCycle,
        profile: const UserProfile(
          showFertileDays: true,
          quizAnswers: {'affects': 'Hormonal contraception'},
        ),
      ),
    );
    expect(found, contains('NEW02'));
    expect(found, isNot(contains('I09')));
    expect(found, isNot(contains('NEW01')));
  });

  test('a symptom that keeps coming back becomes a pattern card', () {
    final logs = [
      ...history,
      ...period(const DayKey(2024, 3, 25)),
      for (final day in const [
        DayKey(2024, 1, 24),
        DayKey(2024, 2, 21),
        DayKey(2024, 3, 20),
      ])
        DayLog(date: day, symptoms: const {'Bloating'}),
    ];
    const today = DayKey(2024, 4, 17);
    final candidates = picker.candidates(
      InsightContext(
        today: today,
        status: engine.status(logs, today: today),
        logs: logs,
        profile: const UserProfile(),
      ),
    );
    final pattern = candidates.firstWhere((c) => c.id == 'H01').pattern!;
    expect(pattern.symptom, 'Bloating');
    expect(pattern.phase, CyclePhase.luteal);
    expect(pattern.hits, 3);
  });

  test('every card the picker can choose has wording in every language', () {
    for (final language in AppLanguage.values) {
      final texts = HerInsightTexts.of(language);
      for (final id in insightCooldownDays.keys) {
        expect(texts.cards[id], isNotNull, reason: '${language.code} $id');
        for (final source in texts.cards[id]!.sources) {
          expect(texts.sources[source], isNotNull, reason: '$id $source');
        }
      }
    }
  });
}
