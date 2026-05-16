class LeveledCache<T> {
  final Map<int, Map<int, List<T>>> _data = {};

  List<T> get(int projectId, int levelId) =>
      List.unmodifiable(_data[projectId]?[levelId] ?? const []);

  void put(int projectId, int levelId, List<T> items) =>
      (_data[projectId] ??= {})[levelId] = items;

  void clearProject(int projectId) => _data.remove(projectId);
}
