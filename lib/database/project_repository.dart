import 'package:flutter/foundation.dart';

import '../models/project.dart';
import 'app_database.dart';

class ProjectRepository extends ChangeNotifier {
  ProjectRepository(this._appDb);

  final AppDatabase _appDb;
  List<Project> _projects = [];
  List<Project> get projects => List.unmodifiable(_projects);

  Future<void> load() async {
    final rows = await _appDb.raw.query(
      'projects',
      orderBy: 'created_at DESC',
    );
    _projects = rows.map(Project.fromRow).toList();
    notifyListeners();
  }

  Future<int?> insert(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final id = await _appDb.raw.insert('projects', {
      'name': trimmed,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await load();
    return id;
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _appDb.raw.update(
      'projects',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [id],
    );
    await load();
  }

  Future<void> delete(int id) async {
    await _appDb.raw.delete('projects', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Project? byId(int id) {
    try {
      return _projects.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
