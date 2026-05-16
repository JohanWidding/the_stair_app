import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/stair_math.dart';
import 'chain.dart';
import 'chain_geometry.dart';

class ChainPainter extends CustomPainter {
  ChainPainter({
    required this.chains,
    required this.draftChain,
    required this.draftCursor,
    this.dragGhostStart,
    required this.selectedChainId,
    required this.cellSize,
    required this.edgeFill,
    required this.nodeFill,
    required this.selectedFill,
    required this.stroke,
    required this.ghostStroke,
  });

  final List<StairChain> chains;
  final StairChain? draftChain;
  final Offset? draftCursor;       // cursor pixel position during drag preview
  /// When no draftChain exists yet (first edge being drawn), draw ghost from here to draftCursor.
  final Offset? dragGhostStart;
  final String? selectedChainId;
  final double cellSize;

  final Paint edgeFill;
  final Paint nodeFill;
  final Paint selectedFill;
  final Paint stroke;
  final Paint ghostStroke;

  @override
  void paint(Canvas canvas, Size size) {
    for (final chain in chains) {
      final isSelected = chain.id == selectedChainId;
      _drawChain(canvas, chain, isSelected: isSelected);
      if (isSelected) {
        _drawHandles(canvas, chain);
      }
    }
    if (draftChain != null) {
      _drawChain(canvas, draftChain!, isSelected: false, isDraft: true);
      _drawDraftGhost(canvas, draftChain!, draftCursor);
    } else if (dragGhostStart != null && draftCursor != null) {
      _dashedLine(canvas, dragGhostStart!, draftCursor!, ghostStroke);
    }
  }

  void _drawChain(Canvas canvas, StairChain chain, {
    required bool isSelected,
    bool isDraft = false,
  }) {
    if (!chain.isValid) return;
    final polys = ChainGeometry.compute(chain, cellSize);
    final fill  = isSelected ? selectedFill : edgeFill;

    for (var i = 0; i < polys.edges.length; i++) {
      final edge = polys.edges[i];
      final chainEdge = chain.edges[i];
      final steps = chainEdge.stepCount ??
          StairMath.findOptimalN(chainEdge.heightMm, 250.0);
      _fillPoly(canvas, edge.poly, fill);
      _strokePoly(canvas, edge.poly, stroke);
      _drawEdgeDividers(canvas, edge.poly, steps);
    }
    for (var i = 0; i < polys.nodes.length; i++) {
      final node = polys.nodes[i];
      if (node.poly.isEmpty) continue;
      _fillPoly(canvas, node.poly, nodeFill);
      _strokePoly(canvas, node.poly, stroke);
      _drawNodeDividers(canvas, node, chain.nodes[i + 1].stepCount);
    }
    _drawGanglinje(canvas, polys, chain.ganglinjeMode);
  }

