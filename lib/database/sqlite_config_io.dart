import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> configureSqliteIfNeeded() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      final stableDir = p.join(home, '.local', 'share', 'the_stair_app');
      await Directory(stableDir).create(recursive: true);
      await databaseFactory.setDatabasesPath(stableDir);
    }
  }
}
