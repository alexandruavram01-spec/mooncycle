import 'log_repository.dart';
import 'prefs_log_repository.dart';

/// Web: browser local storage. Good enough to click through the UI, and it
/// survives a page refresh, but it is not the shipping store.
Future<LogRepository> createLogRepository() async =>
    PrefsLogRepository.open();