  void _drawGanglinje(Canvas canvas, ChainPolygons polys, GanglinjeMode mode) {
    if (polys.edges.isEmpty) return;
    const gangRed = Color(0xFFD32F2F);
    final paint = Paint()
      ..color = gangRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tickPaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.butt;
    const tickHalf = 5.0;

    // For outerstrict/innerstrict, route along the actual wall edge of each
    // straight segment rather than through the centreline midpoints.
    // poly = [EO(0), OMC(1), SO(2), SI(3), IMC(4), EI(5)]
    // Edge poly = [startLeft(0), endLeft(1), endRight(2), startRight(3)]
    // isRightTurn (cr>0): endLeft=EO, endRight=EI; startLeft=SO, startRight=SI
    // !isRightTurn (cr<0): endRight=EO, endLeft=EI; startRight=SO, startLeft=SI
    final outerMode = mode == GanglinjeMode.outerstrict;
    final useWalls  = outerMode || mode == GanglinjeMode.innerstrict;

    // Wall end-face point of edge e at corner node nd (EO for outer, EI for inner).
    Offset wallEnd(EdgeData e, NodeData nd) =>
        (outerMode == nd.isRightTurn) ? e.poly[1] : e.poly[2];

    // Wall start-face point of edge e at corner node nd (SO for outer, SI for inner).
    Offset wallStart(EdgeData e, NodeData nd) =>
        (outerMode == nd.isRightTurn) ? e.poly[0] : e.poly[3];

    void drawTick(Offset pt, Offset dir) {
      final len = dir.distance;
      if (len < 1e-6) return;
      final perp = Offset(-dir.dy, dir.dx) / len;
      canvas.drawLine(pt - perp * tickHalf, pt + perp * tickHalf, tickPaint);
    }

    // Starting point: for wall modes use the outer/inner corner of the first edge's
    // start face (determined by the turn direction of the first corner node).
    final firstEdge = polys.edges.first;
    final firstCornerNode = polys.nodes.isNotEmpty && polys.nodes[0].poly.length == 6
        ? polys.nodes[0] : null;
    final Offset pathStart = (useWalls && firstCornerNode != null)
        ? wallStart(firstEdge, firstCornerNode)
        : firstEdge.ganglinjeStart;

    final path = Path()..moveTo(pathStart.dx, pathStart.dy);

    for (var i = 0; i < polys.edges.length; i++) {
      final e  = polys.edges[i];
      final nd = i < polys.nodes.length ? polys.nodes[i] : null;
      final isCornerNd = nd != null && nd.poly.length == 6;

      // End-face target for this straight segment.
      final Offset edgeEnd = (useWalls && isCornerNd)
          ? wallEnd(e, nd)
          : e.ganglinjeEnd;
      path.lineTo(edgeEnd.dx, edgeEnd.dy);

      if (nd != null && nd.ganglinjeStart != null && nd.ganglinjeEnd != null) {
        // Tick at node entry, perpendicular to the flight direction.
        final entryDir = e.ganglinjeEnd - e.ganglinjeStart;
        drawTick(edgeEnd, entryDir);

        var drawnToEnd = false;
        if (isCornerNd) {
          // poly = [EO(0), OMC(1), SO(2), SI(3), IMC(4), EI(5)]
          final poly = nd.poly;
          switch (mode) {
            case GanglinjeMode.middlestrict:
              final via = (poly[1] + poly[4]) / 2;
              path.lineTo(via.dx, via.dy);
            case GanglinjeMode.innerstrict:
              // EI → IMC → SI  (we arrived at EI via wallEnd; no extra lineTo(EI) needed)
              path..lineTo(poly[5].dx, poly[5].dy)
                  ..lineTo(poly[4].dx, poly[4].dy)
                  ..lineTo(poly[3].dx, poly[3].dy);
              drawnToEnd = true; // ended at SI — wall start of next edge
            case GanglinjeMode.outerstrict:
              // EO → OMC → SO  (we arrived at EO via wallEnd; no extra lineTo(EO) needed)
              path..lineTo(poly[0].dx, poly[0].dy)
                  ..lineTo(poly[1].dx, poly[1].dy)
                  ..lineTo(poly[2].dx, poly[2].dy);
              drawnToEnd = true; // ended at SO — wall start of next edge
            case GanglinjeMode.middlewalk:
              final omc = poly[1];
              final W   = (poly[0] - poly[5]).distance;
              final R   = W / 2;
              if (R < 1e-6) break;
              final entryMid  = (poly[0] + poly[5]) / 2;
              final entryFace = poly[5] - poly[0]; // EI - EO
              final faceLen   = entryFace.distance;
              if (faceLen < 1e-6) break;
              final perpCW    = Offset(entryFace.dy, -entryFace.dx) / faceLen;
              final toOmc     = omc - entryMid;
              final dIn       = (perpCW.dx * toOmc.dx + perpCW.dy * toOmc.dy) >= 0
                  ? perpCW : Offset(-perpCW.dx, -perpCW.dy);
              final t1proj    = toOmc.dx * dIn.dx + toOmc.dy * dIn.dy;
              final t1        = entryMid + dIn * t1proj;
              final sign       = nd.isRightTurn ? 1.0 : -1.0;
              final startAngle = math.atan2(t1.dy - omc.dy, t1.dx - omc.dx);
              final sweepAngle = sign * (nd.turnAngleDeg * math.pi / 180.0);
              path.lineTo(t1.dx, t1.dy);
              path.arcTo(
                Rect.fromCircle(center: omc, radius: R),
                startAngle, sweepAngle, false,
              );
              path.lineTo(nd.ganglinjeEnd!.dx, nd.ganglinjeEnd!.dy);
              drawnToEnd = true;
          }
        }
        if (!drawnToEnd) path.lineTo(nd.ganglinjeEnd!.dx, nd.ganglinjeEnd!.dy);

        // Tick at node exit, perpendicular to the next flight direction.
        if (i + 1 < polys.edges.length) {
          final nextE = polys.edges[i + 1];
          // Exit point: SO (outerstrict), SI (innerstrict), or midpoint otherwise.
          final Offset exitPt = (useWalls && isCornerNd)
              ? (outerMode ? nd.poly[2] : nd.poly[3])
              : nd.ganglinjeEnd!;
          final exitDir = nextE.ganglinjeEnd - nextE.ganglinjeStart;
          drawTick(exitPt, exitDir);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawDraftGhost(Canvas canvas, StairChain chain, Offset? cursor) {
    if (cursor == null || !chain.isValid) return;
    final lastNode = chain.nodes.last;
    final lastPx = Offset(lastNode.gx * cellSize, lastNode.gy * cellSize);
    _dashedLine(canvas, lastPx, cursor, ghostStroke);
  }

  void _drawHandles(Canvas canvas, StairChain chain) {
    final pts = [
      for (final nd in chain.nodes) Offset(nd.gx * cellSize, nd.gy * cellSize),
    ];
    final n = pts.length;
    final borderPaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < n; i++) {
      final Color fill;
      if (i == 0) {
        fill = Colors.white;
      } else if (i == n - 1) {
        fill = Colors.black;
      } else {
        fill = const Color(0xFFFFE0B2);
      }
      canvas.drawCircle(pts[i], 7, Paint()..color = fill..style = PaintingStyle.fill);
      canvas.drawCircle(pts[i], 7, borderPaint);
    }
  }

  /// Interpolate along a two-point edge at parameter t ∈ [0,1].
  static Offset _lerp(Offset a, Offset b, double t) => a + (b - a) * t;

  /// Point at arc-length parameter t ∈ [0,1] along a piecewise linear path.
  static Offset _pointOnPath(List<Offset> pts, double t) {
    double total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += (pts[i + 1] - pts[i]).distance;
    }
    if (total < 1e-6) return pts.first;
    double target = t * total;
    double accum = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      final segLen = (pts[i + 1] - pts[i]).distance;
      if (accum + segLen >= target - 1e-9) {
        final localT = segLen < 1e-9 ? 0.0 : (target - accum) / segLen;
        return _lerp(pts[i], pts[i + 1], localT.clamp(0.0, 1.0));
      }
      accum += segLen;
    }
    return pts.last;
  }

  void _drawNodeDividers(Canvas canvas, NodeData nd, int? stepCount) {
    final poly = nd.poly;
    if (poly.length != 6) return;
    final auto = (nd.turnAngleDeg / 30.0).round().clamp(2, 12);
    final n = stepCount ?? auto;
    if (n <= 1) return;
    // poly = [EO(0), OMC(1), SO(2), SI(3), IMC(4), EI(5)]
    final outer = [poly[0], poly[1], poly[2]]; // EO → OMC → SO
    final eiPt  = poly[5];
    final siPt  = poly[3];
    final inner = [eiPt, poly[4], siPt];       // EI → IMC → SI
    final divPaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 1; i < n; i++) {
      final t = i / n;
      canvas.drawLine(
        _pointOnPath(outer, t),
        _chordProjectOnPath(inner, eiPt, siPt, t),
        divPaint,
      );
    }
  }

