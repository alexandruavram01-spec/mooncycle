import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// On-device SQLite store. Nothing here leaves the phone.
///
/// The schema is intentionally sync-friendly: every row carries `updated_at`
/// and `deleted`, so a future backend can do last-write-wins reconciliation
/// without a migration.
class LocalDatabase {
  LocalDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;
  static Future<LocalDatabase>? _opening;

  static Future<LocalDatabase> open() {
    // On failure the cached future must be cleared, otherwise every later
    // attempt replays the same error and the app can never recover.
    return _opening ??= _openInternal().onError((error, stack) {
      _opening = null;
      Error.throwWithStackTrace(error!, stack);
    });
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

  static Future<LocalDatabase> _openInternal() async {
    _initFactoryForDesktop();
    final dir = await getDatabasesPath();
    final database = await openDatabase(
      p.join(dir, 'mooncycle.db'),
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

  Future<void> close() async {
    await db.close();
    _opening = null;
  }
}
