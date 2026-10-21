import 'dart:math' as math;

import 'day_key.dart';
import 'enums.dart';
import 'models.dart';

enum PredictionConfidence { none, low, medium, high }

/// Everything the UI needs to describe "where am I right now".
class CycleStatus {
  const CycleStatus({
    required this.today,
    required this.dayOfCycle,
    required this.phase,
    required this.currentCycleStart,
    required this.predictedNextStart,
    required this.predictedOvulation,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
    required this.typicalCycleLength,
    required this.typicalPeriodLength,
    required this.cycleLengthVariation,
    required this.confidence,
    required this.completedCycles,
  });

  final DayKey today;

  /// 1-based. 0 when nothing has ever been logged.
  final int dayOfCycle;
  final CyclePhase phase;
  final DayKey? currentCycleStart;
  final DayKey? predictedNextStart;
  final DayKey? predictedOvulation;
  final DayKey? fertileWindowStart;
  final DayKey? fertileWindowEnd;
  final int typicalCycleLength;
  final int typicalPeriodLength;

  /// Standard deviation of recent cycle lengths, in days.
  final double cycleLengthVariation;
  final PredictionConfidence confidence;
  final int completedCycles;

  bool get hasData => currentCycleStart != null;

  /// Negative when the period is late.
  int? get daysUntilNextPeriod =>
      predictedNextStart?.differenceInDays(today);

  bool get isLate {
    final d = daysUntilNextPeriod;
    return d != null && d < 0;
  }

  bool get isInFertileWindow {
    if (fertileWindowStart == null || fertileWindowEnd == null) return false;
    return !today.isBefore(fertileWindowStart!) &&
        !today.isAfter(fertileWindowEnd!);
  }
}

/// Pure, deterministic cycle maths. No Flutter, no IO, no clock access except
/// what is passed in — so it can be exhaustively unit tested.
class CycleEngine {
  const CycleEngine({
    this.defaultCycleLength = 28,
    this.defaultPeriodLength = 5,
    this.lutealPhaseLength = 14,
    this.maxGapWithinPeriod = 1,
    this.minCycleLength = 15,
    this.maxPlausibleCycleLength = 60,
    this.historyWindow = 6,
    this.lateGraceDays = 10,
  });

  /// Used before any cycle has been observed.
  final int defaultCycleLength;
  final int defaultPeriodLength;

  /// Luteal phase is the stable part of the cycle (~14d), so ovulation is
  /// predicted backwards from the next period rather than forwards from the
  /// last one. This is what makes predictions hold up for irregular cycles.
  final int lutealPhaseLength;

  /// A one-day break in bleeding does not end the period.
  final int maxGapWithinPeriod;

  /// Bleeding sooner than this is treated as mid-cycle spotting, not a new
  /// cycle.
  final int minCycleLength;

  /// Cycles longer than this are excluded from averages (missed logging).
  final int maxPlausibleCycleLength;

  /// How many recent cycles feed the prediction.
  final int historyWindow;

  /// How long a predicted date is allowed to sit in the past before we assume
  /// the period was simply not logged and project the next one instead.
  ///
  /// Without this, a period that is one day late would jump the prediction a
  /// full cycle ahead — the app would say "next period in 27 days" exactly
  /// when the user most wants to see "1 day late".
  final int lateGraceDays;

  // ---------------------------------------------------------------- cycles

