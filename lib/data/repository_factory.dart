/// Chooses a storage backend at compile time.
///
/// `sqflite` cannot be compiled for web at all — importing it from shared code
/// breaks the build before anything renders. A conditional export keeps the
/// SQLite code out of the web bundle entirely, rather than trying to branch on
/// `kIsWeb` at runtime, which would be too late.
export 'repository_factory_web.dart'
    if (dart.library.io) 'repository_factory_io.dart';
