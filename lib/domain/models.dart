import 'day_key.dart';
import 'enums.dart';

/// Everything the user recorded for a single day.
class DayLog {
  const DayLog({
    required this.date,
    this.flow = FlowIntensity.none,
    this.symptoms = const <String>{},
    this.energy,
    this.sleepHours,
    this.basalTemperature,
    this.weightKg,
    this.notes,
    this.isPeriodStartOverride,
  });

  final DayKey date;
  final FlowIntensity flow;
  final Set<String> symptoms;

  /// 1 (drained) .. 5 (energised). Null = not logged.
  final int? energy;
  final double? sleepHours;
  final double? basalTemperature;
  final double? weightKg;
  final String? notes;

  /// Lets the user correct the engine when it guessed the cycle start wrong.
  /// `true` forces a start, `false` suppresses one, `null` = auto.
  final bool? isPeriodStartOverride;

  bool get isEmpty =>
      flow == FlowIntensity.none &&
      symptoms.isEmpty &&
      energy == null &&
      sleepHours == null &&
      basalTemperature == null &&
      weightKg == null &&
      (notes == null || notes!.isEmpty) &&
      isPeriodStartOverride == null;

  DayLog copyWith({
    FlowIntensity? flow,
    Set<String>? symptoms,
    int? energy,
    double? sleepHours,
    double? basalTemperature,
    double? weightKg,
    String? notes,
    bool? isPeriodStartOverride,
    bool clearEnergy = false,
    bool clearOverride = false,
  }) {
    return DayLog(
      date: date,
      flow: flow ?? this.flow,
      symptoms: symptoms ?? this.symptoms,
      energy: clearEnergy ? null : (energy ?? this.energy),
      sleepHours: sleepHours ?? this.sleepHours,
      basalTemperature: basalTemperature ?? this.basalTemperature,
      weightKg: weightKg ?? this.weightKg,
      notes: notes ?? this.notes,
      isPeriodStartOverride: clearOverride
          ? null
          : (isPeriodStartOverride ?? this.isPeriodStartOverride),
    );
  }

  Map<String, Object?> toMap() => {
        'date': date.iso,
        'flow': flow.name,
        'symptoms': symptoms.join('|'),
        'energy': energy,
        'sleep_hours': sleepHours,
        'bbt': basalTemperature,
        'weight_kg': weightKg,
        'notes': notes,
        'period_start_override': isPeriodStartOverride == null
            ? null
            : (isPeriodStartOverride! ? 1 : 0),
      };

  static DayLog fromMap(Map<String, Object?> m) {
    final raw = (m['symptoms'] as String?) ?? '';
    final override = m['period_start_override'] as int?;
    return DayLog(
      date: DayKey.parse(m['date'] as String),
      flow: FlowIntensity.fromName(m['flow'] as String?),
      symptoms:
          raw.isEmpty ? const <String>{} : raw.split('|').toSet(),
      energy: m['energy'] as int?,
      sleepHours: (m['sleep_hours'] as num?)?.toDouble(),
      basalTemperature: (m['bbt'] as num?)?.toDouble(),
      weightKg: (m['weight_kg'] as num?)?.toDouble(),
      notes: m['notes'] as String?,
      isPeriodStartOverride: override == null ? null : override == 1,
    );
  }
}

/// One completed or in-progress menstrual cycle.
class Cycle {
  const Cycle({
    required this.start,
    this.end,
    required this.periodLength,
  });

  /// First day of bleeding.
  final DayKey start;

  /// Last day before the next cycle started. Null while the cycle is running.
  final DayKey? end;

  /// Number of consecutive bleeding days at the start of this cycle.
  final int periodLength;

  bool get isComplete => end != null;

  /// Length in days, or null if still running.
  int? get length => end == null ? null : end!.differenceInDays(start) + 1;

  bool contains(DayKey day) {
    if (day.isBefore(start)) return false;
    if (end == null) return true;
    return !day.isAfter(end!);
  }
}

/// A read-only projection of the current cycle, safe to share with a partner.
class PartnerSnapshot {
  const PartnerSnapshot({
    this.dayOfCycle,
    this.phase,
    required this.daysUntilNextPeriod,
    this.sharedSymptoms = const <String>[],
    this.energy,
    this.nextPhase,
    this.daysUntilNextPhase,
    this.jokes = false,
  });

  /// Whether his tips may be funny today. Only the yes or no is shared,
  /// never the reason.
  final bool jokes;

  /// Both null unless she shares her cycle phase.
  final int? dayOfCycle;
  final CyclePhase? phase;

  /// The phase that starts next and how many days away it is. Null whenever
  /// saying so would reveal something she has not chosen to share.
  final CyclePhase? nextPhase;
  final int? daysUntilNextPhase;

  /// -999 when she does not share it.
  final int daysUntilNextPeriod;
  final List<String> sharedSymptoms;
  final int? energy;
}