  /// Projects chord parameter t (along [a→b]) onto the nearest point on [pts].
  static Offset _chordProjectOnPath(
      List<Offset> pts, Offset a, Offset b, double t) {
    final chord = b - a;
    final len   = chord.distance;
    if (len < 1e-6) return a;
    final u          = chord / len;
    final targetProj = t * len;
    for (var seg = 0; seg < pts.length - 1; seg++) {
      final p0    = pts[seg];
      final p1    = pts[seg + 1];
      final proj0 = (p0 - a).dx * u.dx + (p0 - a).dy * u.dy;
      final proj1 = (p1 - a).dx * u.dx + (p1 - a).dy * u.dy;
      final span  = proj1 - proj0;
      if (span.abs() < 1e-6) continue;
      final localT = (targetProj - proj0) / span;
      if (localT >= -1e-6 && localT <= 1 + 1e-6) {
        return p0 + (p1 - p0) * localT.clamp(0.0, 1.0);
      }
    }
    return pts.last;
  }

  /// Draw n-1 divider lines across the edge polygon.
  /// poly = [startLeft, endLeft, endRight, startRight]
  void _drawEdgeDividers(Canvas canvas, List<Offset> poly, int n) {
    if (n <= 1 || poly.length < 4) return;
    final startLeft  = poly[0];
    final endLeft    = poly[1];
    final endRight   = poly[2];
    final startRight = poly[3];
    final divPaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 1; i < n; i++) {
      final t = i / n;
      final left  = _lerp(startLeft,  endLeft,  t);
      final right = _lerp(startRight, endRight, t);
      canvas.drawLine(left, right, divPaint);
    }
  }

  static void _fillPoly(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.length < 3) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { path.lineTo(p.dx, p.dy); }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _strokePoly(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { path.lineTo(p.dx, p.dy); }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 8.0, gap = 5.0;
    final d = b - a;
    final len = d.distance;
    if (len < 1e-6) return;
    final dir = d / len;
    var t = 0.0;
    while (t < len) {
      final t2 = (t + dash) < len ? t + dash : len;
      canvas.drawLine(a + dir * t, a + dir * t2, paint);
      t = t2 + gap;
    }
  }

  @override
  bool shouldRepaint(ChainPainter old) =>
      old.chains != chains ||
      old.draftChain != draftChain ||
      old.draftCursor != draftCursor ||
      old.dragGhostStart != dragGhostStart ||
      old.selectedChainId != selectedChainId ||
      old.cellSize != cellSize;
}
