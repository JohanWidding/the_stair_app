import 'dart:math' show sqrt;

import 'chain.dart';
import 'chain_geometry.dart';

/// Immutable 1-D walk model for a [StairChain].
///
/// The ganglinje is the continuous walking-line path through the entire
/// staircase with total length [totalMm].  It decomposes into alternating
/// straight sections (one per edge, length [rawEdgeMm[i]]) and fixed-length
/// corner arcs (one per interior node that is a real corner, length [arcMm[j]]).
///
/// The fitter moves the "knobs" — the boundaries between straight sections
/// and corner arcs — to distribute N steps as evenly as possible.
class Ganglinje {
  const Ganglinje({
    required this.rawEdgeMm,
    required this.isCorner,
    required this.arcMm,
    required this.tBackMm,
    required this.tFwdMm,
    required this.totalHeightMm,
    required this.mode,
  });

  /// Center-to-center distances for each straight flight (mm).
  final List<double>  rawEdgeMm;

  /// True if the interior node at index j is a real corner (turn > 1°).
  final List<bool>    isCorner;

  /// Walk arc length through each interior node (mm); 0.0 for non-corners.
  final List<double>  arcMm;

  /// Minimum back-landing size for each interior node (mm).
  final List<double>  tBackMm;

  /// Minimum forward-landing size for each interior node (mm).
  final List<double>  tFwdMm;

  /// Total floor-to-floor height (mm), used for Blondel N selection.
  final double        totalHeightMm;

  /// Ganglinje routing mode used to compute [arcMm].
  final GanglinjeMode mode;

  int    get nEdges          => rawEdgeMm.length;
  int    get nInterior       => arcMm.length;
  double get totalStraightMm => rawEdgeMm.fold(0.0, (s, v) => s + v);
  double get totalArcMm      => arcMm.fold(0.0, (s, v) => s + v);
  double get totalMm         => totalStraightMm + totalArcMm;

  /// Maximum straight-walk length for each edge given minimum landing constraints.
  List<double> get straightMaxMm => List<double>.generate(nEdges, (i) {
    final lH = (i > 0         && isCorner[i - 1]) ? tFwdMm[i - 1] : 0.0;
    final rH = (i < nInterior && isCorner[i])     ? tBackMm[i]    : 0.0;
    return (rawEdgeMm[i] - lH - rH).clamp(0.0, rawEdgeMm[i]);
  });

  // ── Factory ────────────────────────────────────────────────────────────────

  static const _cornerThreshDeg = 1.0;

  /// Compute the ganglinje from [chain] using zero-landing geometry.
  /// Returns null when the chain is invalid or has no edges.
  static Ganglinje? compute(StairChain chain) {
    if (!chain.isValid || chain.edgeCount == 0) return null;

    final mode      = chain.ganglinjeMode;
    final nEdges    = chain.edgeCount;
    final nInterior = nEdges - 1;

    final polys0 = ChainGeometry.compute(_zeroLandings(chain), 10.0);

    final rawEdgeMm = List<double>.generate(
        nEdges, (i) => _edgeMm(chain.nodes[i], chain.nodes[i + 1]));
    final isCorner  = [for (final nd in polys0.nodes) nd.turnAngleDeg > _cornerThreshDeg];
    final tBackMm   = [for (final nd in polys0.nodes) nd.transLenBackMm];
    final tFwdMm    = [for (final nd in polys0.nodes) nd.transLenFwdMm];
    final arcMm     = List<double>.generate(
        nInterior, (j) => isCorner[j] ? nodeMm(polys0.nodes[j], mode) : 0.0);

    return Ganglinje(
      rawEdgeMm:     rawEdgeMm,
      isCorner:      isCorner,
      arcMm:         arcMm,
      tBackMm:       tBackMm,
      tFwdMm:        tFwdMm,
      totalHeightMm: chain.totalHeightMm,
      mode:          mode,
    );
  }

  // ── Public helpers ─────────────────────────────────────────────────────────

  /// Walk length of [nd] along the ganglinje under [mode].
  static double nodeMm(NodeData nd, GanglinjeMode mode) {
    if (nd.ganglinjeStart == null || nd.ganglinjeEnd == null) return 0.0;
    final start = nd.ganglinjeStart!;
    final end   = nd.ganglinjeEnd!;
    if (mode == GanglinjeMode.middlewalk || nd.poly.length != 6) {
      return (end - start).distance;
    }
    final poly = nd.poly;
    switch (mode) {
      case GanglinjeMode.middlestrict:
        final via = (poly[1] + poly[4]) / 2;
        return (via - start).distance + (end - via).distance;
      case GanglinjeMode.innerstrict:
        // Inner wall EI→IMC→SI (shorter — inside of turn)
        return (poly[5] - start).distance +
               (poly[4] - poly[5]).distance +
               (poly[3] - poly[4]).distance +
               (end     - poly[3]).distance;
      case GanglinjeMode.outerstrict:
        // Outer wall EO→OMC→SO (longer — outside of turn)
        return (poly[0] - start).distance +
               (poly[1] - poly[0]).distance +
               (poly[2] - poly[1]).distance +
               (end     - poly[2]).distance;
      case GanglinjeMode.middlewalk:
        return (end - start).distance;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static StairChain _zeroLandings(StairChain chain) => chain.copyWith(
    nodes: [for (final nd in chain.nodes)
        nd.copyWith(landingMm: 0.0, landingOffset: 0.5)],
  );

  static double _edgeMm(ChainNode a, ChainNode b) {
    final dx = (b.gx - a.gx) * 10.0;
    final dy = (b.gy - a.gy) * 10.0;
    return sqrt(dx * dx + dy * dy);
  }
}
