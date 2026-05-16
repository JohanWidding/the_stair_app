import 'dart:math' show acos, pi, sqrt;

import 'package:flutter/painting.dart';

import 'chain.dart';

class EdgeData {
  const EdgeData({
    required this.poly,
    required this.widthMm,
    required this.lengthMm,
    required this.ganglinjeStart,
    required this.ganglinjeEnd,
  });

  /// 4-point polygon [startLeft, endLeft, endRight, startRight] in pixel space.
  final List<Offset> poly;
  final double widthMm;
  final double lengthMm;

  /// Centre of start face and end face — the walking-line segment for this edge.
  final Offset ganglinjeStart;
  final Offset ganglinjeEnd;
}

class NodeData {
  const NodeData({
    required this.poly,
    required this.turnAngleDeg,
    required this.isRightTurn,
    required this.landingMm,
    this.ganglinjeStart,
    this.ganglinjeEnd,
    this.transLenBackMm = 0.0,
    this.transLenFwdMm  = 0.0,
    this.outerMiterCorner,
    this.innerMiterCorner,
  });

  /// 4- or 6-point polygon in pixel space; empty for straight nodes with no landing.
  final List<Offset> poly;

  /// Angle between the two adjacent edge directions (0 = straight, 90 = L-shape, 180 = U-turn).
  final double turnAngleDeg;

  /// True = clockwise turn (right) in screen space; false = counter-clockwise (left).
  final bool isRightTurn;
  final double landingMm;

  /// Walking-line entry and exit points for this node polygon.
  /// Null when the node has no polygon (straight node, no landing).
  final Offset? ganglinjeStart;
  final Offset? ganglinjeEnd;

  /// Minimum backL (mm) for this node's incoming edge to be in rectangular phase.
  /// Zero for straight nodes (no miter transition).
  final double transLenBackMm;

  /// Minimum fwdL (mm) for this node's outgoing edge to be in rectangular phase.
  final double transLenFwdMm;

  /// Raw outer and inner miter corners — used for ganglinje routing modes.
  /// Non-null only for corner nodes (poly.length == 6).
  final Offset? outerMiterCorner;
  final Offset? innerMiterCorner;
}

/// Computed 2D polygons and measurements for a StairChain, in pixel space.
class ChainPolygons {
  const ChainPolygons({
    required this.edges,
    required this.nodes,
  });

  /// One EdgeData per edge.
  final List<EdgeData> edges;

  /// One NodeData per interior node (nodes[1..nodeCount-2]).
  /// poly may be empty for straight nodes with no landing.
  final List<NodeData> nodes;
}

class ChainGeometry {
  static const _eps = 1e-6;

