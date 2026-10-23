import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../domain/day_key.dart';
import '../domain/models.dart';
import 'local_database.dart';
import 'log_repository.dart';

/// The real store, used on Android, iOS and desktop.
///
/// This file must never be imported from code that can be compiled for web —
/// `sqflite` has no web implementation. Go through `repository_factory.dart`.
class SqliteLogRepository implements LogRepository {
  SqliteLogRepository(this._database);

  final LocalDatabase _database;

  @override
  Future<List<DayLog>> all() async {
    final rows = await _database.db.query(
      'day_logs',
      where: 'deleted = 0',
      orderBy: 'date ASC',
    );
    return rows.map(DayLog.fromMap).toList();
  }

  @override
  Future<DayLog?> forDay(DayKey day) async {
    final rows = await _database.db.query(
      'day_logs',
      where: 'date = ? AND deleted = 0',
      whereArgs: [day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DayLog.fromMap(rows.first);
  }

  @override
  Future<void> save(DayLog log) async {
    if (log.isEmpty) {
      await delete(log.date);
      return;
    }
    await _database.db.insert(
      'day_logs',
      {
        ...log.toMap(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the day for good. (It used to be only marked as deleted, which
  /// kept what she had logged in the file.)
  @override
  Future<void> delete(DayKey day) async {
    await _database.db.delete(
      'day_logs',
      where: 'date = ?',
      whereArgs: [day.iso],
    );
  }
}
