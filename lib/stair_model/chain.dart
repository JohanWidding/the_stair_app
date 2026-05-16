import 'package:flutter/foundation.dart';

/// Where the ganglinje (walking line) runs through corner nodes.
enum GanglinjeMode {
  /// Straight midpoint-to-midpoint — cuts across the corner (current default).
  middlewalk,

  /// Centre path that goes around the corner via the midpoint of (omc + imc).
  middlestrict,

  /// Goes around the corner via the inner miter corner (imc).
  innerstrict,

  /// Goes around the corner via the outer miter corner (omc).
  outerstrict,
}

/// One straight flight segment.
class ChainEdge {
  const ChainEdge({
    required this.id,
    this.widthMm = 1000.0,
    this.heightMm = 2600.0,
    this.stepCount,
  });

  final String id;
  final double widthMm;
  final double heightMm;

  /// Null = auto-compute from heightMm using Blondel formula.
  final int? stepCount;

  ChainEdge copyWith({
    double? widthMm,
    double? heightMm,
    Object? stepCount = _unset,
  }) =>
      ChainEdge(
        id: id,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        stepCount: stepCount == _unset ? this.stepCount : stepCount as int?,
      );
}

const _unset = Object();

/// A waypoint in the chain — either an endpoint or a turning node.
/// Width is NOT stored here; it is derived from the adjacent edges.
class ChainNode {
  const ChainNode({
    required this.id,
    required this.gx,
    required this.gy,
    this.landingMm = 0.0,
    this.landingOffset = 0.5,
    this.stepCount,
  });

  final String id;
  final double gx, gy;         // grid coords (1 unit = 10 mm)
  final double landingMm;      // 0 = pure miter; >0 = rectangular landing depth
  /// How the grid point sits within the landing along the chain direction.
  /// 0.0 = anchor at incoming end (landing extends forward toward outgoing edge).
  /// 0.5 = centered (default — current behavior).
  /// 1.0 = anchor at outgoing end (landing extends backward toward incoming edge).
  final double landingOffset;  // 0.0–1.0

  /// Null = auto from turn angle (turnAngleDeg / 30, clamped 2–12).
  final int? stepCount;

  ChainNode copyWith({
    double? gx,
    double? gy,
    double? landingMm,
    double? landingOffset,
    Object? stepCount = _unset,
  }) =>
      ChainNode(
        id: id,
        gx: gx ?? this.gx,
        gy: gy ?? this.gy,
        landingMm: landingMm ?? this.landingMm,
        landingOffset: landingOffset ?? this.landingOffset,
        stepCount: stepCount == _unset ? this.stepCount : stepCount as int?,
      );
}

/// An ordered chain: nodes[i] connects to nodes[i+1] via edges[i].
/// Invariant: nodes.length == edges.length + 1, minimum 2 nodes.
/// nodes[0] and nodes[last] are the endpoints.
@immutable
class StairChain {
  const StairChain({
    required this.id,
    required this.nodes,
    required this.edges,
    this.totalHeightMm = 2600.0,
    this.ganglinjeMode = GanglinjeMode.middlewalk,
  }) : assert(nodes.length == edges.length + 1);

  final String id;
  final List<ChainNode> nodes;
  final List<ChainEdge> edges;

  /// Total floor-to-floor rise for the entire staircase (all segments combined).
  final double totalHeightMm;
  final GanglinjeMode ganglinjeMode;

  int get edgeCount => edges.length;
  int get nodeCount => nodes.length;
  bool get isValid => nodes.length >= 2;

  StairChain copyWith({
    List<ChainNode>? nodes,
    List<ChainEdge>? edges,
    double? totalHeightMm,
    GanglinjeMode? ganglinjeMode,
  }) =>
      StairChain(
        id: id,
        nodes: nodes ?? this.nodes,
        edges: edges ?? this.edges,
        totalHeightMm: totalHeightMm ?? this.totalHeightMm,
        ganglinjeMode: ganglinjeMode ?? this.ganglinjeMode,
      );

  /// Returns a new chain with [node] appended and [edge] connecting it.
  StairChain extended(ChainNode node, ChainEdge edge) => StairChain(
        id: id,
        nodes: [...nodes, node],
        edges: [...edges, edge],
        totalHeightMm: totalHeightMm,
        ganglinjeMode: ganglinjeMode,
      );

  /// Returns a new chain with [nodeIdx] moved to (gx, gy).
  StairChain withNodeMoved(int nodeIdx, double gx, double gy) {
    final updated = List<ChainNode>.of(nodes);
    updated[nodeIdx] = updated[nodeIdx].copyWith(gx: gx, gy: gy);
    return copyWith(nodes: updated);
  }
}
