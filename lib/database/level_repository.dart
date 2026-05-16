import 'package:flutter/foundation.dart';

import '../models/level.dart';
import 'app_database.dart';

class LevelRepository extends ChangeNotifier {
  LevelRepository(this._appDb);

  final AppDatabase _appDb;
  final Map<int, List<Level>> _cache = {};

  List<Level> levelsForProjectSync(int projectId) =>
      List.unmodifiable(_cache[projectId] ?? const []);

  Future<void> load(int projectId) async {
    final rows = await _appDb.raw.query(
      'levels',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'ordinal ASC, elevation_mm ASC',
    );
    _cache[projectId] = rows.map(Level.fromRow).toList();
    notifyListeners();
  }

  Future<Level> ensureDefaultLevel(int projectId) async {
    await load(projectId);
    final levels = _cache[projectId] ?? [];
    if (levels.isNotEmpty) return levels.first;

    final id = await _appDb.raw.insert('levels', {
      'project_id': projectId,
      'name': 'Ground Floor',
      'elevation_mm': 0.0,
      'ordinal': 0,
      'is_auto_named': 1,
    });
    await load(projectId);
    return _cache[projectId]!.firstWhere((l) => l.id == id);
  }


}
