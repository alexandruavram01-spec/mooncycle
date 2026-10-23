import 'dart:io' show File, Platform;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'account_storage.dart';

/// On-device SQLite store. Nothing here leaves the phone.
///
/// The schema is intentionally sync-friendly: every row carries `updated_at`
/// and `deleted`, so a future backend can do last-write-wins reconciliation
/// without a migration.
class LocalDatabase {
  LocalDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;
  static final Map<String, Future<LocalDatabase>> _opening = {};

  /// The database of the account [accountId]: one file each, so signing in
  /// as someone else never opens the previous person's logs.
  static Future<LocalDatabase> open(String accountId) {
    // On failure the cached future must be cleared, otherwise every later
    // attempt replays the same error and the app can never recover.
    return _opening[accountId] ??=
        _openInternal(accountId).onError((error, stack) {
      _opening.remove(accountId);
      Error.throwWithStackTrace(error!, stack);
    });
  }

  /// Closes and deletes the account's file, when the account is deleted.
  static Future<void> deleteFor(String accountId) async {
    final opening = _opening.remove(accountId);
    if (opening != null) {
      try {
        await (await opening).db.close();
      } catch (_) {
        // Already closed, or never opened.
      }
    }
    _initFactoryForDesktop();
    await deleteDatabase(await _pathFor(accountId));
  }

  static Future<String> _pathFor(String accountId) async =>
      p.join(await getDatabasesPath(), 'mooncycle-$accountId.db');

  /// Before 23 October 2026 every account on the phone shared one file,
  /// `mooncycle.db`. It becomes the file of the account that took the shared
  /// data (see AccountStorage.claimLegacy), the one that was signed in.
  static Future<void> _adoptLegacyFile(String accountId, String path) async {
    if (await AccountStorage.legacyOwner() != accountId) return;
    final legacy = p.join(await getDatabasesPath(), 'mooncycle.db');
    if (!File(legacy).existsSync() || File(path).existsSync()) return;
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final file = File('$legacy$suffix');
      if (file.existsSync()) await file.rename('$path$suffix');
    }
  }

  /// `sqflite` only ships a platform implementation for Android and iOS.
  /// On desktop the global `databaseFactory` is unset, so any query throws
  /// "databaseFactory not initialized" — point it at the FFI backend instead.
  /// Android is untouched by this.
  static void _initFactoryForDesktop() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<LocalDatabase> _openInternal(String accountId) async {
    _initFactoryForDesktop();
    final path = await _pathFor(accountId);
    await _adoptLegacyFile(accountId, path);
    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE day_logs (
            date TEXT PRIMARY KEY,
            flow TEXT NOT NULL DEFAULT 'none',
            symptoms TEXT NOT NULL DEFAULT '',
            energy INTEGER,
            sleep_hours REAL,
            bbt REAL,
            weight_kg REAL,
            notes TEXT,
            period_start_override INTEGER,
            source TEXT NOT NULL DEFAULT 'manual',
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await d.execute(
          'CREATE INDEX idx_day_logs_updated ON day_logs(updated_at)',
        );
      },
    );
    return LocalDatabase._(database);
  }
}
