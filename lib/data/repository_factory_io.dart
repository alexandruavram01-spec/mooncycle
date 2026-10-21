import 'local_database.dart';
import 'log_repository.dart';
import 'sqlite_log_repository.dart';

/// Android, iOS and desktop: real SQLite.
Future<LogRepository> createLogRepository() async {
  final db = await LocalDatabase.open();
  return SqliteLogRepository(db);
}