  static ChainPolygons compute(StairChain chain, double cellSize) {
    final n = chain.edgeCount;
    if (n == 0) return const ChainPolygons(edges: [], nodes: []);

    // ── Pixel positions ───────────────────────────────────────────────────
    final pts = [
      for (final nd in chain.nodes) Offset(nd.gx * cellSize, nd.gy * cellSize),
    ];

    // ── Unit directions, left normals, half-widths ────────────────────────
    final us  = List<Offset>.filled(n, Offset.zero);
    final ns  = List<Offset>.filled(n, Offset.zero);
    final hws = List<double>.filled(n, 0.0);

    for (var i = 0; i < n; i++) {
      final d = pts[i + 1] - pts[i];
      final dist = d.distance;
      us[i]  = dist > _eps ? d / dist : const Offset(1, 0);
      ns[i]  = Offset(-us[i].dy, us[i].dx); // 90° left
      hws[i] = chain.edges[i].widthMm / 10.0 * cellSize / 2.0;
    }

    // ── Per interior node: miter corners, cross, landing extents, transition lengths ──
    //
    // cross > 0  →  outer (overlap) boundary is the left  (+ns) side.
    // cross < 0  →  outer (overlap) boundary is the right (-ns) side.
    //
    // Behaviour as an edge corner is "dragged" toward the node (backL decreasing):
    //   • backL ≥ transLenBack  →  rectangular phase: both corners at the perpendicular face.
    //   • backL <  transLenBack  →  clamped phase: outer corner pinned to the outer miter corner;
    //                                inner corner keeps its flat perpendicular position.
    // This gives the "delayed join": edges stay as full rectangles as long as possible, then
    // only the overlap-side corner extends outward once the natural miter length is reached.
    final leftCorners  = List<Offset?>.filled(chain.nodeCount, null);
    final rightCorners = List<Offset?>.filled(chain.nodeCount, null);
    final crosses      = List<double>.filled(chain.nodeCount, 0.0);
    final backLs       = List<double>.filled(chain.nodeCount, 0.0);
    final fwdLs        = List<double>.filled(chain.nodeCount, 0.0);
    // Distance from node to outer miter corner projected along each adjacent edge direction.
    final transLenBack = List<double>.filled(chain.nodeCount, 0.0);
    final transLenFwd  = List<double>.filled(chain.nodeCount, 0.0);

    for (var j = 1; j < chain.nodeCount - 1; j++) {
      final prev = j - 1;
      final next = j;
      final c    = pts[j];
      final node = chain.nodes[j];

      leftCorners[j]  = _boundaryIntersect(c, us[prev], ns[prev], hws[prev],
                                              us[next], ns[next], hws[next], side:  1);
      rightCorners[j] = _boundaryIntersect(c, us[prev], ns[prev], hws[prev],
                                              us[next], ns[next], hws[next], side: -1);
      crosses[j] = _cross2(us[prev], us[next]);

      if (node.landingMm > 0) {
        final totalL = node.landingMm / 10.0 * cellSize;
        backLs[j] = totalL * node.landingOffset;
        fwdLs[j]  = totalL * (1.0 - node.landingOffset);
      }

      if (crosses[j].abs() >= _eps) {
        final omc  = crosses[j] > 0 ? leftCorners[j]! : rightCorners[j]!;
        final diff = omc - c;
        // dot(diff, -us[prev]) = distance backward along incoming edge to omc
        transLenBack[j] = -(diff.dx * us[prev].dx + diff.dy * us[prev].dy);
        // dot(diff,  us[next]) = distance forward along outgoing edge to omc
        transLenFwd[j]  =   diff.dx * us[next].dx + diff.dy * us[next].dy;
      }
    }

    // ── Edge polygons ─────────────────────────────────────────────────────
    // [startLeft, endLeft, endRight, startRight]
    // First/last node: flat perpendicular cap.
    // Interior node:
    //   rectangular phase (backL/fwdL ≥ transLen): perpendicular face, both corners move together.
    //   clamped phase (backL/fwdL < transLen): outer corner at miter corner, inner corner flat.
    final edgesData = <EdgeData>[];
    for (var i = 0; i < n; i++) {
      final nv    = ns[i];
      final hw    = hws[i];
      final sNode = i;
      final eNode = i + 1;

      // ── Start face ──
      final Offset startLeft, startRight;
      if (sNode == 0) {
        startLeft  = pts[0] + nv * hw;
        startRight = pts[0] - nv * hw;
      } else {
        final cr = crosses[sNode];
        final fL = fwdLs[sNode];
        if (cr.abs() < _eps) {
          // Straight: always rectangular.
          startLeft  = pts[sNode] + nv * hw + us[i] * fL;
          startRight = pts[sNode] - nv * hw + us[i] * fL;
        } else {
          final outerSign = cr > 0 ? 1.0 : -1.0;
          final omc       = cr > 0 ? leftCorners[sNode]! : rightCorners[sNode]!;
          final Offset sOuter, sInner;
          if (fL >= transLenFwd[sNode]) {
            sOuter = pts[sNode] + nv * hw * outerSign + us[i] * fL;
            sInner = pts[sNode] - nv * hw * outerSign + us[i] * fL;
          } else {
            sOuter = omc;
            sInner = pts[sNode] - nv * hw * outerSign + us[i] * fL;
          }
          if (cr > 0) { startLeft = sOuter; startRight = sInner; }
          else         { startLeft = sInner; startRight = sOuter; }
        }
      }

      // ── End face ──
      final Offset endLeft, endRight;
      if (eNode == chain.nodeCount - 1) {
        endLeft  = pts[eNode] + nv * hw;
        endRight = pts[eNode] - nv * hw;
      } else {
        final cr = crosses[eNode];
        final bL = backLs[eNode];
        if (cr.abs() < _eps) {
          endLeft  = pts[eNode] + nv * hw - us[i] * bL;
          endRight = pts[eNode] - nv * hw - us[i] * bL;
        } else {
          final outerSign = cr > 0 ? 1.0 : -1.0;
          final omc       = cr > 0 ? leftCorners[eNode]! : rightCorners[eNode]!;
          final Offset eOuter, eInner;
          if (bL >= transLenBack[eNode]) {
            eOuter = pts[eNode] + nv * hw * outerSign - us[i] * bL;
            eInner = pts[eNode] - nv * hw * outerSign - us[i] * bL;
          } else {
            eOuter = omc;
            eInner = pts[eNode] - nv * hw * outerSign - us[i] * bL;
          }
          if (cr > 0) { endLeft = eOuter; endRight = eInner; }
          else         { endLeft = eInner; endRight = eOuter; }
        }
      }

      final rawPxLen = (pts[eNode] - pts[sNode]).distance;
      final startSetback = sNode == 0 ? 0.0 : fwdLs[sNode];
      final endSetback   = eNode == chain.nodeCount - 1 ? 0.0 : backLs[eNode];
      final lengthMm = ((rawPxLen - startSetback - endSetback) / cellSize * 10.0)
          .clamp(0.0, double.infinity);
      edgesData.add(EdgeData(
        poly: [startLeft, endLeft, endRight, startRight],
        widthMm: chain.edges[i].widthMm,
        lengthMm: lengthMm,
        ganglinjeStart: (startLeft + startRight) / 2,
        ganglinjeEnd:   (endLeft   + endRight)   / 2,
      ));
    }

    // ── Node polygons ─────────────────────────────────────────────────────
    // 6-point polygon [endOuter, omc, startOuter, startInner, imc, endInner] covering
    // the full corner gap between the two adjacent edge faces.
    //
    // In the rectangular phase (backL/fwdL ≥ transLen) the outer path
    //   endOuter → omc → startOuter  is a bent path through the outer miter corner.
    // In the clamped phase endOuter = startOuter = omc, so the polygon degenerates to
    // [omc, startInner, imc, endInner] — a 4-point inner-gap filler.
    final nodesData = <NodeData>[];
    for (var j = 1; j < chain.nodeCount - 1; j++) {
      final cr = crosses[j];
      final dot = us[j - 1].dx * us[j].dx + us[j - 1].dy * us[j].dy;
      final turnAngleDeg = acos(dot.clamp(-1.0, 1.0)) * 180.0 / pi;
      final landingMm = chain.nodes[j].landingMm;

      if (cr.abs() < _eps) {
        // Straight node: no corner gap, but a landing creates a rectangular gap.
        if (landingMm <= 0) {
          nodesData.add(NodeData(poly: const [], turnAngleDeg: 0, isRightTurn: false, landingMm: 0));
          continue;
        }
        final prev = j - 1;
        final next = j;
        final bL = backLs[j];
        final fL = fwdLs[j];
        final p0 = pts[j] + ns[prev] * hws[prev] - us[prev] * bL;
        final p1 = pts[j] + ns[next] * hws[next] + us[next] * fL;
        final p2 = pts[j] - ns[next] * hws[next] + us[next] * fL;
        final p3 = pts[j] - ns[prev] * hws[prev] - us[prev] * bL;
        nodesData.add(NodeData(
          poly: [p0, p1, p2, p3],
          turnAngleDeg: 0,
          isRightTurn: false,
          landingMm: landingMm,
          ganglinjeStart: (p0 + p3) / 2,   // midpoint of back face
          ganglinjeEnd:   (p1 + p2) / 2,   // midpoint of front face
        ));
        continue;
      }

      final prev = j - 1;
      final next = j;
      final bL   = backLs[j];
      final fL   = fwdLs[j];
      final outerSign = cr > 0 ? 1.0 : -1.0;
      final omc  = cr > 0 ? leftCorners[j]! : rightCorners[j]!;
      final imc  = cr > 0 ? rightCorners[j]! : leftCorners[j]!;

      // End of incoming edge (edge prev = j−1) at node j
      final Offset endOuter, endInner;
      if (bL >= transLenBack[j]) {
        endOuter = pts[j] + ns[prev] * hws[prev] * outerSign - us[prev] * bL;
        endInner = pts[j] - ns[prev] * hws[prev] * outerSign - us[prev] * bL;
      } else {
        endOuter = omc;
        endInner = pts[j] - ns[prev] * hws[prev] * outerSign - us[prev] * bL;
      }

      // Start of outgoing edge (edge next = j) at node j
      final Offset startOuter, startInner;
      if (fL >= transLenFwd[j]) {
        startOuter = pts[j] + ns[next] * hws[next] * outerSign + us[next] * fL;
        startInner = pts[j] - ns[next] * hws[next] * outerSign + us[next] * fL;
      } else {
        startOuter = omc;
        startInner = pts[j] - ns[next] * hws[next] * outerSign + us[next] * fL;
      }

      // [EO(0), OMC(1), SO(2), SI(3), IMC(4), EI(5)]
      // ganglinjeStart = midpoint of incoming face (EO, EI)
      // ganglinjeEnd   = midpoint of outgoing face (SO, SI)
      nodesData.add(NodeData(
        poly: [endOuter, omc, startOuter, startInner, imc, endInner],
        turnAngleDeg:    turnAngleDeg,
        isRightTurn:     cr > 0,
        landingMm:       landingMm,
        ganglinjeStart:  (endOuter + endInner) / 2,
        ganglinjeEnd:    (startOuter + startInner) / 2,
        transLenBackMm:  transLenBack[j],
        transLenFwdMm:   transLenFwd[j],
        outerMiterCorner: omc,
        innerMiterCorner: imc,
      ));
    }

    return ChainPolygons(edges: edgesData, nodes: nodesData);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Intersection of the [side] boundary of the incoming edge (direction u1)
  /// with the [side] boundary of the outgoing edge (direction u2), both
  /// emanating from the shared corner [c].
  ///
  /// side = +1 → left boundary;  side = −1 → right boundary.
  static Offset _boundaryIntersect(
    Offset c,
    Offset u1, Offset n1, double hw1,
    Offset u2, Offset n2, double hw2, {
    required double side,
  }) {
    final p1 = c + n1 * (hw1 * side);
    final p2 = c + n2 * (hw2 * side);
    final d2 = -u2;
    final denom = _cross2(u1, d2);
    if (denom.abs() < _eps) return c + n1 * (hw1 * side);
    final t = _cross2(p2 - p1, d2) / denom;
    return p1 + u1 * t;
  }

  static double _cross2(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  // ignore: unused_element
  static double _dot2(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  // ignore: unused_element
  static double _len(Offset a) => sqrt(a.dx * a.dx + a.dy * a.dy);
}
