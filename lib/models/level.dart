class Level {
  const Level({
    required this.id,
    required this.projectId,
    required this.name,
    required this.elevationMm,
    required this.ordinal,
    this.isAutoNamed = false,
  });

  final int id;
  final int projectId;
  final String name;
  final double elevationMm;
  final int ordinal;
  final bool isAutoNamed;

  static Level fromRow(Map<String, Object?> map) {
    return Level(
      id: map['id']! as int,
      projectId: map['project_id']! as int,
      name: map['name']! as String,
      elevationMm: (map['elevation_mm'] as num).toDouble(),
      ordinal: map['ordinal']! as int,
      isAutoNamed: (map['is_auto_named'] as int? ?? 0) == 1,
    );
  }

  Level copyWith({
    String? name,
    double? elevationMm,
    int? ordinal,
    bool? isAutoNamed,
  }) {
    return Level(
      id: id,
      projectId: projectId,
      name: name ?? this.name,
      elevationMm: elevationMm ?? this.elevationMm,
      ordinal: ordinal ?? this.ordinal,
      isAutoNamed: isAutoNamed ?? this.isAutoNamed,
    );
  }
}