  /// Reconstructs cycles from raw day logs.
  List<Cycle> deriveCycles(Iterable<DayLog> logs) {
    final bleedingDays = <DayKey>[];
    final forcedStarts = <DayKey>{};
    final suppressedStarts = <DayKey>{};

    for (final log in logs) {
      if (log.flow.isBleeding) bleedingDays.add(log.date);
      if (log.isPeriodStartOverride == true) forcedStarts.add(log.date);
      if (log.isPeriodStartOverride == false) suppressedStarts.add(log.date);
    }
    for (final forced in forcedStarts) {
      if (!bleedingDays.contains(forced)) bleedingDays.add(forced);
    }
    if (bleedingDays.isEmpty) return const [];
    bleedingDays.sort();

    final starts = <DayKey>[];
    for (final day in bleedingDays) {
      if (suppressedStarts.contains(day)) continue;
      if (starts.isEmpty) {
        starts.add(day);
        continue;
      }
      final sinceLastStart = day.differenceInDays(starts.last);
      if (forcedStarts.contains(day)) {
        if (sinceLastStart > 0) starts.add(day);
      } else if (sinceLastStart >= minCycleLength) {
        starts.add(day);
      }
    }

    final cycles = <Cycle>[];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final nextStart = i + 1 < starts.length ? starts[i + 1] : null;
      cycles.add(
        Cycle(
          start: start,
          end: nextStart?.addDays(-1),
          periodLength: _periodLengthFrom(start, bleedingDays, nextStart),
        ),
      );
    }
    return cycles;
  }

  int _periodLengthFrom(DayKey start, List<DayKey> bleeding, DayKey? nextStart) {
    final set = bleeding.toSet();
    var length = 0;
    var cursor = start;
    var gap = 0;
    while (true) {
      if (nextStart != null && !cursor.isBefore(nextStart)) break;
      if (set.contains(cursor)) {
        length = cursor.differenceInDays(start) + 1;
        gap = 0;
      } else {
        gap++;
        if (gap > maxGapWithinPeriod) break;
      }
      cursor = cursor.addDays(1);
    }
    return math.max(length, 1);
  }

  // ------------------------------------------------------------ statistics

  List<int> recentCycleLengths(List<Cycle> cycles) {
    final lengths = cycles
        .where((c) => c.isComplete)
        .map((c) => c.length!)
        .where((l) => l >= minCycleLength && l <= maxPlausibleCycleLength)
        .toList();
    if (lengths.length <= historyWindow) return lengths;
    return lengths.sublist(lengths.length - historyWindow);
  }

  /// Median is used rather than mean: one forgotten month shouldn't drag the
  /// prediction by a week.
  int typicalCycleLength(List<Cycle> cycles) {
    final lengths = recentCycleLengths(cycles);
    if (lengths.isEmpty) return defaultCycleLength;
    return _median(lengths).round();
  }

  int typicalPeriodLength(List<Cycle> cycles) {
    final lengths = cycles
        .where((c) => c.isComplete)
        .map((c) => c.periodLength)
        .toList();
    if (lengths.isEmpty) return defaultPeriodLength;
    final recent = lengths.length <= historyWindow
        ? lengths
        : lengths.sublist(lengths.length - historyWindow);
    return _median(recent).round();
  }

  double cycleLengthVariation(List<Cycle> cycles) {
    final lengths = recentCycleLengths(cycles);
    if (lengths.length < 2) return 0;
    final mean = lengths.reduce((a, b) => a + b) / lengths.length;
    final variance = lengths
            .map((l) => (l - mean) * (l - mean))
            .reduce((a, b) => a + b) /
        (lengths.length - 1);
    return math.sqrt(variance);
  }

  PredictionConfidence confidenceFor(List<Cycle> cycles) {
    final n = recentCycleLengths(cycles).length;
    if (n == 0) return PredictionConfidence.none;
    if (n < 2) return PredictionConfidence.low;
    final sd = cycleLengthVariation(cycles);
    if (sd <= 2.0 && n >= 3) return PredictionConfidence.high;
    if (sd <= 4.5) return PredictionConfidence.medium;
    return PredictionConfidence.low;
  }

  // ------------------------------------------------------------ prediction

  /// Next [count] predicted period start dates, continuing past the last
  /// logged cycle.
  List<DayKey> predictedStarts(List<Cycle> cycles, DayKey from,
      {int count = 6}) {
    if (cycles.isEmpty) return const [];
    final cycleLength = math.max(typicalCycleLength(cycles), 1);
    var cursor = cycles.last.start.addDays(cycleLength);

    // Same grace rule as [status], so the calendar and the home screen never
    // disagree about when the next period is due.
    while (from.differenceInDays(cursor) > lateGraceDays) {
      cursor = cursor.addDays(cycleLength);
    }
    return List<DayKey>.generate(count, (i) => cursor.addDays(i * cycleLength));
  }

  CycleStatus status(List<DayLog> logs, {DayKey? today}) {
    final now = today ?? DayKey.today();
    final cycles = deriveCycles(logs);
    final cycleLength = typicalCycleLength(cycles);
    final periodLength = typicalPeriodLength(cycles);

    if (cycles.isEmpty) {
      return CycleStatus(
        today: now,
        dayOfCycle: 0,
        phase: CyclePhase.follicular,
        currentCycleStart: null,
        predictedNextStart: null,
        predictedOvulation: null,
        fertileWindowStart: null,
        fertileWindowEnd: null,
        typicalCycleLength: cycleLength,
        typicalPeriodLength: periodLength,
        cycleLengthVariation: 0,
        confidence: PredictionConfidence.none,
        completedCycles: 0,
      );
    }

    // The cycle that contains today; if today predates all logs, fall back to
    // the first cycle so the UI still renders something coherent.
    var current = cycles.last;
    for (final c in cycles) {
      if (c.contains(now)) {
        current = c;
        break;
      }
    }
    final start = current.start;
    final dayOfCycle = now.differenceInDays(start) + 1;

    var nextStart = start.addDays(cycleLength);
    // A recently-missed date stays put so the UI can say "n days late"; only
    // once it is well overdue do we assume a cycle went unlogged.
    if (now.differenceInDays(nextStart) > lateGraceDays) {
      nextStart = _rollForward(start, cycleLength, now);
    }

    final ovulation = nextStart.addDays(-lutealPhaseLength);
    final fertileStart = ovulation.addDays(-5);
    final fertileEnd = ovulation.addDays(1);

    return CycleStatus(
      today: now,
      dayOfCycle: math.max(dayOfCycle, 1),
      phase: phaseFor(
        day: now,
        cycleStart: start,
        periodLength: current.periodLength,
        ovulation: ovulation,
      ),
      currentCycleStart: start,
      predictedNextStart: nextStart,
      predictedOvulation: ovulation,
      fertileWindowStart: fertileStart,
      fertileWindowEnd: fertileEnd,
      typicalCycleLength: cycleLength,
      typicalPeriodLength: periodLength,
      cycleLengthVariation: cycleLengthVariation(cycles),
      confidence: confidenceFor(cycles),
      completedCycles: cycles.where((c) => c.isComplete).length,
    );
  }

  DayKey _rollForward(DayKey start, int cycleLength, DayKey now) {
    var cursor = start;
    // Guard against a pathological cycleLength of 0.
    final step = math.max(cycleLength, 1);
    while (!cursor.isAfter(now)) {
      cursor = cursor.addDays(step);
    }
    return cursor;
  }

  CyclePhase phaseFor({
    required DayKey day,
    required DayKey cycleStart,
    required int periodLength,
    required DayKey ovulation,
  }) {
    final dayOfCycle = day.differenceInDays(cycleStart) + 1;
    if (dayOfCycle <= periodLength) return CyclePhase.menstrual;
    final fromOvulation = day.differenceInDays(ovulation);
    if (fromOvulation >= -1 && fromOvulation <= 1) return CyclePhase.ovulatory;
    if (fromOvulation < -1) return CyclePhase.follicular;
    return CyclePhase.luteal;
  }

  static double _median(List<int> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid].toDouble();
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
