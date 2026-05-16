import 'sqlite_config_stub.dart'
    if (dart.library.io) 'sqlite_config_io.dart' as impl;

Future<void> configureSqliteIfNeeded() => impl.configureSqliteIfNeeded();
