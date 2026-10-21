import '../domain/day_key.dart';
import '../domain/models.dart';

/// Read/write access to day logs. The rest of the app never touches storage
/// directly, which is what lets the backing store differ per platform:
/// SQLite on Android, browser storage on web.
abstract class LogRepository {
  Future<List<DayLog>> all();
  Future<DayLog?> forDay(DayKey day);
  Future<void> save(DayLog log);
  Future<void> delete(DayKey day);
}

/// Used by tests and as a last-resort fallback.
class InMemoryLogRepository implements LogRepository {
  InMemoryLogRepository([List<DayLog> seed = const []]) {
    for (final l in seed) {
      _store[l.date] = l;
    }
  }

  final Map<DayKey, DayLog> _store = {};

  @override
  Future<List<DayLog>> all() async {
    final list = _store.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<DayLog?> forDay(DayKey day) async => _store[day];

  @override
  Future<void> save(DayLog log) async {
    // An emptied-out day is a delete, not a blank row — otherwise the cycle
    // engine would see phantom entries.
    if (log.isEmpty) {
      _store.remove(log.date);
      return;
    }
    _store[log.date] = log;
  }

  @override
  Future<void> delete(DayKey day) async => _store.remove(day);
}
