import 'package:health/health.dart';

import '../domain/day_key.dart';
import '../domain/models.dart';

/// Reads wearable data through Android Health Connect, which aggregates
/// Fitbit, Garmin, Samsung Health, Oura and Whoop behind one API — so we
/// integrate once instead of maintaining an OAuth client per vendor.
class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();

  final Health _health;

  /// HRV is deliberately absent: the RMSSD type is not exposed by every
  /// version of the `health` package, and nothing in the app consumes it yet.
  /// Add it back once there is a feature that needs it.
  static const List<HealthDataType> readTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.STEPS,
    HealthDataType.WEIGHT,
  ];

  Future<void> configure() => _health.configure();

  Future<bool> isAvailable() async {
    final status = await _health.getHealthConnectSdkStatus();
    return status == HealthConnectSdkStatus.sdkAvailable;
  }

  Future<bool> requestPermissions() async {
    final permissions =
        readTypes.map((_) => HealthDataAccess.READ).toList(growable: false);
    return _health.requestAuthorization(readTypes, permissions: permissions);
  }

  /// Pulls wearable metrics for a date range and folds them into day logs.
  ///
  /// Wearable data never overwrites something the user typed — manual entries
  /// win, because a user correcting their own temperature is more trustworthy
  /// than a sensor estimate.
  Future<Map<DayKey, WearableDay>> fetchRange({
    required DayKey from,
    required DayKey to,
  }) async {
    final points = await _health.getHealthDataFromTypes(
      types: readTypes,
      startTime: from.toDateTime(),
      endTime: to.addDays(1).toDateTime(),
    );

    final byDay = <DayKey, _Accumulator>{};
    for (final point in points) {
      final day = DayKey.fromDateTime(point.dateFrom);
      final acc = byDay[day] ??= _Accumulator();
      final value = point.value;
      if (value is! NumericHealthValue) continue;
      final n = value.numericValue.toDouble();

      switch (point.type) {
        case HealthDataType.SLEEP_ASLEEP:
          // Health Connect reports sleep as minute-long segments.
          acc.sleepMinutes += point.dateTo.difference(point.dateFrom).inMinutes;
        case HealthDataType.RESTING_HEART_RATE:
          acc.restingHr.add(n);
        case HealthDataType.BODY_TEMPERATURE:
          acc.temperature.add(n);
        case HealthDataType.STEPS:
          acc.steps += n;
        case HealthDataType.WEIGHT:
          acc.weight.add(n);
        default:
          break;
      }
    }

    return byDay.map((day, acc) => MapEntry(day, acc.build(day)));
  }

  /// Merges wearable readings into an existing log without clobbering
  /// anything the user entered by hand.
  static DayLog merge(DayLog existing, WearableDay wearable) {
    return existing.copyWith(
      sleepHours: existing.sleepHours ?? wearable.sleepHours,
      basalTemperature: existing.basalTemperature ?? wearable.temperature,
      weightKg: existing.weightKg ?? wearable.weightKg,
    );
  }
}

class WearableDay {
  const WearableDay({
    required this.date,
    this.sleepHours,
    this.restingHeartRate,
    this.hrv,
    this.temperature,
    this.steps,
    this.weightKg,
  });

  final DayKey date;
  final double? sleepHours;
  final double? restingHeartRate;
  final double? hrv;
  final double? temperature;
  final double? steps;
  final double? weightKg;
}

class _Accumulator {
  int sleepMinutes = 0;
  double steps = 0;
  final List<double> restingHr = [];
  final List<double> hrv = [];
  final List<double> temperature = [];
  final List<double> weight = [];

  double? _avg(List<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  WearableDay build(DayKey date) => WearableDay(
        date: date,
        sleepHours: sleepMinutes == 0 ? null : sleepMinutes / 60.0,
        restingHeartRate: _avg(restingHr),
        hrv: _avg(hrv),
        temperature: _avg(temperature),
        steps: steps == 0 ? null : steps,
        weightKg: _avg(weight),
      );
}
