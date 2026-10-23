import 'account_storage.dart';
import 'log_repository.dart';
import 'prefs_log_repository.dart';

/// Web: browser local storage. Good enough to click through the UI, and it
/// survives a page refresh, but it is not the shipping store.
Future<LogRepository> createLogRepository(String accountId) async =>
    PrefsLogRepository.open(accountId);

/// Erases one account's logs, when the account is deleted.
Future<void> deleteLogStore(String accountId) =>
    AccountStorage.eraseKeys(accountId);
