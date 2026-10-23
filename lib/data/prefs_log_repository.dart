import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/day_key.dart';
import '../domain/models.dart';
import 'account_storage.dart';
import 'log_repository.dart';

/// Storage for platforms with no SQLite implementation — currently web, where
/// this lands in browser local storage.
///
/// It reuses `DayLog.toMap` / `fromMap`, so the on-disk shape matches the
/// SQLite columns and data could be migrated between the two if web ever
/// became a real target rather than a preview surface.
class PrefsLogRepository implements LogRepository {
  PrefsLogRepository(this._prefs, String accountId)
      : _key = AccountStorage.key('mooncycle.logs.v1', accountId);

  /// One account's logs.
  final String _key;

  final SharedPreferences _prefs;

  static Future<PrefsLogRepository> open(String accountId) async =>
      PrefsLogRepository(await SharedPreferences.getInstance(), accountId);

  Map<String, DayLog> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as List<dynamic>;
    final result = <String, DayLog>{};
    for (final entry in decoded) {
      final map = (entry as Map).cast<String, Object?>();
      final log = DayLog.fromMap(map);
      result[log.date.iso] = log;
    }
    return result;
  }

  Future<void> _write(Map<String, DayLog> logs) async {
    await _prefs.setString(
      _key,
      jsonEncode(logs.values.map((l) => l.toMap()).toList()),
    );
  }

  @override
  Future<List<DayLog>> all() async {
    final list = _read().values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<DayLog?> forDay(DayKey day) async => _read()[day.iso];

  @override
  Future<void> save(DayLog log) async {
    final logs = _read();
    if (log.isEmpty) {
      logs.remove(log.date.iso);
    } else {
      logs[log.date.iso] = log;
    }
    await _write(logs);
  }

  @override
  Future<void> delete(DayKey day) async {
    final logs = _read()..remove(day.iso);
    await _write(logs);
  }
}
