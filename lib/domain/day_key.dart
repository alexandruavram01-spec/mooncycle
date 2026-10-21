/// A calendar day with no time component and no timezone drift.
///
/// Cycle maths must never be done on `DateTime` differences directly: DST
/// transitions make `difference(...).inDays` off by one twice a year, which
/// silently corrupts predictions. Everything downstream uses [DayKey].
class DayKey implements Comparable<DayKey> {
  const DayKey(this.year, this.month, this.day);

  factory DayKey.fromDateTime(DateTime dt) => DayKey(dt.year, dt.month, dt.day);

  factory DayKey.today() => DayKey.fromDateTime(DateTime.now());

  /// Parses `yyyy-MM-dd`.
  factory DayKey.parse(String iso) {
    final parts = iso.split('-');
    return DayKey(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime toDateTime() => DateTime(year, month, day);

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Days since 1970-01-01, computed in UTC so DST can't interfere.
  int get epochDay => DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  DayKey addDays(int n) {
    final d = DateTime.utc(year, month, day).add(Duration(days: n));
    return DayKey(d.year, d.month, d.day);
  }

  /// Signed day count from [other] to `this`.
  int differenceInDays(DayKey other) => epochDay - other.epochDay;

  bool isBefore(DayKey other) => epochDay < other.epochDay;
  bool isAfter(DayKey other) => epochDay > other.epochDay;

  int get weekdayMondayFirst => toDateTime().weekday; // 1 = Mon .. 7 = Sun

  @override
  int compareTo(DayKey other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is DayKey &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}
