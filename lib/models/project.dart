class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    this.floorHeightMm = 2800,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final double floorHeightMm;

  static Project fromRow(Map<String, Object?> map) => Project(
        id: map['id']! as int,
        name: map['name']! as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
        floorHeightMm:
            (map['floor_height_mm'] as num? ?? 2800).toDouble(),
      );

  Project copyWith({String? name, double? floorHeightMm}) => Project(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        floorHeightMm: floorHeightMm ?? this.floorHeightMm,
      );
}
