import 'local_database.dart';
import 'log_repository.dart';
import 'sqlite_log_repository.dart';

/// Android, iOS and desktop: real SQLite, one file per account.
Future<LogRepository> createLogRepository(String accountId) async {
  final db = await LocalDatabase.open(accountId);
  return SqliteLogRepository(db);
}

/// Erases one account's logs, file and all, when the account is deleted.
Future<void> deleteLogStore(String accountId) =>
    LocalDatabase.deleteFor(accountId);
