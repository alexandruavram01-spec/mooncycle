import 'cycle_engine.dart';
import 'day_key.dart';
import 'enums.dart';
import 'models.dart';

/// A detected pattern, phrased for display.
class Pattern {
  const Pattern({
    required this.title,
    required this.detail,
    required this.strength,
  });

  final String title;
  final String detail;

  /// 0..1 — how consistently the pattern held.
  final double strength;
}

/// A symptom that keeps turning up in the same phase: logged in [hits] of
/// her last [cycles] completed cycles.
class PhasePattern {
  const PhasePattern({
    required this.symptom,
    required this.phase,
    required this.hits,
    required this.cycles,
  });

  final String symptom;
  final CyclePhase phase;
  final int hits;
  final int cycles;

  double get strength => hits / cycles;
}

class PhaseAverages {
  const PhaseAverages({
    required this.phase,
    required this.averageEnergy,
    required this.topSymptoms,
    required this.sampleDays,
    this.energySamples = 0,
  });

  final CyclePhase phase;
  final double? averageEnergy;
  final List<String> topSymptoms;
  final int sampleDays;

  /// How many days with an energy level the average is based on.
  final int energySamples;
}

/// Derives human-readable patterns from logged history. Pure Dart.
class InsightsEngine {
  const InsightsEngine({this.engine = const CycleEngine()});

  final CycleEngine engine;

  /// Minimum number of cycles before we claim a pattern exists at all.
  static const int minCyclesForPattern = 3;

  Map<DayKey, CyclePhase> phaseMap(List<DayLog> logs) {
    final cycles = engine.deriveCycles(logs);
    final result = <DayKey, CyclePhase>{};
    if (cycles.isEmpty) return result;
    final cycleLength = engine.typicalCycleLength(cycles);

    for (final cycle in cycles) {
      final end = cycle.end ?? cycle.start.addDays(cycleLength - 1);
      final nextStart = end.addDays(1);
      final ovulation = nextStart.addDays(-engine.lutealPhaseLength);
      var cursor = cycle.start;
      while (!cursor.isAfter(end)) {
        result[cursor] = engine.phaseFor(
          day: cursor,
          cycleStart: cycle.start,
          periodLength: cycle.periodLength,
          ovulation: ovulation,
        );
        cursor = cursor.addDays(1);
      }
    }
    return result;
  }

  List<PhaseAverages> byPhase(List<DayLog> logs) {
    final phases = phaseMap(logs);
    final energy = <CyclePhase, List<int>>{};
    final symptoms = <CyclePhase, Map<String, int>>{};
    final days = <CyclePhase, int>{};

    for (final log in logs) {
      final phase = phases[log.date];
      if (phase == null) continue;
      days[phase] = (days[phase] ?? 0) + 1;
      if (log.energy != null) {
        (energy[phase] ??= <int>[]).add(log.energy!);
      }
      final counts = symptoms[phase] ??= <String, int>{};
      for (final s in log.symptoms) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }

    return CyclePhase.values.map((phase) {
      final e = energy[phase] ?? const <int>[];
      final counts = symptoms[phase] ?? const <String, int>{};
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return PhaseAverages(
        phase: phase,
        averageEnergy:
            e.isEmpty ? null : e.reduce((a, b) => a + b) / e.length,
        topSymptoms: sorted.take(3).map((e) => e.key).toList(),
        sampleDays: days[phase] ?? 0,
        energySamples: e.length,
      );
    }).toList();
  }

  /// Symptoms that reliably show up in the same phase across cycles.
  List<Pattern> detectPatterns(List<DayLog> logs) => [
        for (final p in phasePatterns(logs).take(8))
          Pattern(
            title: '${p.symptom} in your ${p.phase.label.toLowerCase()} phase',
            detail: 'Logged in ${p.hits} of ${p.cycles} recent cycles.',
            strength: p.strength,
          ),
      ];

  /// The same patterns as [detectPatterns], as data, strongest first.
  List<PhasePattern> phasePatterns(List<DayLog> logs) {
    final cycles = engine.deriveCycles(logs);
    final completed = cycles.where((c) => c.isComplete).toList();
    if (completed.length < minCyclesForPattern) return const [];

    final phases = phaseMap(logs);
    final logsByDate = {for (final l in logs) l.date: l};

    // symptom -> phase -> number of cycles it appeared in
    final hits = <String, Map<CyclePhase, Set<int>>>{};
    for (var i = 0; i < completed.length; i++) {
      final cycle = completed[i];
      var cursor = cycle.start;
      while (!cursor.isAfter(cycle.end!)) {
        final log = logsByDate[cursor];
        final phase = phases[cursor];
        if (log != null && phase != null) {
          for (final s in log.symptoms) {
            ((hits[s] ??= {})[phase] ??= <int>{}).add(i);
          }
        }
        cursor = cursor.addDays(1);
      }
    }

    final patterns = <PhasePattern>[];
    hits.forEach((symptom, byPhase) {
      byPhase.forEach((phase, cycleIndices) {
        final pattern = PhasePattern(
          symptom: symptom,
          phase: phase,
          hits: cycleIndices.length,
          cycles: completed.length,
        );
        if (pattern.strength >= 0.6) patterns.add(pattern);
      });
    });

    patterns.sort((a, b) => b.strength.compareTo(a.strength));
    return patterns;
  }

  /// Cycle length history for charting, oldest first.
  List<int> cycleLengthHistory(List<DayLog> logs) => engine
      .deriveCycles(logs)
      .where((c) => c.isComplete)
      .map((c) => c.length!)
      .toList();
}
