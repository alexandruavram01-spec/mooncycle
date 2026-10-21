import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/domain/cycle_engine.dart';
import 'package:mooncycle/domain/day_key.dart';
import 'package:mooncycle/domain/enums.dart';
import 'package:mooncycle/domain/models.dart';

/// Builds a period of [days] consecutive bleeding days starting at [start].
List<DayLog> period(DayKey start, {int days = 5}) => List.generate(
      days,
      (i) => DayLog(
        date: start.addDays(i),
        flow: i == 0 || i == 1 ? FlowIntensity.heavy : FlowIntensity.light,
      ),
    );

void main() {
  const engine = CycleEngine();

  group('DayKey', () {
    test('day arithmetic is unaffected by DST transitions', () {
      // Europe/Bucharest springs forward on 26 March 2023.
      const before = DayKey(2023, 3, 25);
      final after = before.addDays(2);
      expect(after, const DayKey(2023, 3, 27));
      expect(after.differenceInDays(before), 2);
    });

    test('crosses month and year boundaries', () {
      expect(const DayKey(2023, 12, 30).addDays(3), const DayKey(2024, 1, 2));
      expect(const DayKey(2024, 2, 28).addDays(1), const DayKey(2024, 2, 29));
    });

    test('round-trips through ISO', () {
      const d = DayKey(2024, 7, 4);
      expect(DayKey.parse(d.iso), d);
      expect(d.iso, '2024-07-04');
    });
  });

  group('deriveCycles', () {
    test('groups consecutive bleeding days into one cycle', () {
      final logs = [
        ...period(const DayKey(2024, 1, 1)),
        ...period(const DayKey(2024, 1, 29)),
      ];
      final cycles = engine.deriveCycles(logs);

      expect(cycles.length, 2);
      expect(cycles.first.start, const DayKey(2024, 1, 1));
      expect(cycles.first.periodLength, 5);
      expect(cycles.first.length, 28);
      expect(cycles.last.isComplete, isFalse);
    });

    test('a one-day break does not end the period', () {
      final logs = [
        DayLog(date: const DayKey(2024, 1, 1), flow: FlowIntensity.heavy),
        DayLog(date: const DayKey(2024, 1, 2), flow: FlowIntensity.medium),
        // 3 Jan not logged
        DayLog(date: const DayKey(2024, 1, 4), flow: FlowIntensity.light),
      ];
      expect(engine.deriveCycles(logs).single.periodLength, 4);
    });

    test('mid-cycle spotting does not start a new cycle', () {
      final logs = [
        ...period(const DayKey(2024, 1, 1)),
        DayLog(date: const DayKey(2024, 1, 14), flow: FlowIntensity.spotting),
        ...period(const DayKey(2024, 1, 29)),
      ];
      final cycles = engine.deriveCycles(logs);

      expect(cycles.length, 2);
      expect(cycles.map((c) => c.start),
          [const DayKey(2024, 1, 1), const DayKey(2024, 1, 29)]);
    });

    test('a manual override forces a start the heuristic would reject', () {
      final logs = [
        ...period(const DayKey(2024, 1, 1)),
        DayLog(
          date: const DayKey(2024, 1, 12),
          flow: FlowIntensity.medium,
          isPeriodStartOverride: true,
        ),
      ];
      final cycles = engine.deriveCycles(logs);

      expect(cycles.length, 2);
      expect(cycles.last.start, const DayKey(2024, 1, 12));
    });

    test('a suppressed start is ignored even when bleeding is heavy', () {
      final logs = [
        ...period(const DayKey(2024, 1, 1)),
        DayLog(
          date: const DayKey(2024, 2, 1),
          flow: FlowIntensity.heavy,
          isPeriodStartOverride: false,
        ),
      ];
      expect(engine.deriveCycles(logs).length, 1);
    });
  });

  group('statistics', () {
    test('uses the median so one outlier cycle does not skew predictions', () {
      // 28, 28, 28, 45 (a month of missed logging), 28
      final starts = [
        const DayKey(2024, 1, 1),
        const DayKey(2024, 1, 29),
        const DayKey(2024, 2, 26),
        const DayKey(2024, 3, 25),
        const DayKey(2024, 5, 9), // 45 days later
        const DayKey(2024, 6, 6),
      ];
      final logs = starts.expand((s) => period(s)).toList();
      final cycles = engine.deriveCycles(logs);

      expect(engine.recentCycleLengths(cycles), [28, 28, 28, 45, 28]);
      expect(engine.typicalCycleLength(cycles), 28);
    });

    test('variation grows with irregular cycles', () {
      final regular = engine.deriveCycles([
        ...period(const DayKey(2024, 1, 1)),
        ...period(const DayKey(2024, 1, 29)),
        ...period(const DayKey(2024, 2, 26)),
        ...period(const DayKey(2024, 3, 25)),
      ]);
      final irregular = engine.deriveCycles([
        ...period(const DayKey(2024, 1, 1)),
        ...period(const DayKey(2024, 1, 22)), // 21
        ...period(const DayKey(2024, 2, 26)), // 35
        ...period(const DayKey(2024, 3, 20)), // 23
      ]);

      expect(engine.cycleLengthVariation(regular), lessThan(0.01));
      expect(engine.cycleLengthVariation(irregular), greaterThan(5));
      expect(engine.confidenceFor(regular), PredictionConfidence.high);
      expect(engine.confidenceFor(irregular), PredictionConfidence.low);
    });

    test('confidence is none with no completed cycles', () {
      final cycles = engine.deriveCycles(period(const DayKey(2024, 1, 1)));
      expect(engine.confidenceFor(cycles), PredictionConfidence.none);
    });
  });

  group('status and prediction', () {
    final logs = [
      ...period(const DayKey(2024, 1, 1)),
      ...period(const DayKey(2024, 1, 29)),
      ...period(const DayKey(2024, 2, 26)),
    ];

    test('reports the correct day of cycle', () {
      final status = engine.status(logs, today: const DayKey(2024, 3, 1));
      expect(status.currentCycleStart, const DayKey(2024, 2, 26));
      expect(status.dayOfCycle, 5);
    });

    test('predicts the next period one typical cycle after the last start', () {
      final status = engine.status(logs, today: const DayKey(2024, 3, 1));
      expect(status.predictedNextStart, const DayKey(2024, 3, 25));
      expect(status.daysUntilNextPeriod, 24);
      expect(status.isLate, isFalse);
    });

    test('ovulation is counted back from the next period, not forward '
        'from the last', () {
      final status = engine.status(logs, today: const DayKey(2024, 3, 1));
      expect(status.predictedOvulation, const DayKey(2024, 3, 11));
      expect(status.fertileWindowStart, const DayKey(2024, 3, 6));
      expect(status.fertileWindowEnd, const DayKey(2024, 3, 12));
    });

    test('reports a late period rather than a date in the past', () {
      final status = engine.status(logs, today: const DayKey(2024, 3, 28));
      expect(status.predictedNextStart, const DayKey(2024, 3, 25));
      expect(status.isLate, isTrue);
      expect(status.daysUntilNextPeriod, -3);
    });

    test('keeps projecting forward when a cycle is long overdue', () {
      final status = engine.status(logs, today: const DayKey(2024, 5, 10));
      final next = status.predictedNextStart!;
      expect(next.isAfter(const DayKey(2024, 5, 10)), isTrue);
      // 26 Feb + 28*3 = 20 May
      expect(next, const DayKey(2024, 5, 20));
    });

    test('handles an empty log without throwing', () {
      final status = engine.status(const [], today: const DayKey(2024, 3, 1));
      expect(status.hasData, isFalse);
      expect(status.dayOfCycle, 0);
      expect(status.typicalCycleLength, 28);
      expect(status.confidence, PredictionConfidence.none);
    });
  });

  group('predictedStarts', () {
    final logs = [
      ...period(const DayKey(2024, 1, 1)),
      ...period(const DayKey(2024, 1, 29)),
      ...period(const DayKey(2024, 2, 26)),
    ];

    test('agrees with status about the next period, including when late', () {
      const today = DayKey(2024, 3, 28);
      final cycles = engine.deriveCycles(logs);
      final starts = engine.predictedStarts(cycles, today, count: 3);
      final status = engine.status(logs, today: today);

      expect(starts.first, status.predictedNextStart);
      expect(starts, [
        const DayKey(2024, 3, 25),
        const DayKey(2024, 4, 22),
        const DayKey(2024, 5, 20),
      ]);
    });

    test('returns nothing when there is no history', () {
      expect(engine.predictedStarts(const [], DayKey.today()), isEmpty);
    });
  });

  group('phaseFor', () {
    const start = DayKey(2024, 3, 1);
    const ovulation = DayKey(2024, 3, 15);

    CyclePhase phaseOn(int dayOfCycle) => engine.phaseFor(
          day: start.addDays(dayOfCycle - 1),
          cycleStart: start,
          periodLength: 5,
          ovulation: ovulation,
        );

    test('bleeding days are menstrual', () {
      expect(phaseOn(1), CyclePhase.menstrual);
      expect(phaseOn(5), CyclePhase.menstrual);
    });

    test('the days after the period are follicular', () {
      expect(phaseOn(6), CyclePhase.follicular);
      expect(phaseOn(13), CyclePhase.follicular);
    });

    test('ovulation day and its neighbours are ovulatory', () {
      expect(phaseOn(14), CyclePhase.ovulatory);
      expect(phaseOn(15), CyclePhase.ovulatory);
      expect(phaseOn(16), CyclePhase.ovulatory);
    });

    test('everything after ovulation is luteal', () {
      expect(phaseOn(17), CyclePhase.luteal);
      expect(phaseOn(28), CyclePhase.luteal);
    });
  });
}
